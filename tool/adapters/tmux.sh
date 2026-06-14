#!/usr/bin/env bash
# stitchpad adapter: tmux (the universal wake).
#
# Every terminal coding agent — Claude Code, codex, cursor, pi, … — runs in a
# tmux pane. tmux can deliver text to any pane from outside as if typed. So the
# wake for ANY runtime is one line: send-keys to that teammate's pane.
#
# Called by the watcher as: tmux.sh mention <to> <stitchpad.md> <taskfile>
# Env: SP_WAKE, SP_TARGET (= tmux pane id, e.g. "main:1.2"), SP_PAD_DIR, SP_PAD_MD
set -uo pipefail
event="$1"; to="$2"; pad_md="$3"; taskfile="$4"
pane="${SP_TARGET:-}"
log="${SP_PAD_DIR}/.state/adapter.tmux.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

[ "$event" = "mention" ] || exit 0
command -v tmux >/dev/null 2>&1 || { echo "[$(ts)] tmux not on PATH" >>"$log"; exit 1; }
[ -n "$pane" ] && [ "$pane" != "-" ] || { echo "[$(ts)] no pane target for @$to (set roster target to a tmux pane id)" >>"$log"; exit 1; }
tmux has-session -t "${pane%%:*}" 2>/dev/null || { echo "[$(ts)] tmux session for pane '$pane' not found" >>"$log"; exit 1; }

# The nudge the agent receives at its prompt. Keep it short and free of shell
# metacharacters (quotes, globs) so it reads cleanly if a shell echoes it. The
# pad itself holds the detail; the agent reads it with: stitchpad read
nudge="stitchpad: @$to you were pinged. Read .stitchpad/stitchpad.md and reply by posting a line that starts with @whoever-pinged-you."

# Deliver it. send-keys types the line; the second send-keys presses Enter.
# Split so a partially-typed human line isn't silently submitted with our text.
tmux send-keys -t "$pane" "$nudge" 2>>"$log" && tmux send-keys -t "$pane" Enter 2>>"$log" \
  && echo "[$(ts)] woke @$to in pane $pane" >>"$log" \
  || echo "[$(ts)] send-keys to pane $pane failed for @$to" >>"$log"
