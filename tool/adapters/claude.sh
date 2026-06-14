#!/usr/bin/env bash
# chatroom adapter: claude (pull). Claude Code is interactive — we can't spawn it
# headless mid-conversation, so we drop a ping flag + desktop notification. The
# Claude Code session's pre-turn hook surfaces the flag on its next turn.
#
# Called by the watcher as: claude.sh mention <to> <channel.md> <taskfile>
set -uo pipefail
event="$1"; to="$2"; chan_md="$3"; taskfile="$4"
flag="${CR_CHAN_DIR}/.state/ping.$to"

[ "$event" = "mention" ] || exit 0
latest="$(grep -iE "^[ >*_-]*@${to}" "$chan_md" | tail -1 | cut -c1-140)"
{
  echo "Pinged in chatroom at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Latest: $latest"
  echo "→ Read .chatroom/channel.md to see what's needed."
} > "$flag"

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "chatroom · @$to pinged" -message "$latest" -sound Glass 2>/dev/null || true
else
  osascript -e "display notification \"${latest//\"/\\\"}\" with title \"chatroom · @$to pinged\" sound name \"Glass\"" 2>/dev/null || true
fi
