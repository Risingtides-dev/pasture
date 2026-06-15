#!/usr/bin/env bash
# stitchpad ← Stop-hook shim for Claude Code AND Codex. STABLE: all logic lives in
# `stitchpad hook`, so this file's hash never changes and codex only needs to
# trust it ONCE (via /hooks). Wire it the same in both runtimes:
#   Claude ~/.claude/settings.json · Codex ~/.codex/hooks.json
#     { "hooks": { "Stop": [ { "hooks": [ { "type": "command",
#         "command": "/Users/you/.stitchpad/adapters/stop-hook.sh" } ] } ] } }
# Identity: launch each agent with its name in the env so the hook inherits it —
#   STITCHPAD_NAME=larry codex   ·   STITCHPAD_NAME=dale claude
# (export it in the same shell where you run `stitchpad say` too). The runtime
# pipes its Stop JSON to our stdin; we forward it to the CLI, which does the work.
sp="$(command -v stitchpad 2>/dev/null || true)"
[ -z "$sp" ] && sp="$HOME/.stitchpad/bin/stitchpad"
[ -x "$sp" ] || exit 0
exec "$sp" hook
