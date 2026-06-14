# Larry ↔ Chief coordination layer

A two-way ping system + blame-able history for the agent conversation on the
Scratchpad. "Chief" = Claude Code (this CLI). "Larry" = the frontend agent.

## The pieces

| File | Role |
|---|---|
| `scratchpad-env.sh` | Shared config (sourced by all). Resolves the real Scratchpad filename + the isolated git repo. |
| `scratchpad-read.sh` | **Pre-turn hook** (`UserPromptSubmit`, `SessionStart`). Injects new Scratchpad commits/diff + any `@chief` ping into chief's context. Silent when nothing changed. |
| `scratchpad-end.sh` | **Post-turn hook** (`Stop`). Auto-commits Scratchpad edits to the isolated repo; clears the ping if chief replied; otherwise leaves a soft reminder. Never blocks. |
| `larry-watch.sh` | **Daemon.** `fswatch` on the Scratchpad. New `@chief` entry → commit to isolated repo + macOS notification + `.larry-ping` flag. |
| `larry-daemon.sh` | `start` / `stop` / `status` / `restart` for the daemon. |

## Two directions

- **Larry → Chief:** Larry writes a line containing `@chief`. The daemon notifies
  + flags; chief's next turn surfaces it via the pre-turn hook.
- **Chief → Larry:** Chief writes a line containing `@larry`. (Delivery via pi's
  agent-trigger mechanism — see task #11, wiring in progress.)

## Isolated git

The Scratchpad has its **own** git repo at `.claude/scratchpad-git/` (separate
git-dir, work-tree = project root, `info/exclude` tracks ONLY the Scratchpad). So
every entry is a commit with real blame/diff, without touching Librarian source
history. Inspect it:

```sh
source .claude/hooks/scratchpad-env.sh
sgit log --oneline        # history of the conversation
sgit diff HEAD~1          # what changed in the last entry
```

## Running it

```sh
.claude/hooks/larry-daemon.sh start    # start the heartbeat watcher
.claude/hooks/larry-daemon.sh status
```

The turn hooks fire automatically (wired in `.claude/settings.json`). Runtime
state files (`.larry-ping`, `.larry-watch.pid/log`, `.scratchpad-seen-sha`, the
isolated repo) are gitignored.
