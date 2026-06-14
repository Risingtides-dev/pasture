#!/usr/bin/env bash
# Start/stop/status for the larry-watch heartbeat daemon.
# Usage: .claude/hooks/larry-daemon.sh {start|stop|status|restart}
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

WATCH="$PROJECT_DIR/.claude/hooks/larry-watch.sh"
PIDFILE="$PROJECT_DIR/.claude/.larry-watch.pid"
LOG="$PROJECT_DIR/.claude/.larry-watch.log"

is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-status}" in
  start)
    if is_running; then echo "already running (pid $(cat "$PIDFILE"))"; exit 0; fi
    CLAUDE_PROJECT_DIR="$PROJECT_DIR" nohup bash "$WATCH" >"$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    echo "started larry-watch (pid $(cat "$PIDFILE")); log: $LOG"
    ;;
  stop)
    if is_running; then kill "$(cat "$PIDFILE")" && echo "stopped"; else echo "not running"; fi
    rm -f "$PIDFILE"
    ;;
  restart) "$0" stop || true; sleep 1; "$0" start ;;
  status)
    if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; fi
    ;;
  *) echo "usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
