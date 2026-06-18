#!/usr/bin/env bash
# stitchpad adapter: kitty (the universal wake).
#
# Every interactive agent — claude, codex, pi — runs in a kitty window. kitty's
# remote control writes text into a window it owns (it owns the pty, so the
# kernel permits it without root and without TIOCSTI, which macOS gates to root).
# This is the on-plan, no-API-bill external wake: the agent stays a normal
# interactive session (claude/codex draw from your subscription, not the metered
# Agent-SDK pool); we just nudge it to take a turn and read the pad.
#
# Called by the watcher as: kitty.sh mention <name> <stitchpad.md> <taskfile>
# Env: SP_TARGET = the agent's kitty address, captured at join as:
#        "<socket>@@<window_id>"  e.g. "unix:/tmp/kitty-thoth-675@@49"
#      (@@ not | — the roster is pipe-delimited, so | would be truncated.)
#      (kitty appends the instance PID to listen_on, and each window exposes its
#       own $KITTY_LISTEN_ON + $KITTY_WINDOW_ID — so the agent records its own.)
#      Back-compat: a bare number is treated as a window id on $KITTY_SOCKET.
#
# Requires (already in this kitty.conf): allow_remote_control socket-only (or yes).
set -uo pipefail
event="$1"; to="$2"; pad_md="$3"; taskfile="$4"
# SP_PAD_DIR may be either the project root (contains .stitchpad/) or the pad dir
# itself (contains stitchpad.md). Normalize once so watcher/adapter agree.
pad_root="${SP_PAD_DIR:-.}"
if [ -f "$pad_root/stitchpad.md" ]; then
  pad_dir="$pad_root"
elif [ -d "$pad_root/.stitchpad" ]; then
  pad_dir="$pad_root/.stitchpad"
else
  pad_dir=".stitchpad"
fi
mkdir -p "$pad_dir/.state" 2>/dev/null || true
log="$pad_dir/.state/adapter.kitty.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }
[ "$event" = "mention" ] || exit 0

kitty_bin="$(command -v kitty 2>/dev/null || echo /Applications/kitty.app/Contents/MacOS/kitty)"
[ -x "$kitty_bin" ] || { echo "[$(ts)] kitty not found" >>"$log"; exit 1; }

target="${SP_TARGET:-}"
case "$target" in
  *"@@"*) sock="${target%%@@*}"; win="${target##*@@}" ;;          # socket@@window_id (normal)
  *)      sock=""; win="" ;;                                       # empty/-/bare → resolve below
esac
# If the recorded kitty socket is stale (common after restart), drop it and
# let the title-based self-heal find the current socket/window.
if [[ "$sock" == unix:* ]]; then
  _sock_path="${sock#unix:}"
  [ -S "$_sock_path" ] || { sock=""; win=""; }
fi

# SELF-HEAL: if no usable target (codex/MCP often can't capture KITTY_WINDOW_ID),
# find the agent's window. Match AUTHORITATIVELY on env.STITCHPAD_NAME first (the
# session itself declares who it is — set by the launcher / agent shell), then
# fall back to the cosmetic title "🧵 <name>". This fixes the drift bug: a window
# titled "🧵 larry" while hosting the dennis SESSION would mis-route under a
# title-only match; env-first routes to whoever the session actually is. Once the
# right window is found we re-stamp the title so the cosmetic drift self-corrects.
# (Fleet without env yet → title fallback keeps working until next respawn.)
if [ -z "$sock" ] || [ -z "$win" ]; then
  # Dynamic socket discovery: try KITTY_SOCKET/KITTY_LISTEN_ON, then find any kitty socket in /tmp/
  sk="${KITTY_SOCKET:-${KITTY_LISTEN_ON:-}}"
  if [ -z "$sk" ]; then
    sk="unix:$(ls /tmp/kitty-* 2>/dev/null | head -1)"
  fi
  # prints "<win_id> <matchkey>" where matchkey is env|title (or empty if none)
  read -r found matchkey <<<"$("$kitty_bin" @ --to "$sk" ls 2>/dev/null | python3 -c '
import sys,json
name=sys.argv[1]
try:
  d=json.load(sys.stdin)
  wins=[w for o in d for t in o["tabs"] for w in t["windows"]]
  # 1. authoritative: a session that declares STITCHPAD_NAME == name
  for w in wins:
    if (w.get("env",{}) or {}).get("STITCHPAD_NAME")==name:
      print(w["id"],"env"); sys.exit()
  # 2. fallback: cosmetic title (legacy fleet with no env set)
  for w in wins:
    if w.get("title","")=="🧵 "+name:
      print(w["id"],"title"); sys.exit()
