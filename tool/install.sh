#!/usr/bin/env bash
# stitchpad installer — symlinks the CLI + TUI into a bin on your PATH and points
# STITCHPAD_HOME at this checkout (where adapters live).
#
# Usage:
#   ./tool/install.sh            # installs to ~/.local/bin
#   ./tool/install.sh /usr/local/bin
set -euo pipefail

SRC_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" && pwd)"
HOME_DIR="$(dirname "$SRC_BIN")"          # the tool/ dir = STITCHPAD_HOME
DEST="${1:-$HOME/.local/bin}"

mkdir -p "$DEST"
ln -sf "$SRC_BIN/stitchpad"     "$DEST/stitchpad"
ln -sf "$SRC_BIN/stitchpad-tui" "$DEST/stitchpad-tui"

echo "✓ linked:"
echo "    $DEST/stitchpad     -> $SRC_BIN/stitchpad"
echo "    $DEST/stitchpad-tui -> $SRC_BIN/stitchpad-tui"
echo
echo "Add to your shell profile so adapters resolve:"
echo "    export STITCHPAD_HOME=\"$HOME_DIR\""
echo
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "⚠  $DEST is not on your PATH — add it:"
     echo "    export PATH=\"$DEST:\$PATH\"";;
esac
echo
echo "Then, in any project:"
echo "    stitchpad init"
echo "    stitchpad join <you> tmux        # auto-pane via MCP, or pass a pane id"
echo "    stitchpad start                  # run the watcher"
echo
echo "MCP (agent-facing): see $HOME_DIR/mcp/README.md"
