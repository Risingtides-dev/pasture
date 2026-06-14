#!/usr/bin/env bash
# chatroom core library — sourced by every command/daemon/adapter.
# The whole system is: one markdown file (the channel) whose own header declares
# its roster, plus a generic watcher that fires each user's adapter on @mention.
#
# A channel is a directory with:
#   channel.md     the markdown bus (roster block + messages)
#   channel-git/   isolated git history (one commit per post)
#   .state/        runtime flags/counters (gitignored)
#
# Roster lives INSIDE channel.md as a fenced ```roster block:
#   name | adapter | wake | target
# wake = push (daemon spawns them) | pull (daemon flags+notifies; they read later)

set -uo pipefail

CHATROOM_HOME="${CHATROOM_HOME:-$HOME/.chatroom}"
ADAPTER_DIR="$CHATROOM_HOME/adapters"

# ── Channel resolution ──────────────────────────────────────────────
# Find the channel dir: explicit $CHANNEL_DIR, else nearest .chatroom up the tree.
cr_find_channel() {
  if [ -n "${CHANNEL_DIR:-}" ]; then echo "$CHANNEL_DIR"; return; fi
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.chatroom" ] && { echo "$d/.chatroom"; return; }
    d="$(dirname "$d")"
  done
  return 1
}

cr_init_paths() {
  CHAN_DIR="$(cr_find_channel "${1:-$PWD}")" || { echo "no .chatroom found (run: chatroom init)" >&2; return 1; }
  CHAN_MD="$CHAN_DIR/channel.md"
  CHAN_GIT="$CHAN_DIR/channel-git"
  CHAN_STATE="$CHAN_DIR/.state"
  mkdir -p "$CHAN_STATE"
}

# Isolated git wrapper: history of just channel.md, separate from project repo.
cgit() { git --git-dir="$CHAN_GIT" --work-tree="$CHAN_DIR" "$@"; }

cr_commit() {
  local msg="$1"
  cgit rev-parse --git-dir >/dev/null 2>&1 || return 0
  cgit diff --quiet -- channel.md 2>/dev/null && return 0
  cgit add channel.md 2>/dev/null || true
  cgit commit -q -m "$msg" 2>/dev/null || true
}

# ── Roster parsing (the magic: roster is IN the markdown) ────────────
# Emits "name|adapter|wake|target" per participant from the ```roster fence.
cr_roster() {
  awk '
    /^```roster/ { inblk=1; next }
    /^```/       { inblk=0 }
    inblk {
      line=$0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      n=split(line, f, /[ \t]*\|[ \t]*/)
      if (n>=2) {
        name=f[1]; adapter=f[2];
        wake=(n>=3?f[3]:"pull"); target=(n>=4?f[4]:"-");
        gsub(/^[ \t]+|[ \t]+$/, "", name)
        print name "|" adapter "|" wake "|" target
      }
    }
  ' "$CHAN_MD"
}

# Look up one field for a user. cr_user_field <name> <adapter|wake|target>
cr_user_field() {
  local who="$1" field="$2"
  cr_roster | awk -F'|' -v w="$who" -v f="$field" '
    tolower($1)==tolower(w) {
      if (f=="adapter") print $2;
      else if (f=="wake") print $3;
      else if (f=="target") print $4;
      exit
    }'
}

cr_user_exists() { [ -n "$(cr_user_field "$1" adapter)" ]; }

# ── @mention detection (a TASK line STARTS with @name) ───────────────
# Count lines addressed TO <name> — line begins with @name (allow md punctuation).
cr_count_to() {
  local who="$1"
  local n
  n=$(grep -icE "^[ >*_-]*@${who}([^a-z0-9_-]|$)" "$CHAN_MD" 2>/dev/null) || true
  echo "${n:-0}"
}

# Extract the latest message block addressed to <name>: from the last "## " header
# owning an @name line, through EOF.
cr_latest_to() {
  local who="$1"
  awk -v who="$who" '
    /^##/ { sub_start=NR }
    { lines[NR]=$0 }
    tolower($0) ~ ("^[ >*_-]*@" tolower(who)) { last=sub_start }
    END { if (last) for (i=last;i<=NR;i++) print lines[i] }
  ' "$CHAN_MD"
}

# ── Notifications ────────────────────────────────────────────────────
cr_notify() {
  local title="$1" msg="$2" sound="${3:-Glass}"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$msg" -sound "$sound" 2>/dev/null || true
  else
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"$sound\"" 2>/dev/null || true
  fi
}
