#!/usr/bin/env bash
# stitchpad watcher adapter: pi.
# Fired by watch.sh: pi.sh mention <name> <stitchpad.md> <taskfile>
#
# pi normally rosters as `herdr | push | <pane>` (the extension pins that at
# join), so herdr.sh handles the push. This adapter is the fallback for rows
# still on adapter `pi`: when a usable herdr target exists, delegate to
# herdr.sh; otherwise just notify — an external shell can't inject into pi
# without a pane host, so the extension's turn-end drain does the delivery.
#
# Exit contract: 0 delivered · 1 failed · 3 deferred (do not consume the gate).
set -uo pipefail

event="${1:-}"; name="${2:-}"; pad="${3:-}"; taskfile="${4:-}"
[ "$event" = "mention" ] || exit 0
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hd_bin="$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")"
if [ -x "$hd_bin" ] && [ -n "${SP_TARGET:-}" ] && [ "${SP_TARGET:-}" != "-" ] && [ -f "$src/herdr.sh" ]; then
  exec bash "$src/herdr.sh" "$@"
fi

source "$src/../bin/lib.sh" 2>/dev/null || true
msg="$(head -c 240 "$taskfile" 2>/dev/null)"
sp_notify "stitchpad → @$name" "${msg:-new mention}" 2>/dev/null || true
exit 3
