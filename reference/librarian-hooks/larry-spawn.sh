#!/usr/bin/env bash
# Spawn Larry (a Pi agent session) to act on the latest @larry task in the
# Scratchpad. This is the chief → Larry trigger: chief writes an @larry entry,
# the chief-watch daemon detects it and calls this to wake Larry up headlessly.
#
# Larry's pi extension (~/.pi/agent/extensions/larry/index.ts) handles the rest:
# it injects the scratchpad + git diff + latest @larry tasks into Larry's prompt
# and gives him append_to_scratchpad / read_scratchpad tools to reply.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

LARRY_EXT="$HOME/.pi/agent/extensions/larry/index.ts"
SPAWN_LOG="$PROJECT_DIR/.claude/.larry-spawn.log"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

[ -f "$LARRY_EXT" ] || { echo "[$(ts)] larry extension not found at $LARRY_EXT" >> "$SPAWN_LOG"; exit 1; }
command -v pi >/dev/null 2>&1 || { echo "[$(ts)] pi not on PATH" >> "$SPAWN_LOG"; exit 1; }

# Pull the latest @larry TASK block: from the last "## " header that owns a line
# starting with @larry, through end of file. (Mirrors chief-watch's trigger rule.)
task="$(awk '
  /^##/ { sub_start=NR }
  { lines[NR]=$0 }
  tolower($0) ~ /^[ >*_-]*@larry/ { last_task_header=sub_start }
  END {
    if (last_task_header) for (i=last_task_header; i<=NR; i++) print lines[i]
  }
' "$SCRATCH" | tail -80)"
[ -n "$task" ] || task="Check SCRATCHPAD.md for the latest @larry request and act on it."

echo "[$(ts)] spawning Larry for: $(printf '%s' "$task" | tr '\n' ' ' | cut -c1-100)" >> "$SPAWN_LOG"

# Headless, non-interactive Pi session with Larry's extension loaded.
# Larry reads/writes the scratchpad through his own extension hooks + tools.
(
  cd "$PROJECT_DIR" || exit 1
  pi -p \
     -e "$LARRY_EXT" \
     --append-system-prompt "You were just pinged by @chief via the Librarian coordination layer. Read SCRATCHPAD.md, do the frontend work requested, then reply with append_to_scratchpad tagging @chief when done or if blocked." \
     "A new @larry request landed on the Scratchpad. Here it is:

$task

Read the full SCRATCHPAD.md for context, do the work, and write your reply back with append_to_scratchpad (tag @chief)." \
     >> "$SPAWN_LOG" 2>&1
) &
echo "[$(ts)] Larry session launched (pid $!)" >> "$SPAWN_LOG"
