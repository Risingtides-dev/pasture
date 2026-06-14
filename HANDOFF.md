# stitchpad — HANDOFF

> Read this first. It's the full context for a fresh session to come out firing.
> Last updated: 2026-06-14, end of the session that spun stitchpad out of Librarian.

---

## What stitchpad IS (the one-paragraph pitch)

**stitchpad.md is a self-describing markdown file that acts as a Slack-style channel
for AI coding agents — across any runtime (Claude Code, pi, codex, cline, cursor…).**
The roster of participants lives *inside the file itself* as a fenced ```roster block.
You address a teammate by writing a line that starts with `@name`. A watcher notices
the new mention, looks up that teammate in the roster, and **wakes them**. Every change
is one commit in an isolated git repo, so the whole conversation has blame/diff. A TUI
renders it live like a chat client.

The elegance is the simplicity: **it's just a markdown file + a watcher.** The file
describes its own membership. Open it and you see both who's in the room and the entire
conversation. Any agent joins by adding one line.

It was an accidental tangent — built as coordination plumbing for the Librarian app,
then realized it's its own product. Librarian was handed off clean to a separate agent;
this repo is the spun-out tool.

---

## ⚠️ THE PIVOT (do this — it's the whole point now)

The current implementation wakes agents via **per-runtime hooks + adapters**. That's the
wrong abstraction long-term because hooks are runtime-specific:
- Claude Code: `Stop` / `UserPromptSubmit` hooks in settings.json
- pi: `before_agent_start` extension hook
- codex / cline / cursor: different or none

So today there's a separate adapter per runtime (`adapters/pi.sh`, `adapters/claude.sh`)
and each agent needs bespoke hook wiring. **Not plug-and-play.**

**New direction: TTY/PID-driven wake + expose stitchpad as an MCP server.**

Why this is better:
1. **TTY/PID wake is runtime-agnostic.** Instead of a runtime hook, find the agent's
   terminal session by PID and deliver the nudge directly — write to its controlling
   TTY, or signal the process, or drop into an inbox the agent polls via its MCP tools.
   No per-runtime hook integration. Works the same for every coding agent that runs in
   a terminal.
2. **MCP makes it true plug-and-play.** Any agent that speaks MCP adds the stitchpad MCP
   server, flips it on, and is in the channel — `join`, `say`, `read`, `who` become MCP
   tools. No shell scripts to install, no hooks to wire. Add MCP → turn on → you're a
   teammate.

### What "TTY/PID driven" means concretely (design notes — validate in the new session)
- When an agent joins, record its **PID and controlling TTY** in the roster line (or a
  sidecar the daemon manages). On macOS: `ps -o tty=,pid= -p <pid>`, TTY is under `/dev/`.
- To wake a `pull`-style agent: the agent's MCP server has an `inbox`/`wait_for_mention`
  tool; the daemon flips a flag the MCP server returns on next poll. (Cleanest — no
  writing to foreign TTYs, which is fragile and can corrupt another session's input.)
- To wake a `push`-style agent (spawn a fresh headless session): keep an adapter-like
  spawn, but invoked generically.
- **Caution:** directly injecting keystrokes into another process's TTY is hacky and
  unsafe (it races the user's own typing, can trigger actions). Prefer the MCP-inbox
  pull model. PID/TTY is mainly for *targeting/identifying* the session and for
  notifications, not for forcing input. Decide this deliberately early in the session.

### Net architecture to aim for
```
stitchpad.md  (the bus, roster inside it)
   │
   ├── stitchpad MCP server  ← every agent connects here
   │      tools: join, say, read, who, wait_for_mention (inbox poll)
   │
   └── watcher (fswatch on stitchpad.md)
          on new @mention → mark that teammate's inbox / notify / (optional) spawn
```
The shell CLI + TUI stay as the human-facing side. The MCP server is the agent-facing
side. Both read/write the same stitchpad.md and isolated git.

---

## Current state on disk (`~/stitchpad`)

```
~/stitchpad/
├── HANDOFF.md                     ← you are here
├── tool/
│   ├── bin/
│   │   ├── stitchpad              CLI: init|join|say|watch|start|stop|status|roster|log
│   │   ├── lib.sh                 core: roster parse, isolated git (cgit), mention detect, notify
│   │   ├── watch.sh               the fswatch daemon body  ← HAS A BUG (see tasks)
│   │   ├── daemon.sh              start/stop/status/restart background manager
│   │   ├── tui.sh                 live Slack-style terminal renderer
│   │   └── chatroom-tui           DEAD symlink → old ~/.chatroom (delete it)
│   └── adapters/
│       ├── pi.sh                  push: spawn headless `pi -p -e <ext>` with the task
│       └── claude.sh              pull: drop ping flag + macOS notification
└── reference/                     prior art — DO NOT ship, just study
    ├── librarian-hooks/           the working bash version (chief↔larry, hook-based)
    │     scratchpad-{env,read,end}.sh, larry-watch.sh, chief-watch.sh,
    │     larry-spawn.sh, coord.sh, larry-daemon.sh, README.md
    └── node-watcher/
          watch-larry.js           291-line Node version of the @larry watcher (prior art)
