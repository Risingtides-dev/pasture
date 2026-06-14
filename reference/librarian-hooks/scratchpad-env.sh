#!/usr/bin/env bash
# Shared config for the larry↔chief Scratchpad coordination layer.
# Source this; don't run it. One place for the filename + isolated-repo paths.

# Resolve PROJECT_DIR robustly: prefer the env var Claude Code sets, else derive
# it from THIS script's own location (.claude/hooks/scratchpad-env.sh → up 2).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  _self="${BASH_SOURCE[0]:-$0}"
  PROJECT_DIR="$(cd "$(dirname "$_self")/../.." && pwd)"
fi

# The board file. Resolve case-insensitively (macOS) but use the REAL on-disk name,
# because the isolated git repo's index is case-sensitive.
SCRATCH_NAME="$(cd "$PROJECT_DIR" && ls -1 | grep -i '^scratchpad\.md$' | head -1)"
SCRATCH_NAME="${SCRATCH_NAME:-SCRATCHPAD.md}"
SCRATCH="$PROJECT_DIR/$SCRATCH_NAME"

# Isolated git repo: tracks ONLY the scratchpad, separate history from the project.
SGIT_DIR="$PROJECT_DIR/.claude/scratchpad-git"
# Convenience wrapper: sgit <git args…>
sgit() { git --git-dir="$SGIT_DIR" --work-tree="$PROJECT_DIR" "$@"; }

# Runtime state (all gitignored).
PING_FLAG="$PROJECT_DIR/.claude/.larry-ping"
SEEN_SHA="$PROJECT_DIR/.claude/.scratchpad-seen-sha"
