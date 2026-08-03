#!/usr/bin/env node
// stitchpad deepseek-host — run DeepSeek as an AUTONOMOUS stitchpad teammate.
//
// Why this exists: DeepSeek has no CLI runtime and therefore no turn-end hook,
// so it can never be a `pull` member. Like pi-host, this host OWNS the loop:
// poll the pad, and when a mention lands, run a DeepSeek completion and post the
// reply back. The loop is the enforcement — the same guarantee claude/codex get
// from their Stop hook.
//
//   DEEPSEEK_API_KEY=… STITCHPAD_NAME=deepseek \
//     node ~/.stitchpad/hosts/deepseek-host.mjs        (run inside a pad dir)
//
// Roster shape: `deepseek | push | -`  — the watcher must never try to wake it;
// this host is the only delivery path.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const exec = promisify(execFile);

// Resolve the CLI explicitly. Falling back to a bare "stitchpad" is a trap: if it
// isn't on PATH every call fails with ENOENT, which is indistinguishable from
// "no new mentions" and the seat hangs silently forever. Prefer the checkout we
// ship inside, then the installed home, then PATH — and preflight it below.
const HERE = dirname(fileURLToPath(import.meta.url));
const SP =
  process.env.STITCHPAD_BIN ||
  [join(HERE, "../bin/stitchpad"), join(homedir(), ".stitchpad/bin/stitchpad")]
    .find((p) => existsSync(p)) ||
  "stitchpad";

const NAME = process.env.STITCHPAD_NAME;
const KEY = process.env.DEEPSEEK_API_KEY;
const MODEL = process.env.DEEPSEEK_MODEL || "deepseek-v4-pro";
const BASE = process.env.DEEPSEEK_BASE_URL || "https://api.deepseek.com";
const IDLE_MS = Number(process.env.STITCHPAD_POLL_MS || 4000);
const MAX_TURNS = Number(process.env.DEEPSEEK_HISTORY_TURNS || 24);

if (!NAME) { console.error("set STITCHPAD_NAME=<your handle>"); process.exit(1); }
if (!KEY) { console.error("set DEEPSEEK_API_KEY (never hardcode it)"); process.exit(1); }

// A nonzero exit with output is normal for `wake` (it signals "blocked"), so we
// read stdout off the error too. But an ENOENT/spawn failure means the CLI isn't
// there at all — that must be fatal, never an empty string.
const sp = async (args) => {
  try {
    const r = await exec(SP, args, { env: { ...process.env, STITCHPAD_NAME: NAME } });
    return (r.stdout || "").trim();
  } catch (e) {
    if (e?.code === "ENOENT" || e?.code === "EACCES") {
      console.error(`[deepseek-host] cannot run stitchpad CLI at "${SP}" (${e.code}).`);
      console.error(`  Install it (tool/install.sh) or set STITCHPAD_BIN=/path/to/stitchpad`);
      process.exit(1);
    }
    return (e?.stdout || "").trim();
  }
};

// Persona is a system-prompt fragment, same convention as the other seats.
const personaPath = join(homedir(), ".stitchpad/personas", `${NAME}.md`);
const persona = existsSync(personaPath) ? readFileSync(personaPath, "utf8") : "";

const SYSTEM = [
  `You are @${NAME}, a teammate on a stitchpad — a shared markdown channel where`,
  `CLI coding agents collaborate. You receive the pad excerpts addressed to you.`,
  `Reply with the message body only: no preamble, no "as @${NAME}", no markdown`,
  `fences around the whole reply. Address a teammate by starting a line with`,
  `@their-name; that is what wakes them. Be concise — this is a chat channel,`,
  `not a document. If you have nothing useful to add, say so in one line.`,
  persona && `\nYour standing role:\n${persona}`,
].filter(Boolean).join("\n");

const history = [];

async function complete(messages) {
  const res = await fetch(`${BASE}/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${KEY}` },
    body: JSON.stringify({ model: MODEL, messages, stream: false }),
  });

  if (!res.ok) {
    throw new Error(`deepseek ${res.status}: ${(await res.text()).slice(0, 300)}`);
  }

  const choice = (await res.json())?.choices?.[0];
  const reply = choice?.message?.content?.trim();
  // v4 models are reasoners: they can burn the turn on reasoning_content and
  // hand back empty content. Observed rarely and non-deterministically, so it's
  // worth one retry before telling the room something broke.
  if (!reply) throw new Error(`empty completion (finish_reason=${choice?.finish_reason})`);
  return reply;
}

async function respond(mention) {
  history.push({ role: "user", content: mention });
  while (history.length > MAX_TURNS) history.shift();

  const messages = [{ role: "system", content: SYSTEM }, ...history];
  let reply;
  for (let attempt = 1; ; attempt++) {
    try {
      reply = await complete(messages);
      break;
    } catch (e) {
      if (attempt >= 3) throw e;
      console.error(`[deepseek-host] attempt ${attempt} failed (${e.message}) — retrying`);
      await new Promise((r) => setTimeout(r, 1000 * attempt));
    }
  }

  history.push({ role: "assistant", content: reply });
  return reply;
}

// Register identity so `wake` resolves us, and mark the seat push/unwakeable.
await sp(["join", NAME, "deepseek", "push", "-"]);
await sp(["bind-session", "-", NAME]);
console.error(`[stitchpad deepseek-host] @${NAME} online (${MODEL}) — watching the pad`);

let stop = false;
for (const s of ["SIGINT", "SIGTERM"]) {
  process.on(s, async () => { stop = true; await sp(["leave", NAME]); process.exit(0); });
}

while (!stop) {
  const mention = await sp(["wake", NAME]);
  if (!mention) {
    await new Promise((r) => setTimeout(r, IDLE_MS));   // ponytail: poll, not a socket.
    continue;
  }
  try {
    await sp(["say", await respond(mention)]);
  } catch (e) {
    console.error("[deepseek-host] turn error:", e?.message);
    // Tell the room rather than dying silently — a mute teammate looks like a hang.
    await sp(["say", `(@${NAME} host error: ${e?.message ?? "unknown"})`]);
  }
}
