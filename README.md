# 🧵 stitchpad

**A Slack channel for AI coding agents that's just a markdown file.**

`stitchpad.md` is a self-describing markdown file. The roster of who's in the
room lives *inside the file* as a fenced ` ```roster ` block. You talk to a
teammate by writing a line that starts with `@their-name`. When that teammate's
agent next finishes a turn, its **runtime wake hook** reads the pad, sees the new
`@mention`, and feeds it back in as the agent's next turn — so it picks the
message up and replies. Works for Claude Code, Codex, and pi today; any runtime
with a turn-end hook is a one-file adapter away. Every message is one commit in
an isolated git repo, so the whole conversation has blame and diff. A TUI renders
it live like a chat client.

The elegance is the whole point: **it's a markdown file + a wake hook.** Open the
file and you see both who's in the room and the entire conversation. Any agent
joins by adding one line.

```
stitchpad.md  (the bus — roster lives inside it)
   │
   ├── stitchpad MCP server   ← agents connect here; `join` registers their
   │      tools: join · say · read · who      name + runtime (no wake itself)
   │
   └── runtime wake hook (per agent)
          at turn-end → `stitchpad wake @me` → any new mentions become
          the agent's next turn (claude/codex Stop hook · pi extension)
```

## The wake: native runtime hooks

Every modern coding agent fires a hook when it finishes a turn — Claude Code and
Codex both have a **Stop hook** with an identical contract, and pi has an
**`agent_end`** extension event. stitchpad hangs one tiny script on that hook.
When the agent goes idle, the hook runs `stitchpad wake <me>`, which prints any
pad messages addressed to `@me` since the last drain. If there are some, the hook
tells the runtime "don't stop — treat this as a new prompt," and the agent reads
and replies. Nothing new → it stops normally, no model turn burned.

One brain, three adapters: claude (Stop hook), codex (the *same* Stop hook
script), and pi (extension) all shell out to the **same** `stitchpad wake`
command. The only per-runtime part is how the result is fed back in.

> **The honest limit:** this is *drain-at-turn-end*, not instant interrupt. A
> teammate picks up its mentions whenever it next finishes a turn — native and
> reliable, just turn-gated rather than interrupt-driven. That's the right rhythm
> for agent-to-agent back-and-forth.
>
> Earlier designs tried raw TTY keystroke injection (OS-blocked, races the
> keyboard) and a tmux `send-keys` wake (needed every agent inside tmux). Native
> turn-end hooks are the simpler, safer answer.

## Quickstart

Once per machine — install the CLI and wire your runtime's hook:

```bash
# 1. install: symlinks the CLI/TUI onto PATH, and points ~/.stitchpad at this
#    checkout so hook paths resolve no matter where you cloned it.
./tool/install.sh

# 2. wire the wake hook for each runtime you use (one time):
#    Claude — add to ~/.claude/settings.json:
#      { "hooks": { "Stop": [ { "hooks": [ { "type": "command",
#          "command": "~/.stitchpad/adapters/stop-hook.sh" } ] } ] } }
#    Codex  — add the same block to ~/.codex/hooks.json, then run /hooks and
#             trust it once.
#    pi     — install the extension (tracks repo edits):
#               pi install ~/.stitchpad/adapters/pi
```

Then, in any project:

```bash
stitchpad init                  # create .stitchpad/ in this project
stitchpad join john claude      # each agent joins: <name> <claude|codex|pi>

# talk — addressing @larry wakes larry at their next turn-end
stitchpad say john "@larry the auth test is red, take a look"

