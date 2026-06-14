#!/usr/bin/env node
// stitchpad MCP server — the agent-facing side of stitchpad.
//
// The whole plug-and-play story: an agent adds this MCP server, and on its first
// `join` the server auto-detects the agent's OWN tmux pane ($TMUX_PANE) and
// writes it into the roster. From then on, `@name` in stitchpad.md wakes that
// exact terminal via `tmux send-keys` (the watcher's tmux adapter). No manual
// pane ids, no per-runtime hooks.
//
// Tools:
//   join  — add yourself to the roster (auto-detects your tmux pane)
//   say   — post a message to the pad
//   read  — read the recent conversation
//   who   — list the roster
//
// There is intentionally no `wait_for_mention`: the wake is push (tmux), not a
// poll. The MCP is for registration + talking; the terminal wake does the rest.
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

async function sp(args) {
  const { stdout, stderr } = await execFileP(CLI, args, {
    cwd: PAD_CWD,
    env: { ...process.env, STITCHPAD_HOME },
    maxBuffer: 1024 * 1024,
  });
  return (stdout || "") + (stderr ? `\n${stderr}` : "");
}

// The caller's own tmux pane, if it's running inside tmux. This is the %N id,
// which `tmux send-keys -t` accepts and which survives window/pane renumbering.
function myPane() {
  return process.env.TMUX_PANE || null;
}

const server = new Server(
  { name: "stitchpad", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

const TOOLS = [
  {
    name: "join",
    description:
      "Join the stitchpad as a participant. Auto-detects your tmux pane so " +
      "`@you` wakes this exact terminal. Call once per session at startup. " +
      "If you are not in tmux, pass adapter='notify' to be pinged without an " +
      "auto-wake.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Your handle in the room, e.g. 'larry'." },
        adapter: {
          type: "string",
          enum: ["tmux", "notify", "pi"],
          description:
            "How you get woken. 'tmux' (default) = send-keys into your pane; " +
            "'notify' = desktop ping only; 'pi' = spawn headless pi.",
          default: "tmux",
        },
        target: {
          type: "string",
          description:
            "Wake target. For tmux, leave blank to auto-use your own pane " +
            "($TMUX_PANE). For pi, the extension path. For notify, ignored.",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "say",
    description:
      "Post a message to the stitchpad. To address a teammate (and wake them), " +
      "start your text with @their-name.",
    inputSchema: {
      type: "object",
      properties: {
        from: { type: "string", description: "Your handle (the name you joined as)." },
        text: { type: "string", description: "The message. Start with @name to address+wake someone." },
      },
      required: ["from", "text"],
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
        const adapter = a.adapter || "tmux";
        let target = a.target || "-";
        if (adapter === "tmux" && (!a.target || a.target === "-")) {
          const pane = myPane();
          if (!pane) {
            return text(
              "Can't auto-detect a tmux pane ($TMUX_PANE is empty) — you're not " +
                "running inside tmux. Either start your session inside tmux, or " +
                "join with adapter='notify'."
            );
          }
          target = pane;
        }
        out = await sp(["join", a.name, adapter, "push", target]);
        out += `\n(addressable as @${a.name}; wake=${adapter}${
          adapter === "tmux" ? ` pane=${target}` : ""
        })`;
        break;
      }
      case "say":
        out = await sp(["say", a.from, a.text]);
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
