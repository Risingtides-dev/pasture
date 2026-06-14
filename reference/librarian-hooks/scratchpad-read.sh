#!/usr/bin/env bash
# Larry coordination hook — PRE-TURN (UserPromptSubmit + SessionStart).
# Surfaces NEW activity on the Scratchpad (from the isolated scratchpad git repo)
# so chief never misses a message from Larry. Stays quiet when nothing changed,
# so it doesn't spam context on unrelated turns.
#
# stdout = context injected into the turn.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

[ -f "$SCRATCH" ] || exit 0
sgit rev-parse --git-dir >/dev/null 2>&1 || exit 0   # isolated repo not set up yet

current_sha="$(sgit rev-parse HEAD 2>/dev/null || echo none)"
seen_sha="$(cat "$SEEN_SHA" 2>/dev/null || echo none)"

has_ping=0; [ -f "$PING_FLAG" ] && has_ping=1
# Also treat an uncommitted scratchpad edit as "new" (Larry may not auto-commit).
dirty=0; sgit diff --quiet -- "$SCRATCH_NAME" 2>/dev/null || dirty=1

# Nothing new and no ping → stay silent.
if [ "$current_sha" = "$seen_sha" ] && [ "$has_ping" -eq 0 ] && [ "$dirty" -eq 0 ]; then
  exit 0
fi

echo "=== SCRATCHPAD: new activity since you last looked ==="
echo "File: $SCRATCH_NAME  (isolated repo: .claude/scratchpad-git)"
echo

if [ "$has_ping" -eq 1 ]; then
  echo "*** ⚠️  LARRY PINGED @chief — heartbeat ***"
  cat "$PING_FLAG"
  echo
fi

if [ "$dirty" -eq 1 ]; then
  echo "--- UNCOMMITTED edits to the Scratchpad (git diff) ---"
  sgit diff -- "$SCRATCH_NAME" 2>/dev/null | head -120
  echo
fi

if [ "$current_sha" != "$seen_sha" ] && [ "$current_sha" != "none" ]; then
  echo "--- New commits since your last turn ---"
  if [ "$seen_sha" = "none" ]; then
    sgit log -1 --format='%h  %an  %ar%n%s' 2>/dev/null
  else
    sgit log --format='%h  %an  %ar%n%s' "${seen_sha}..${current_sha}" 2>/dev/null | head -40
    echo
    echo "--- Diff of those commits ---"
    sgit diff "${seen_sha}..${current_sha}" -- "$SCRATCH_NAME" 2>/dev/null | head -120
  fi
  echo
fi

# Recent @chief mentions so they can't be skimmed past.
if grep -n "@chief" "$SCRATCH" >/dev/null 2>&1; then
  echo "--- recent @chief lines ---"
  grep -n "@chief" "$SCRATCH" | tail -5
  echo
fi

echo "ACTION: Read the relevant part of $SCRATCH_NAME, handle what Larry needs, and"
echo "leave a reply entry before you finish (the scratchpad auto-commits on save)."

# Mark this state as seen so we don't re-surface it next turn.
echo "$current_sha" > "$SEEN_SHA"
exit 0