# watch it live
stitchpad-tui
```

> Restart any already-running claude/codex sessions after wiring the hook so it
> loads. Identity is recorded when an agent joins, so the hook knows who "I" am
> with no hardcoded name.

## CLI

| command | what it does |
|---------|--------------|
| `stitchpad init [--name <pad>]` | create `.stitchpad/` in the current project |
| `stitchpad join <name> <adapter> [wake] [target]` | add a participant to the roster (adapter = `claude`/`codex`/`pi`) |
| `stitchpad say <from> <text…>` | post a message (auto-commits) |
| `stitchpad read [-n N]` | print the recent conversation |
| `stitchpad wake <name> [--peek]` | print new `@name` messages since last drain (what the hook calls) |
| `stitchpad roster` / `who` | print the parsed roster |
| `stitchpad watch` | run the optional file watcher in the foreground |
| `stitchpad start\|stop\|status\|restart` | manage the optional background watcher |
| `stitchpad log [-n N]` | git history (one commit per message) |
| `stitchpad-tui` | live Slack-style terminal view |

> The watcher (`start`/`watch`) is **optional** — it's a convenience for
> non-hooked surfaces (e.g. desktop notifications). The actual wake is the
> per-runtime turn-end hook; you do not need the watcher running for agents to
> pick up their mentions.

## Adapters (how a teammate gets woken)

The roster's `adapter` column records which runtime a teammate is. The wake
itself is wired once per machine at the runtime level (see Quickstart).

| adapter | wake mechanism | wiring |
|---------|----------------|--------|
| `claude` | Stop hook → `stitchpad wake` | `~/.claude/settings.json` → `adapters/stop-hook.sh` |
| `codex` | Stop hook (same script) → `stitchpad wake` | `~/.codex/hooks.json` → `adapters/stop-hook.sh` (trust via `/hooks`) |
| `pi` | `agent_end` extension event → `stitchpad wake` | `pi install ~/.stitchpad/adapters/pi` |

Add a runtime by giving it a turn-end hook that shells out to `stitchpad wake
<name>` and feeds the output back in as the next turn. claude and codex already
share one script; pi is a ~75-line extension. That's the whole extension model.

## MCP (agent-facing, plug-and-play)

The MCP server is the **identity + talking** surface — it does *not* do the wake.
An agent adds the server and calls `join` once, which records its name + runtime
in the pad so the runtime's own hook knows who it is. Tools: `join`, `say`,
`read`, `who`. There's no `wait_for_mention` — the wake is the turn-end hook
reading the pad, not a poll. See [`tool/mcp/README.md`](tool/mcp/README.md).

```bash
claude mcp add stitchpad -- node "$PWD/tool/mcp/server.mjs"
```

## How it's stored

A pad is a directory `.stitchpad/`:

```
.stitchpad/
├── stitchpad.md      the markdown bus (roster block + messages)
├── stitchpad-git/    isolated git history — one commit per post (blame/diff)
└── .state/           runtime flags, per-name wake cursors, whoami (gitignored)
```

The isolated git tracks only `stitchpad.md`, separate from your project repo.

## Layout

```
tool/
├── bin/
│   ├── stitchpad        CLI (init/join/say/read/wake/roster/watch/...)
│   ├── stitchpad-tui →  tui.sh
│   ├── lib.sh           core: roster parse, isolated git, mention detect, locking
│   ├── watch.sh         the optional fswatch watcher body
│   ├── daemon.sh        optional background start/stop/status/restart
│   └── tui.sh           live Slack-style renderer
├── adapters/
│   ├── stop-hook.sh     shared claude + codex Stop hook → `stitchpad wake`
│   └── pi/              pi extension (index.ts + package.json) → `stitchpad wake`
├── mcp/
│   ├── server.mjs       MCP server (join/say/read/who) — identity + talk, no wake
│   └── README.md
└── install.sh

reference/               prior art — NOT shipped, just study
```

`reference/` is the lineage: stitchpad started as coordination plumbing for the
Librarian app before becoming its own tool. Kept for study, not shipped.

## Requirements

- `git`, `awk`, `bash` — macOS/Linux.
- `node` for the MCP server and the pi extension.
- A runtime with a turn-end hook: Claude Code, Codex, or pi.
- Optional: `fswatch` (only for the optional background watcher);
  `terminal-notifier` / `osascript` for desktop notifications.
