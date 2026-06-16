#!/usr/bin/env bash
# Regression tests for DND wake suppression. DND must suppress transport only:
# it does not advance seen.<name>, and off --drain delivers one queued wake.
set -uo pipefail

STITCHPAD_HOME="${STITCHPAD_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STITCHPAD_BIN="$STITCHPAD_HOME/bin/stitchpad"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.stitchpad/.state"

cat > "$T/.stitchpad/stitchpad.md" <<'PAD'
# test pad

```roster
mark | kitty | push | -
dale | kitty | push | -
```

---

## @dale

@mark queued while DND.
PAD

pass=0
fail=0
check() {
  local label="$1"; shift
  if "$@"; then
    echo "  PASS: $label"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label"
    fail=$((fail + 1))
  fi
}

cd "$T" || exit 1

STITCHPAD_NAME=mark "$STITCHPAD_BIN" dnd on >/dev/null
out="$(STITCHPAD_NAME=mark "$STITCHPAD_BIN" wake mark --peek)"
check "DND suppresses wake output" test -z "$out"
check "DND does not advance seen cursor" test ! -f "$T/.stitchpad/.state/seen.mark"

out="$(STITCHPAD_NAME=mark "$STITCHPAD_BIN" dnd off --drain)"
check "off --drain delivers queued wake" sh -c "printf '%s' \"\$1\" | grep -q '@mark queued while DND'" _ "$out"
check "off --drain advances seen cursor once delivered" sh -c "test \"\$(cat \"\$1\")\" = 1" _ "$T/.stitchpad/.state/seen.mark"

out="$(STITCHPAD_NAME=mark "$STITCHPAD_BIN" wake mark --peek)"
check "drained mention does not refire" test -z "$out"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
