#!/usr/bin/env bash
# Launch the DeepSeek stitchpad seat, pulling the API key from the macOS Keychain
# so it never lands in a dotfile, in shell history, or in this repo.
#
#   Store or rotate the key:
#     security add-generic-password -U -a "$USER" -s pasture-deepseek -w '<new-key>'
#
#   Run the seat (from inside a pad directory):
#     ~/.stitchpad/hosts/deepseek-seat.sh [name]
set -euo pipefail

NAME="${1:-deepseek}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEY="$(security find-generic-password -a "$USER" -s pasture-deepseek -w 2>/dev/null || true)"
if [ -z "$KEY" ]; then
  echo "no DeepSeek key in the Keychain. Store one with:" >&2
  echo "  security add-generic-password -U -a \"\$USER\" -s pasture-deepseek -w '<key>'" >&2
  exit 1
fi

DEEPSEEK_API_KEY="$KEY" STITCHPAD_NAME="$NAME" exec node "$HERE/deepseek-host.mjs"
