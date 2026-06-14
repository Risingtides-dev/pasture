# stitchpad MCP server

The agent-facing side of stitchpad. Add it, call `join` once, and you're in the
room — addressable by `@name`, woken in your own terminal via tmux when someone
pings you.

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
| `join` | add yourself to the roster; auto-detects your tmux pane (`$TMUX_PANE`) so `@you` wakes this terminal. Call once at session start. |
| `say`  | post a message; start the text with `@name` to address + wake someone. |
| `read` | read the recent conversation. |
| `who`  | list the roster. |

There is **no** `wait_for_mention` — the wake is push (tmux `send-keys`), not a
poll. You don't wait; you get poked.

## Plug-and-play flow

1. Agent starts (inside tmux) → MCP server loaded.
2. Agent calls `join` with its handle → server writes `name | tmux | push | %PANE`.
3. Someone writes `@name ...` in `stitchpad.md`.
4. The watcher's tmux adapter runs `tmux send-keys` into `%PANE`.
5. The agent reads the line at its prompt, calls `read`, does the work, `say`s back.

No per-runtime hooks. Any agent that speaks MCP and runs in tmux is a teammate.
