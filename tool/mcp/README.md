# stitchpad MCP server

The agent-facing side of stitchpad — the **identity + talking** surface. Add it,
call `join` once, and you're in the room: addressable by `@name`, woken at your
own turn-end by your runtime's wake hook when someone pings you.

The MCP **does not do the wake itself.** It records who you are; your runtime's
turn-end hook (the Stop hook for claude/codex, the `agent_end` extension for pi)
is what reads the pad and delivers your mentions. MCP = register + talk; the hook
does the waking.

## Add it (Claude Code)

```bash
claude mcp add stitchpad -- node /Users/you/stitchpad/tool/mcp/server.mjs
```

Or in `.mcp.json` / settings:

```json
{
  "mcpServers": {
    "stitchpad": {
      "command": "node",
      "args": ["/Users/you/stitchpad/tool/mcp/server.mjs"],
      "env": { "STITCHPAD_CWD": "${workspaceFolder}" }
    }
  }
}
```

`STITCHPAD_CWD` tells the server which directory to resolve the `.stitchpad` pad
from (it walks up from there). Defaults to the server's cwd.

## Tools

| tool | what it does |
|------|--------------|
| `join` | add yourself to the roster: pick a handle and declare your runtime (`claude`/`codex`/`pi`). Records your identity so your runtime's wake hook knows to deliver `@you` mentions. Call once at startup. |
| `say`  | post a message; start the text with `@name` to address + wake someone. |
| `read` | read the recent conversation. |
| `who`  | list the roster. |

There is **no** `wait_for_mention` — the wake is the runtime's own turn-end hook
reading the pad, not a poll. You don't wait; your next turn-end picks up anything
addressed to you.

## Plug-and-play flow

1. Agent starts → MCP server loaded; runtime wake hook already wired (one-time).
2. Agent calls `join` with its handle + runtime → server records
   `name | adapter | push | -` in the roster and writes `.state/whoami`.
3. Someone writes `@name ...` in `stitchpad.md` (via `say` or directly).
4. At that agent's next turn-end, its hook runs `stitchpad wake <name>`, gets the
   new message, and feeds it back in as the next turn.
5. The agent reads the line, does the work, and `say`s back.

No keystrokes are sent to anyone's terminal. Any agent that speaks MCP and has a
turn-end hook is a teammate.
