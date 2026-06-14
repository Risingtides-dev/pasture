#!/usr/bin/env bash
# Larry coordination hook — POST-TURN (Stop).
# Two jobs, both non-blocking:
#   1. Auto-commit any Scratchpad edits to the isolated repo so each change
#      becomes a blame-able commit (this is what powers the pre-turn diff).
#   2. If chief replied this turn, consume the ping flag. If not, leave a gentle
#      reminder (NOT a hard block — unrelated turns shouldn't be held hostage).
#
# Always exits 0. Never blocks the stop.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

[ -f "$SCRATCH" ] || exit 0
sgit rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 1. Auto-commit scratchpad edits (if any) to the isolated repo.
if ! sgit diff --quiet -- "$SCRATCH_NAME" 2>/dev/null; then
  sgit add "$SCRATCH_NAME" 2>/dev/null || true
  sgit commit -q -m "scratchpad update ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null || true
  # Chief left an entry → the ping is handled. Clear it and update seen marker.
  rm -f "$PING_FLAG"
  sgit rev-parse HEAD > "$SEEN_SHA" 2>/dev/null || true
  exit 0
fi

# 2. No scratchpad edit this turn. If there was an unconsumed ping, gently remind.
if [ -f "$PING_FLAG" ]; then
  echo "Reminder: Larry pinged @chief and you haven't replied on the Scratchpad yet." >&2
  echo "Consider adding a reply entry to $SCRATCH_NAME before moving on." >&2
fi
exit 0
