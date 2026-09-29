#!/usr/bin/env bash
# scripts/test-step-04.sh — Step 04 (size feasibility, GATE) check: re-verify
# every claim of the feasibility report (docs/journal/step-04.md):
#   - NuttX common code compiles for the CDP1802 without warnings and links
#     without undefined symbols (only the ROM overflow remains);
#   - the measured sizes (ROM overflow for HW32/32 and beyond 64 KiB);
#   - the compact 64-bit division is correct (with the -Os workaround);
#   - toolchain issue 0002 (wrong code at -Os) and 0003 (hang at -O1) still
#     reproduce, so that a toolchain update that fixes them is noticed.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
fail() { echo "FAIL: $*"; exit 1; }

# 1. The default minimal configuration (-Os + workaround).
scripts/build.sh sim1802:minimal step04-minimal > /dev/null
d=build/step04-minimal/diagnostics.txt
grep -v "will not fit in region\|HW32/32: ROM overflow\|overflowed by" "$d" \
  | grep . && fail "unexpected diagnostics (see $d)"
grep -q "HW32/32: ROM overflow" "$d" || fail "expected the HW32/32 ROM overflow"
rom=$(sed -n 's/^ROM (text+rodata+data) = \([0-9]*\) bytes.*/\1/p' build/step04-minimal/size.txt)
echo "minimal (-Os, workaround): ROM $rom bytes"
[ "$rom" -gt 65536 ] || fail "ROM $rom: the report says the default build exceeds 64 KiB"
grep -q "libgcc.a" build/step04-minimal/size.txt || fail "no libgcc in size report"
libgcc=$(awk '$1=="libgcc.a"{print $6}' build/step04-minimal/size.txt)
[ "$libgcc" -lt 4000 ] || fail "libgcc contributes $libgcc bytes: 64-bit division not replaced?"
echo "ok: compiles cleanly, links except for ROM overflow; libgcc $libgcc bytes"

# 2. The same without the workaround (the smallest -Os measurement).
scripts/build.sh sim1802:minimal step04-minimal-nowa COSMAC_GCC_WORKAROUNDS= > /dev/null
rom2=$(sed -n 's/^ROM (text+rodata+data) = \([0-9]*\) bytes.*/\1/p' build/step04-minimal-nowa/size.txt)
echo "minimal (-Os, no workaround): ROM $rom2 bytes"
[ "$rom2" -gt 32768 ] && [ "$rom2" -lt 65536 ] || fail "ROM $rom2 outside (32 KiB, 64 KiB)"

# 3. 64-bit division vectors with the workaround flag.
D=toolchain/tests/div64; B=build/step04-div64; mkdir -p "$B"
$T-gcc -Os -fno-split-wide-types -Wall -Werror -I$D/shim -DFAR= \
  -Dnoinline_function='__attribute__((noinline))' -D__udivdi3=my_udivdi3 \
  -D__umoddi3=my_umoddi3 -D__divdi3=my_divdi3 -D__moddi3=my_moddi3 \
  -c -o $B/div64.o nuttx/arch/cosmac/src/common/cosmac_div64.c
$T-gcc -Os -fno-split-wide-types -I$D -o $B/div64test.elf $D/div64test.c $B/div64.o
out=$(RUN_TIMEOUT=300 scripts/run.sh $B/div64test.elf) || fail "div64: $out"
echo "ok: $out"

# 4. Toolchain issue 0002 still reproduces (wrong at -Os, fixed by the flag).
I=toolchain/tests/issues/0002
$T-gcc -Os -o $B/i2.elf $I/main.c $I/repro.c
grep -q WRONG <(scripts/run.sh $B/i2.elf) || echo "NOTE: issue 0002 no longer reproduces at -Os"
$T-gcc -Os -fno-split-wide-types -o $B/i2w.elf $I/main.c $I/repro.c
grep -q OK <(scripts/run.sh $B/i2w.elf) || fail "issue 0002 workaround no longer works"
echo "ok: issue 0002 reproducer and workaround"

# 5. Toolchain issue 0003 still reproduces (-O1 does not finish in 30 s).
if timeout 30 $T-gcc -O1 -march=1802 -c -o /dev/null toolchain/tests/issues/0003/lib_getpwbufr.i; then
  echo "NOTE: issue 0003 no longer reproduces at -O1"
else
  echo "ok: issue 0003 (-O1 compile hang) reproduces"
fi
timeout 30 $T-gcc -Os -march=1802 -c -o /dev/null toolchain/tests/issues/0003/lib_getpwbufr.i \
  || fail "issue 0003 reproducer does not compile at -Os"

echo "PASS: step 04"
