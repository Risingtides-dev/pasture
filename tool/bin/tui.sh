#!/usr/bin/env bash
# chatroom TUI — a live Slack-style terminal view of channel.md.
# Re-renders on every change (fswatch). Color-codes each author, shows the roster
# rail and any unread pings. Read-only viewer; post with `chatroom say`.
#
# Usage: chatroom-tui   (or: tui.sh)   ·  q / Ctrl-C to quit
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cr_init_paths || { echo "no .chatroom here"; exit 1; }

# 256-color palette assigned per author deterministically.
declare -a PALETTE=(39 208 76 170 214 51 199 220 123 141 203 80)
color_for() {  # stable color from name hash
  local s="$1" sum=0 i
  for ((i=0; i<${#s}; i++)); do printf -v o '%d' "'${s:i:1}"; sum=$((sum + o)); done
  echo "${PALETTE[$((sum % ${#PALETTE[@]}))]}"
}
c()    { printf '\033[38;5;%sm' "$1"; }
dim()  { printf '\033[2m'; }
bold() { printf '\033[1m'; }
rst()  { printf '\033[0m'; }

render() {
  clear
  local cols; cols=$(tput cols 2>/dev/null || echo 100)
  local name="$(basename "$(dirname "$CHAN_DIR")")"

  # Header
  bold; c 45; printf '  📣 #%s' "$name"; rst
  dim; printf '   ·   live channel   ·   q to quit\n'; rst
  printf '  '; printf '─%.0s' $(seq 1 $((cols-4))); printf '\n'

  # Roster rail
  printf '  '; dim; printf 'in the room: '; rst
  while IFS='|' read -r rname radapter rwake rtarget; do
    [ -n "$rname" ] || continue
    c "$(color_for "$rname")"; printf '@%s' "$rname"; rst
    dim; printf '(%s) ' "$radapter"; rst
  done < <(cr_roster)
  # unread pings?
  local pings; pings=$(ls "$CHAN_STATE"/ping.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$pings" -gt 0 ] && { c 203; bold; printf '  ● %s unread ping(s)' "$pings"; rst; }
  printf '\n'
  printf '  '; printf '─%.0s' $(seq 1 $((cols-4))); printf '\n\n'

  # Messages: parse "## @from · time" headers, render as chat bubbles.
  awk '
    /^```roster/ { skip=1 }
    /^```/ && skip { skip=0; next }
    skip { next }
    /^## / {
      hdr=$0; sub(/^## /,"",hdr); print "\x01HDR\x01" hdr; next
    }
    /^# / { next }       # title
    /^> / { next }       # blockquote intro
    /^---/ { next }
    { print }
  ' "$CHAN_MD" | {
    while IFS= read -r line; do
      if [[ "$line" == $'\x01HDR\x01'* ]]; then
        hdr="${line#$'\x01HDR\x01'}"
        # "@from · time"  or  "@from → @to · time"
        who="${hdr%% *}"; who="${who#@}"
        printf '\n  '; c "$(color_for "$who")"; bold; printf '%s' "${hdr%% ·*}"; rst
        dim; printf '  %s\n' "${hdr#*· }"; rst
      else
        [ -z "$line" ] && { printf '\n'; continue; }
        printf '      %s\n' "$line"
      fi
    done
  }
  printf '\n'
}

cleanup() { tput cnorm 2>/dev/null; printf '\n'; exit 0; }
trap cleanup INT TERM
tput civis 2>/dev/null   # hide cursor

render
# Re-render on any channel change; also poll keyboard for 'q'.
( fswatch -0 "$CHAN_MD" | while read -r -d "" _; do echo R; done ) &
WATCHER=$!
trap 'kill $WATCHER 2>/dev/null; cleanup' INT TERM
while true; do
  if read -r -t 0.4 -n 1 key 2>/dev/null; then
    [ "$key" = "q" ] && break
  fi
  if kill -0 $WATCHER 2>/dev/null; then
    # drain any render signals quickly
    :
  fi
  # cheap change check: re-render if file mtime changed
  cur=$(stat -f %m "$CHAN_MD" 2>/dev/null || echo 0)
  if [ "${cur:-0}" != "${last:-0}" ]; then render; last="$cur"; fi
done
kill $WATCHER 2>/dev/null
cleanup
