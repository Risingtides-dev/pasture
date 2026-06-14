#!/usr/bin/env bash
# stitchpad adapter: pi (push). Spawns a headless Pi agent session loaded with the
# member's extension, handing it the latest message addressed to them.
#
# Called by the watcher as: pi.sh mention <to> <stitchpad.md> <taskfile>
# Env: SP_WAKE, SP_TARGET (= extension path), SP_PAD_DIR, SP_PAD_MD
set -uo pipefail
event="$1"; to="$2"; pad_md="$3"; taskfile="$4"
ext="${SP_TARGET:-}"
log="${SP_PAD_DIR}/.state/adapter.pi.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

[ "$event" = "mention" ] || exit 0
command -v pi >/dev/null 2>&1 || { echo "[$(ts)] pi not on PATH" >>"$log"; exit 1; }
[ -n "$ext" ] && [ -f "${ext/#\~/$HOME}" ] || { echo "[$(ts)] ext missing for @$to: $ext" >>"$log"; exit 1; }
ext="${ext/#\~/$HOME}"

task="$(cat "$taskfile")"
[ -n "$task" ] || task="Check the stitchpad for the latest @$to request and act on it."
echo "[$(ts)] spawning @$to (pi) for: $(printf '%s' "$task" | tr '\n' ' ' | cut -c1-100)" >>"$log"

# Run from the project dir (parent of .stitchpad) so the agent sees the codebase.
proj="$(dirname "$SP_PAD_DIR")"
(
  cd "$proj" || exit 1
  pi -p -e "$ext" \
     --append-system-prompt "You were pinged in the team stitchpad (stitchpad.md). After doing the work, post your reply back to the pad addressed to whoever pinged you (start a line with @their-name)." \
     "You were addressed in the stitchpad:

$task

Do the work, then reply in the pad." \
     >>"$log" 2>&1
) &
echo "[$(ts)] @$to session launched (pid $!)" >>"$log"
