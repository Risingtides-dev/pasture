#!/usr/bin/env bash
# Unified launcher for the larry↔chief coordination daemons.
#   larry-watch : fires when Larry writes @chief  → notify chief + ping flag
#   chief-watch : fires when chief writes @larry   → spawn Larry (Pi session)
#
# Usage: .claude/hooks/coord.sh {start|stop|status|restart}
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scratchpad-env.sh"

HOOKS="$PROJECT_DIR/.claude/hooks"
declare -a NAMES=("larry-watch" "chief-watch")

pidfile() { echo "$PROJECT_DIR/.claude/.$1.pid"; }
logfile() { echo "$PROJECT_DIR/.claude/.$1.log"; }
is_running() { local p; p="$(pidfile "$1")"; [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; }

start_one() {
  local name="$1"
  if is_running "$name"; then echo "  $name already running (pid $(cat "$(pidfile "$name")"))"; return; fi
  CLAUDE_PROJECT_DIR="$PROJECT_DIR" nohup bash "$HOOKS/$name.sh" >"$(logfile "$name")" 2>&1 &
  echo $! > "$(pidfile "$name")"
  echo "  started $name (pid $(cat "$(pidfile "$name")"))"
}
stop_one() {
  local name="$1"
  if is_running "$name"; then kill "$(cat "$(pidfile "$name")")" && echo "  stopped $name"; else echo "  $name not running"; fi
  rm -f "$(pidfile "$name")"
}

case "${1:-status}" in
  start)   echo "coord: starting"; for n in "${NAMES[@]}"; do start_one "$n"; done ;;
  stop)    echo "coord: stopping"; for n in "${NAMES[@]}"; do stop_one  "$n"; done ;;
  restart) "$0" stop; sleep 1; "$0" start ;;
  status)
    for n in "${NAMES[@]}"; do
      if is_running "$n"; then echo "  $n: running (pid $(cat "$(pidfile "$n")"))"; else echo "  $n: stopped"; fi
    done ;;
  *) echo "usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
