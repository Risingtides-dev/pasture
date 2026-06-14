#!/usr/bin/env bash
# Chief → Larry trigger daemon.
# Watches the Scratchpad. When a NEW @larry mention appears (chief tasking Larry):
#   1. commits the change to the isolated scratchpad repo,
#   2. spawns a headless Larry (Pi) session via larry-spawn.sh,
#   3. posts a macOS notification.
#
# Run via the launcher:  .claude/hooks/coord.sh start
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

SPAWN="$(dirname "${BASH_SOURCE[0]}")/larry-spawn.sh"
COUNT_FILE="$PROJECT_DIR/.claude/.chief-larry-count"

# A TASK for Larry is a line that STARTS with @larry (optionally bold/quoted),
# e.g. "@larry build F4" or "**@larry**: …". An inline mention ("I'll tag you
# @larry") does NOT count — so casual references never spawn a session.
count_larry() {
  local n
  n=$(grep -icE '^[ >*_-]*@larry' "$SCRATCH" 2>/dev/null) || true
  echo "${n:-0}"
}

notify() {
  local title="$1" msg="$2"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$msg" -sound Submarine 2>/dev/null || true
  else
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Submarine\"" 2>/dev/null || true
  fi
}

echo "$(count_larry)" > "$COUNT_FILE"
echo "[chief-watch] watching $SCRATCH_NAME for new @larry entries (baseline: $(cat "$COUNT_FILE"))"

fswatch -0 "$SCRATCH" | while read -r -d "" _event; do
  new=$(count_larry)
  old=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  if [ "${new:-0}" -gt "${old:-0}" ]; then
    if ! sgit diff --quiet -- "$SCRATCH_NAME" 2>/dev/null; then
      sgit add "$SCRATCH_NAME" 2>/dev/null || true
      sgit commit -q -m "chief → @larry ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null || true
    fi
    echo "[chief-watch] NEW @larry task ($old → $new); spawning Larry…"
    notify "Librarian · Chief → Larry" "Spawning Larry to handle a new @larry task."
    bash "$SPAWN" || echo "[chief-watch] spawn failed"
  fi
  echo "$new" > "$COUNT_FILE"
done
