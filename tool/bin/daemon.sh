#!/usr/bin/env bash
# Background manager for the chatroom watcher (per channel).
# Usage: daemon.sh {start|stop|status|restart}
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cr_init_paths || { echo "no .chatroom here"; exit 1; }

PIDFILE="$CHAN_STATE/watch.pid"
LOG="$CHAN_STATE/watch.log"
is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-status}" in
  start)
    if is_running; then echo "running (pid $(cat "$PIDFILE"))"; exit 0; fi
    CHANNEL_DIR="$CHAN_DIR" nohup bash "$CHATROOM_HOME/bin/watch.sh" >"$LOG" 2>&1 &
    echo $! > "$PIDFILE"; echo "started chatroom watcher (pid $(cat "$PIDFILE")); log: $LOG" ;;
  stop)
    if is_running; then kill "$(cat "$PIDFILE")" && echo "stopped"; else echo "not running"; fi
    rm -f "$PIDFILE" ;;
  restart) "$0" stop; sleep 1; "$0" start ;;
  status)  if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; fi ;;
  *) echo "usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
