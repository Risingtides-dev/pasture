#!/usr/bin/env bash
# stitchpad adapter: notify (fallback for an agent NOT in a tmux pane).
#
# Prefer the tmux adapter — it actually wakes the agent. This one just drops a
# ping flag + desktop notification so a human (or a polling agent) notices. It
# never injects input. Kept as "claude" for back-compat; really it's "notify".
#
# Called by the watcher as: claude.sh mention <to> <stitchpad.md> <taskfile>
# Env: SP_WAKE, SP_TARGET, SP_PAD_DIR, SP_PAD_MD
set -uo pipefail
event="$1"; to="$2"; pad_md="$3"; taskfile="$4"
flag="${SP_PAD_DIR}/.state/ping.$to"

[ "$event" = "mention" ] || exit 0
latest="$(grep -iE "^[ >*_-]*@${to}" "$pad_md" | tail -1 | cut -c1-200)"
{
  echo "Pinged in stitchpad at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Latest: $latest"
  echo "→ Read .stitchpad/stitchpad.md to see what's needed."
} > "$flag"

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "stitchpad · @$to pinged" -message "$latest" -sound Glass 2>/dev/null || true
else
  osascript -e "display notification \"${latest//\"/\\\"}\" with title \"stitchpad · @$to pinged\" sound name \"Glass\"" 2>/dev/null || true
fi