```

### What works RIGHT NOW (verified this session)
- `stitchpad init` — creates `.stitchpad/` (currently still names it/files per the old
  `chatroom` scheme in code — see rename task), writes the self-describing markdown with
  a ```roster block, sets up the isolated git repo (`info/exclude` tracks only the md).
- `stitchpad join <name> <adapter> [wake] [target]` — appends a roster line *inside* the
  markdown. Verified parse-back.
- `stitchpad say <from> <text>` — posts a `## @from · HH:MM` message, auto-commits.
- `stitchpad roster` — parses the in-file ```roster block back out. Verified.
- Mention detection: a TASK line **starts** with `@name` (BSD-awk compatible regex,
  ignores casual inline mentions). Verified: casual mention = 0, real task = 1.
- Daemon dispatch: routes `@name` → correct adapter, push vs pull. Verified with a MOCK
  pi adapter (push fired, task extracted correctly) — BUT see the bug below.
- Isolated git blame trail: verified (`stitchpad log` shows one commit per message).

### Known runtime facts
- `fswatch` is at `/opt/homebrew/bin/fswatch`. `jq` available. No `terminal-notifier`
  (falls back to `osascript`).
- `pi` is a real CLI: `pi -p` (headless), `-e <ext>` (load extension), `--append-system-prompt`.
- The Librarian "larry" pi extension lives at `~/.pi/agent/extensions/larry/index.ts`
  (passive half: injects scratchpad context, gives append/read tools). Left in place for
  the Librarian crew — reference it as a working example of the pi side.
- ⚠️ Two unrelated `fswatch` procs are watching `~/dev/Thoth/` — those are NOT ours
  (predate this work, from a `pi` shell function). Leave them alone.

---

## OPEN TASKS (in priority order)

### 0. (NEW, highest leverage) Re-architect to TTY/PID + MCP — see THE PIVOT above
Start by deciding the wake model (recommend: MCP-inbox pull, PID/TTY for targeting +
notify only, NOT keystroke injection). Then stand up a minimal stitchpad MCP server
exposing `join / say / read / who / wait_for_mention`. This supersedes the hook+adapter
approach as the primary path; keep the CLI/TUI as the human side.

### 1. Rename chatroom → stitchpad throughout the code
The tool was built as "chatroom" and only the `bin/chatroom`→`bin/stitchpad` file was
renamed. Still to do, everywhere in `tool/`:
- `CHATROOM_HOME` → `STITCHPAD_HOME`
- `channel.md` → `stitchpad.md`; `.chatroom/` dir → `.stitchpad/`; `channel-git` → `stitchpad-git`
- `cr_` function prefix → `sp_` (cr_init_paths, cr_roster, cr_count_to, cr_latest_to, cgit, etc.)
- `cr_find_channel` walks up for `.chatroom` → `.stitchpad`
- help text, init template header, all comments
- **delete the dead `tool/bin/chatroom-tui` symlink**; recreate as `stitchpad-tui` → tui.sh

### 2. Fix the watcher bug (`watch.sh`)
Symptom: `watch.sh: line ~56: old�: unbound variable` (note the mojibake byte — the var
name got corrupted). Cause: the inner per-member loop reads from stdin, which belongs to
the `fswatch -0 | while read` pipe, so `read` consumes watch events and mangles vars. A
partial fix (snapshot roster into an array, `react()` function) was applied but did NOT
fully resolve it — re-test showed the same error at the new line number. Finish it:
ensure NOTHING inside the fswatch loop reads from stdin (use `< /dev/null` on inner reads,
or feed roster via a here-string/array, or restructure so fswatch feeds a function that
takes no stdin). Re-run the mock-adapter test (push + pull both fire) until clean.

### 3. Finish/verify the TUI (`tui.sh`)
Live Slack-style render of stitchpad.md: author colors (hash→256-color), roster rail,
unread-ping indicator, re-render on fswatch change, `q` to quit. Built but not fully
verified end-to-end. Confirm it redraws live and the message-block parsing handles the
```roster fence + `## @from · time` headers correctly.

### 4. README + install script
- README: the pitch, the self-describing-markdown design, roster-in-file, @mention→wake,
  MCP plug-and-play story, quickstart.
- Install: symlink `stitchpad` (and `stitchpad-tui`) into PATH; note `STITCHPAD_HOME`.
- Document `reference/` as prior art (bash hook version, node version) — not shipped.

### 5. Migrate Librarian onto it (later, optional)
Once solid + MCP-based: re-add chief + larry to a Librarian `.stitchpad/stitchpad.md` so
the original use case runs on the real tool. Not urgent; Librarian is fine without it.

---

## How to resume (fresh session)
1. `cd ~/stitchpad`
2. Read this file.
3. Decide the pivot (task 0) first — it shapes everything. Recommend MCP-inbox pull model.
4. Then rename (1) → fix watcher (2) so the existing CLI is trustworthy → MCP server → TUI → README.
5. Test harness pattern that worked: init in `/tmp/stitchpad-test`, swap a MOCK adapter
   that just logs, drive with `say`, assert on the log. Don't spawn real `pi` in smoke tests.

## Naming note
"teammate" is taken (Anthropic ships a built-in TeammateTool / Agent Teams). "tick.md"
exists for markdown coordination. **stitchpad** is clear and unclaimed — keep it.
