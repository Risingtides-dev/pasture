#!/usr/bin/env bash
# Background manager for the stitchpad watcher (per pad).
# Usage: daemon.sh {start|stop|status|restart}
set -uo pipefail
_src="${BASH_SOURCE[0]}"; while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  [ "${_src#/}" = "$_src" ] && _src="$_dir/$_src"
done
BIN_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
source "$BIN_DIR/lib.sh"
sp_init_paths || { echo "no .stitchpad here"; exit 1; }

PIDFILE="$PAD_STATE/watch.pid"
LOG="$PAD_STATE/watch.log"
is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-status}" in
  start)
    if is_running; then echo "running (pid $(cat "$PIDFILE"))"; exit 0; fi
    PAD_DIR="$PAD_DIR" nohup bash "$STITCHPAD_HOME/bin/watch.sh" >"$LOG" 2>&1 &
    echo $! > "$PIDFILE"; echo "started stitchpad watcher (pid $(cat "$PIDFILE")); log: $LOG" ;;
  stop)
    if is_running; then kill "$(cat "$PIDFILE")" && echo "stopped"; else echo "not running"; fi
    rm -f "$PIDFILE" ;;
  restart) "$0" stop; sleep 1; "$0" start ;;
  status)  if is_running; then echo "running (pid $(cat "$PIDFILE"))"; else echo "stopped"; fi ;;
  *) echo "usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
