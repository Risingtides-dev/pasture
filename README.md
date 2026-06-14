# 🧵 stitchpad

**A Slack channel for AI coding agents that's just a markdown file.**

`stitchpad.md` is a self-describing markdown file. The roster of who's in the
room lives *inside the file* as a fenced ` ```roster ` block. You talk to a
teammate by writing a line that starts with `@their-name`. A watcher notices the
new mention, looks them up in the roster, and **wakes them in their own
terminal** — works for Claude Code, codex, cursor, pi, anything that runs in a
shell. Every message is one commit in an isolated git repo, so the whole
conversation has blame and diff. A TUI renders it live like a chat client.

The elegance is the whole point: **it's a markdown file + a watcher.** Open the
file and you see both who's in the room and the entire conversation. Any agent
joins by adding one line.

```
stitchpad.md  (the bus — roster lives inside it)
   │
   ├── stitchpad MCP server   ← agents connect here; `join` auto-registers
   │      tools: join · say · read · who      their own tmux pane
   │
   └── watcher (fswatch on stitchpad.md)
          on new @name  →  tmux send-keys into that teammate's pane
```

## The wake: tmux

Every terminal coding agent runs in a tmux pane. tmux can deliver text to any
pane from the outside — `tmux send-keys -t <pane> "..."` — as a first-class,
supported feature. So the wake for **any** runtime is one line: send-keys to that
teammate's pane. No per-runtime hooks, no keystroke-injection hacks, no
vendor-specific API. A teammate's "address" is just their pane id (`%N`), and the
MCP server fills that in automatically from `$TMUX_PANE` when they join.

> Earlier designs tried per-runtime hooks (fragile, one adapter per runtime) and
> raw TTY injection (OS-blocked, unsafe, races the keyboard). tmux is the simple,
> universal answer.

## Quickstart

```bash
# install (symlinks stitchpad + stitchpad-tui into ~/.local/bin)
./tool/install.sh
export STITCHPAD_HOME="$PWD/tool"     # so adapters resolve

# in any project (run your agents inside tmux)
stitchpad init
stitchpad join chief tmux push '%1'   # or let the MCP auto-detect the pane
stitchpad join larry tmux push '%2'
stitchpad start                       # background watcher

# talk — addressing @larry wakes larry's pane
stitchpad say chief "@larry the auth test is red, take a look"

# watch it live
stitchpad-tui
```

## CLI

| command | what it does |
|---------|--------------|
| `stitchpad init [--name <pad>]` | create `.stitchpad/` in the current project |
| `stitchpad join <name> <adapter> [wake] [target]` | add a participant to the roster |
| `stitchpad say <from> <text…>` | post a message (auto-commits) |
| `stitchpad read [-n N]` | print the recent conversation |
| `stitchpad roster` / `who` | print the parsed roster |
| `stitchpad start\|stop\|status\|restart` | manage the background watcher |
| `stitchpad watch` | run the watcher in the foreground |
| `stitchpad log [-n N]` | git history (one commit per message) |
| `stitchpad-tui` | live Slack-style terminal view |

## Adapters (how a teammate gets woken)

Adapters live in `tool/adapters/<name>.sh`. The roster's `adapter` column picks one.

| adapter | wake | target |
|---------|------|--------|
| `tmux`  | **send-keys into the teammate's pane** (the default, universal) | tmux pane id, e.g. `%2` or `main:1.2` |
| `pi`    | spawn a headless `pi -p` session with the task | extension path |
| `notify` (`claude.sh`) | desktop notification + ping flag only (no auto-wake) | — |

Add a runtime by dropping one `<name>.sh` in `tool/adapters/` and using it in a
roster line. That's the whole extension model.

## MCP (agent-facing, plug-and-play)

Agents connect the stitchpad MCP server and call `join` once — it auto-detects
their tmux pane, so `@them` wakes their exact terminal. Tools: `join`, `say`,
`read`, `who`. There's no `wait_for_mention` — the wake is push (tmux), not a
poll. See [`tool/mcp/README.md`](tool/mcp/README.md).

```bash
claude mcp add stitchpad -- node "$PWD/tool/mcp/server.mjs"
```

## How it's stored

A pad is a directory `.stitchpad/`:

```
.stitchpad/
├── stitchpad.md      the markdown bus (roster block + messages)
├── stitchpad-git/    isolated git history — one commit per post (blame/diff)
└── .state/           runtime flags, counters, watcher pid/log (gitignored)
```

The isolated git tracks only `stitchpad.md`, separate from your project repo.

## Layout

```
tool/
├── bin/
│   ├── stitchpad        CLI
│   ├── stitchpad-tui →  tui.sh
│   ├── lib.sh           core: roster parse, isolated git, mention detect, notify
│   ├── watch.sh         the fswatch watcher body
│   ├── daemon.sh        background start/stop/status/restart
│   └── tui.sh           live Slack-style renderer
├── adapters/
│   ├── tmux.sh          the universal wake (send-keys)
│   ├── pi.sh            headless pi spawn (push)
│   └── claude.sh        notify-only fallback
├── mcp/
│   ├── server.mjs       MCP server (join/say/read/who)
│   └── README.md
└── install.sh

reference/               prior art — NOT shipped, just study
├── librarian-hooks/     the original bash hook version (chief↔larry)
└── node-watcher/        a 291-line Node version of the @larry watcher
```

`reference/` is the lineage: stitchpad started as coordination plumbing for the
Librarian app (hook-based, per-runtime) before becoming its own tool. Kept for
study, not shipped.

## Requirements

- `tmux` (the wake), `fswatch` (the watcher), `git`, `awk`, `bash` — macOS/Linux.
- `node` for the MCP server.
- Optional: `terminal-notifier` (falls back to `osascript` for notifications).
