#!/usr/bin/env bash
# Larry → Chief heartbeat daemon.
# Watches the Scratchpad. When a NEW @chief mention appears (Larry pinging you):
#   1. commits the change to the isolated scratchpad repo (so it's blame-able),
#   2. posts a macOS notification,
#   3. writes a .larry-ping flag the pre-turn hook surfaces into your next turn.
#
# Run via the launcher:  .claude/hooks/larry-daemon.sh start
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

COUNT_FILE="$PROJECT_DIR/.claude/.larry-chief-count"

count_chief() {
  local n
  n=$(grep -c "@chief" "$SCRATCH" 2>/dev/null) || true
  echo "${n:-0}"
}

notify() {
  local title="$1" msg="$2"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$msg" -sound Glass 2>/dev/null || true
  else
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Glass\"" 2>/dev/null || true
  fi
}

echo "$(count_chief)" > "$COUNT_FILE"
echo "[larry-watch] watching $SCRATCH_NAME for new @chief entries (baseline: $(cat "$COUNT_FILE"))"

fswatch -0 "$SCRATCH" | while read -r -d "" _event; do
  new=$(count_chief)
  old=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  if [ "${new:-0}" -gt "${old:-0}" ]; then
    # Commit Larry's entry to the isolated repo so it's part of the blame trail.
    if ! sgit diff --quiet -- "$SCRATCH_NAME" 2>/dev/null; then
      sgit add "$SCRATCH_NAME" 2>/dev/null || true
      sgit commit -q -m "larry → @chief ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null || true
    fi
    latest=$(grep "@chief" "$SCRATCH" | tail -1 | cut -c1-120)
    {
      echo "Larry pinged @chief at $(date '+%Y-%m-%d %H:%M:%S')"
      echo "Latest: $latest"
      echo "→ Read $SCRATCH_NAME to see what Larry needs."
    } > "$PING_FLAG"
    notify "Librarian · Larry → Chief" "New @chief ping. Open Claude Code and check the Scratchpad."
    echo "[larry-watch] NEW @chief ping ($old → $new); committed + flagged."
  fi
  echo "$new" > "$COUNT_FILE"
done
