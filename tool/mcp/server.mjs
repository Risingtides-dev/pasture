#!/usr/bin/env node
// stitchpad MCP server — the agent-facing side of stitchpad.
//
// The MCP is the ROSTER + TALKING surface. An agent adds this server and, at
// startup, calls `join` to pick its name and declare which runtime it is. The
// runtime's wake hook still needs STITCHPAD_NAME pinned to that name. The MCP
// does NOT do the wake itself.
//
// Tools:
//   join  — add yourself to the roster
//   say   — post a message to the pad (start with @name to address a teammate)
//   read  — read the recent conversation
//   who   — list the roster
//
// There is intentionally no `wait_for_mention`: the wake is the runtime's own
// turn-end hook reading the pad, not an MCP poll. MCP = register + talk; the
// hook does the waking.
//
// All state lives in stitchpad.md + the isolated git, written via the `stitchpad`
// CLI so there is exactly one implementation of roster/commit logic.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import path from "node:path";

const execFileP = promisify(execFile);

// Resolve the stitchpad CLI relative to this file: tool/mcp/server.mjs -> tool/bin/stitchpad
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STITCHPAD_HOME = path.resolve(__dirname, "..");
const CLI = path.join(STITCHPAD_HOME, "bin", "stitchpad");

// Where is the pad? An agent's cwd is the project; the CLI walks up for .stitchpad.
// Allow override via STITCHPAD_CWD (the dir to resolve the pad from).
const PAD_CWD = process.env.STITCHPAD_CWD || process.cwd();

// `me` pins STITCHPAD_NAME for this call so the CLI derives the sender from
// identity, not a trusted arg.
async function sp(args, me) {
  const { stdout, stderr } = await execFileP(CLI, args, {
    cwd: PAD_CWD,
    env: { ...process.env, STITCHPAD_HOME, ...(me ? { STITCHPAD_NAME: me } : {}) },
    maxBuffer: 1024 * 1024,
  });
  return (stdout || "") + (stderr ? `\n${stderr}` : "");
}

// ── Identity, server-side ─────────────────────────────────────────────
// This server process serves exactly ONE agent session. The agent declares its
// name once via join(); we hold it here in memory so say/reply derive the sender
// — the agent never passes a name, so it cannot post as anyone else. We also
// write .state/sessions/<session_id> = name so the (separate) Stop-hook process
// can resolve the same identity from its payload's session_id.
let ME = null;                                   // the joined name; null until join
const SESSION_ID =
  process.env.STITCHPAD_SESSION ||
  process.env.CLAUDE_CODE_SESSION_ID ||
  process.env.CODEX_SESSION_ID ||
  "";

async function bindSession(name) {
  ME = name;
  if (!SESSION_ID) return;                        // no id → hook falls back (see CLI)
  // Ask the CLI where the pad's .state is, then write the session record there.
  await sp(["bind-session", SESSION_ID, name], name).catch(() => {});
}

const server = new Server(
  { name: "stitchpad", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

const TOOLS = [
  {
    name: "join",
    description:
      "Join the stitchpad: pick your handle and declare your runtime. Call once " +
      "at startup. Your runtime's wake hook must also be pinned with " +
      "STITCHPAD_NAME=<your-name> so it knows to deliver messages addressed to " +
      "@you. After joining, you'll be woken at each turn-end whenever someone " +
      "posts a line starting with @your-name.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Your handle in the room, e.g. 'larry'." },
        adapter: {
          type: "string",
          enum: ["claude", "codex", "pi"],
          description:
            "Which runtime you are — selects how you get woken: claude/codex via " +
            "their Stop hook, pi via the pi adapter extension. All read the pad at " +
            "turn-end; no keystrokes are sent to your terminal.",
        },
      },
      required: ["name", "adapter"],
    },
  },
  {
    name: "say",
    description:
      "Post a message to the stitchpad as yourself (the name you joined as — the " +
      "server knows who you are, you cannot post as anyone else). To address a " +
      "teammate and wake them, start your text with @their-name. This is also how " +
      "you reply when the wake hook blocks you with an incoming message.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", description: "The message. Start with @name to address+wake someone." },
      },
      required: ["text"],
    },
  },
  {
    name: "read",
    description: "Read the recent stitchpad conversation.",
    inputSchema: {
      type: "object",
      properties: {
        lines: { type: "number", description: "How many trailing lines to show (default 80).", default: 80 },
      },
    },
  },
  {
    name: "who",
    description: "List who is in the room (the parsed roster).",
    inputSchema: { type: "object", properties: {} },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: a = {} } = req.params;
  try {
    let out;
    switch (name) {
      case "join": {
        const adapter = a.adapter;
        if (!["claude", "codex", "pi"].includes(adapter)) {
          return text("adapter must be one of: claude, codex, pi");
        }
        out = await sp(["join", a.name, adapter, "push", "-"]);
        await bindSession(a.name);   // hold identity + write session record for the hook
        out += `\n(you are @${a.name}; your turn-end hook will wake you on @${a.name} mentions. Reply with the say tool — your identity is fixed server-side.)`;
        break;
      }
      case "say":
        if (!ME) return text("call join first — you have no identity in this stitchpad yet.", true);
        out = await sp(["say", a.text], ME);   // sender derived from server memory, never the agent
        break;
      case "read":
        out = await sp(["read", "-n", String(a.lines || 80)]);
        break;
      case "who":
        out = await sp(["roster"]);
        break;
      default:
        return text(`unknown tool: ${name}`, true);
    }
    return text(out.trim() || "(ok)");
  } catch (err) {
    return text(`stitchpad error: ${err.stderr || err.message}`, true);
  }
});

function text(s, isError = false) {
  return { content: [{ type: "text", text: s }], isError };
}

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("[stitchpad-mcp] ready");