except Exception: pass' "$to" 2>/dev/null)"
  if [ -n "$found" ]; then sock="$sk"; win="$found"
    echo "[$(ts)] self-healed @$to target via $matchkey match -> win $win" >>"$log"
    # Re-stamp the canonical title on the window we authoritatively found, so a
    # drifted title (e.g. 🧵 larry on a dennis session) self-corrects this wake.
    "$kitty_bin" @ --to "$sk" set-window-title --match "id:$found" "🧵 $to" 2>/dev/null || true
  fi
fi
[ -n "$sock" ] && [ -n "$win" ] || { echo "[$(ts)] no kitty target for @$to (no @@target, no '🧵 $to' window found)" >>"$log"; exit 1; }

# GUARD: never inject into a FOCUSED window — that's the one you're typing in, and
# send-text would interleave with your keystrokes. Skip; the mention stays
# unanswered (engagement gate), so the watcher retries on the next pad change once
# you've clicked away. Set STITCHPAD_FORCE_WAKE=1 to override.
if [ "${STITCHPAD_FORCE_WAKE:-0}" != "1" ]; then
  focused="$("$kitty_bin" @ --to "$sock" ls 2>/dev/null | python3 -c '
import sys,json
try:
  d=json.load(sys.stdin); w=sys.argv[1]
  print(any(str(win["id"])==w and win.get("is_focused") for o in d for t in o["tabs"] for win in t["windows"]))
except: print(False)' "$win" 2>/dev/null)"
  if [ "$focused" = "True" ]; then
    echo "[$(ts)] @$to window $win is focused (you're typing) — deferring wake" >>"$log"
    exit 3   # DEFERRED, not delivered — watcher must NOT consume the gate; retry later
  fi
fi

# Get the canonical wake message from the CLI — same text the stop-hook delivers.
nudge="$(STITCHPAD_NAME="$to" stitchpad wake "$to" --peek 2>/dev/null)"
[ -z "$nudge" ] && nudge="stitchpad: @$to you were pinged — read .stitchpad/stitchpad.md and reply"
# sanitize for send-text (strip chars that break kitty's send-text)
nudge="$(printf '%s' "$nudge" | tr -d '\r\n' | tr -s ' ')"

# Ensure the woken agent's heartbeat ticker is running so alive.<name> stays fresh.
# The agent's own session starts it via sp_maybe_start_heartbeat on any CLI call,
# but a cold wake (no CLI run yet) leaves no ticker → agent decays offline in 90s.
# Running it here from the watcher (which knows the pad dir) closes that gap.
# IMPORTANT: do NOT background this with `( … ) &`. `heartbeat start` already
# forks+disowns its own ticker internally and returns immediately; wrapping it in a
# backgrounded subshell puts the ticker in THIS adapter's process group, which the
# kernel reaps the instant the adapter exits — the ticker dies in <1s and the agent
# decays anyway. Foreground spawn lets the internal disown outlive the adapter.
if [ -n "$pad_dir" ] && [ -f "$pad_dir/stitchpad.md" ]; then
  ( cd "$(dirname "$pad_dir")" && STITCHPAD_NAME="$to" stitchpad heartbeat start "$to" >/dev/null 2>&1 )
  echo "[$(ts)] ensured heartbeat for @$to" >>"$log"
fi

# Submit in two steps: send-text drops the line in the prompt, then a SEPARATE
# send-key enter actually submits it. A trailing \r in send-text does NOT submit
# in agent TUIs (claude/codex/pi use a custom keyboard mode) — it just pastes.
# send-key enter is a real keypress and submits across all three. (verified live)
if "$kitty_bin" @ --to "$sock" send-text --match "id:$win" -- "$nudge" 2>>"$log"; then
  sleep 0.3   # let the TUI register the pasted text before the Enter keypress
  "$kitty_bin" @ --to "$sock" send-key --match "id:$win" enter 2>>"$log"
  echo "[$(ts)] woke @$to via kitty (win $win @ $sock)" >>"$log"
else
  echo "[$(ts)] kitty send-text failed for @$to (win $win @ $sock)" >>"$log"; exit 1
fi
