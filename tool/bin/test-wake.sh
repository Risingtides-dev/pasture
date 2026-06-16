#!/usr/bin/env bash
# Standalone regression tests for the content-based wake gate (sp_engagement).
# No framework — plain asserts. Run: bash ~/.stitchpad/bin/test-wake.sh
# Guards: the self-ack loop fix, daemon-race immunity (content not git subjects),
# handle boundaries, and the silent-ack (./[ack]) convention.
set -uo pipefail
source "$HOME/.stitchpad/bin/lib.sh"

T="$(mktemp -d)"; export PAD_MD="$T/pad.md"
pass=0; fail=0
check() { # <label> <expected "M R"> <pad-content>
  printf '%s' "$3" > "$PAD_MD"
  local got; got="$(sp_engagement mark)"
  if [ "$got" = "$2" ]; then echo "  PASS: $1"; pass=$((pass+1))
  else echo "  FAIL: $1 (exp='$2' got='$got')"; fail=$((fail+1)); fi
}

# ── core loop gate ─────────────────────────────────────────────
check "self-ack after real reply releases" "1 3" '## @larry
@mark you there?

## @mark
@larry yes.

## @mark
@mark self-ack idle.'

check "new real mention after reply fires" "4 3" '## @larry
@mark you there?

## @mark
@larry yes.

## @mark
@mark self-ack.

## @larry
@mark one more?'

check "my bare unaddressed post does not clear" "1 0" '## @dale
@mark look at this.

## @mark
(note) thinking.'

check "multi-target @larry @mark wakes mark" "2 1" '## @mark
@dale earlier.

## @dale
@larry @mark both check.'

check "handle boundary: @markus does not wake mark" "0 1" '## @mark
@dale hi.

## @dale
@markus is someone else.'

# ── silent-ack convention ──────────────────────────────────────
# a silent .ack BY ME clears my own gate (it is my acknowledgement) — this is the
# fix for the storm where self-acks never advanced the gate and re-fired forever.
check "my own silent .ack clears my pending mention" "1 2" '## @dale
@mark real question?

## @mark
.ack got it'

# but a silent .ack does NOT count as an addressed reply that would let me ignore a
# LATER real mention — a fresh real mention after my ack still fires.
check "real mention after my .ack still fires" "3 2" '## @dale
@mark real question?

## @mark
.ack got it

## @dale
@mark actually one more thing?'

check "silent [ack] mentioning me does not wake me" "0 1" '## @mark
@dale earlier.

## @dale
[ack] thanks @mark.'

check "normal mention still wakes (control)" "2 1" '## @mark
@dale earlier.

## @dale
@mark thanks.'

# ── P4: quoted/referenced @name is NOT an address ──────────────
# a @name inside referenced text (after punctuation like / ` ") must not wake them.
check "quoted-mention reference does not wake" "0 1" '## @mark
@dale hi.

## @dale
recapping the @larry/@mark/@dale discussion for context.'

check "backticked @mention does not wake" "0 1" '## @mark
@dale hi.

## @dale
the gate matched `@mark` literally in code.'

# real addresses must still fire after the tightening (controls)
check "address chain still wakes (@larry @mark)" "2 1" '## @mark
@dale earlier.

## @dale
@larry @mark both look.'

check "mid-sentence address still wakes" "2 0" '## @larry
@mark hi.

## @larry
hey @mark can you check this?'

# ── P5: @name inside a fenced code block is NOT an address ──────
# doctor output / diffs / code pastes list "@name" but address nobody.
check "fenced-code @mention does not wake" "0 0" '## @dale
roster doctor:
```
  ✓ @mark (kitty/push) — healthy
  ✓ @dale (kitty/push) — healthy
```
all good.'

# a real address OUTSIDE the fence in the same block still wakes
check "address outside fence still wakes despite fenced listing" "2 1" '## @mark
@dale earlier.

## @dale
@mark see the report:
```
  ✓ @mark — healthy
```'

echo
echo "RESULT: $pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
