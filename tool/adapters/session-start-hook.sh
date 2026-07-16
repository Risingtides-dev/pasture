#!/usr/bin/env bash
# stitchpad auto-rejoin — claude SessionStart hook. Zero-friction reconnect:
# a restarted claude session re-binds its NEW session id to this pad's sticky
# handle (.state/autoname.claude, written by the MCP join tool), restarts the
# heartbeat, and re-pins the herdr wake target to this pane's terminal id.
# No manual join call needed. Fast no-op when the cwd has no pad or no sticky
# name — costs nothing in non-stitchpad projects.
set -uo pipefail

input="$(cat 2>/dev/null || true)"
jqbin="$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)"
cwd=""; sid=""
if [ -x "$jqbin" ] && [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | "$jqbin" -r '.cwd // empty' 2>/dev/null)"
  sid="$(printf '%s' "$input" | "$jqbin" -r '.session_id // empty' 2>/dev/null)"
fi
[ -n "$cwd" ] || cwd="$PWD"
pad="$cwd/.stitchpad"
[ -d "$pad" ] || exit 0

name=""
[ -f "$pad/.state/autoname.claude" ] && name="$(cat "$pad/.state/autoname.claude" 2>/dev/null | tr -d '[:space:]')"
[ -n "$name" ] || exit 0

bin="$HOME/.stitchpad/bin/stitchpad"
[ -x "$bin" ] || bin="$(command -v stitchpad 2>/dev/null || true)"
[ -n "$bin" ] && [ -x "$bin" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0

# Re-bind THIS session id to the sticky handle (the old binding died with the
# previous session) and restart the heartbeat under the live claude pid.
[ -n "$sid" ] && "$bin" bind-session "$sid" "$name" >/dev/null 2>&1 || true
STITCHPAD_NAME="$name" STITCHPAD_HEARTBEAT_PARENT_PID="$PPID" \
  "$bin" heartbeat start "$name" >/dev/null 2>&1 || true

# Re-pin the push wake target when running in a herdr pane. Terminal ids
# survive pane moves; a restarted terminal gets a fresh id, so always re-pin.
if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ]; then
  hd="$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")"
  if [ -x "$hd" ] && [ -x "$jqbin" ]; then
    term="$("$hd" agent get "$HERDR_PANE_ID" 2>/dev/null | "$jqbin" -r '.result.agent.terminal_id // empty' 2>/dev/null)"
    [ -n "$term" ] && "$bin" set-wake "$name" push "$term" herdr >/dev/null 2>&1 || true
  fi
fi

# stdout becomes session context: remind the agent who it is on this pad.
echo "stitchpad: you are @$name on this project's pad (auto-rejoined — session re-bound, heartbeat live, wake target re-pinned). Use the stitchpad say/read/tasks MCP tools; @$name mentions wake you at turn-end. Do NOT call join again."
exit 0
