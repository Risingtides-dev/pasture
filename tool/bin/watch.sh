#!/usr/bin/env bash
# chatroom watcher (daemon body). One fswatch on channel.md. On every change:
#   - auto-commit to the isolated channel git
#   - for EACH roster member, if new lines address them (@name), fire their adapter
#
# Adapters live in ~/.chatroom/adapters/<adapter>.sh and are called as:
#   adapter.sh <event> <to> <from-channel.md> <task-text-file>
# where event = "mention". The adapter decides push (spawn) vs pull (flag/notify)
# using the wake mode passed via $CR_WAKE.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cr_init_paths || { echo "no channel"; exit 1; }

# Per-user mention counters live in state.
count_file() { echo "$CHAN_STATE/count.$1"; }

# Seed baselines so we only react to NEW mentions.
while IFS='|' read -r name adapter wake target; do
  [ -n "$name" ] || continue
  echo "$(cr_count_to "$name")" > "$(count_file "$name")"
done < <(cr_roster)

echo "[chatroom] watching $CHAN_MD"
cr_roster | while IFS='|' read -r name adapter wake target; do
  echo "  · @$name → adapter=$adapter wake=$wake"
done

fire_adapter() {
  local name="$1" adapter="$2" wake="$3" target="$4"
  local script="$ADAPTER_DIR/$adapter.sh"
  if [ ! -f "$script" ]; then
    echo "[chatroom] no adapter '$adapter' for @$name (looked in $ADAPTER_DIR)"; return 1
  fi
  local taskfile; taskfile="$(mktemp)"
  cr_latest_to "$name" > "$taskfile"
  CR_WAKE="$wake" CR_TARGET="$target" CR_CHAN_DIR="$CHAN_DIR" CR_CHAN_MD="$CHAN_MD" \
    bash "$script" mention "$name" "$CHAN_MD" "$taskfile" \
    || echo "[chatroom] adapter $adapter failed for @$name"
  rm -f "$taskfile"
}

react() {
  cr_commit "update ($(date '+%H:%M:%S'))"
  # Snapshot the roster into an array so the inner loop doesn't read from stdin
  # (which belongs to the fswatch pipe).
  local -a members=()
  local rline
  while IFS= read -r rline; do members+=("$rline"); done < <(cr_roster)
  local m name adapter wake target new old cf
  for m in "${members[@]}"; do
    IFS='|' read -r name adapter wake target <<< "$m"
    [ -n "$name" ] || continue
    cf="$(count_file "$name")"
    new=$(cr_count_to "$name"); old=$(cat "$cf" 2>/dev/null || echo 0)
    if [ "${new:-0}" -gt "${old:-0}" ]; then
      echo "[chatroom] new @$name mention ($old→$new) → firing $adapter ($wake)"
      fire_adapter "$name" "$adapter" "$wake" "$target"
    fi
    echo "$new" > "$cf"
  done
}

fswatch -0 "$CHAN_MD" | while read -r -d "" _ev; do react; done
