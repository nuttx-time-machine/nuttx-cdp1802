#!/usr/bin/env bash
# scripts/test-step-03.sh — Step 03 exit check: the sim1802 virtual board
# (docs/cdp1802/board-sim1802.md, ADR 0005) behaves as documented, in both
# memory profiles, on the pinned simulator fork.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
D=toolchain/tests/board
B=build/board
mkdir -p "$B"
fail() { echo "FAIL: $*"; exit 1; }
link() { $T-gcc -nostdlib -nostartfiles -T "$D/$1.ld" -o "$B/$2.elf" "${@:3}"; }

# The simulator fork itself (ADR 0003).
scripts/test-sim-fork.sh | tail -1

for p in hw32 sim64; do
  link $p smoke-$p "$D/smoke.S"
  [ "$($T-readelf -h "$B/smoke-$p.elf" | awk '/Entry point/ {print $4}')" = 0x0 ] \
    || fail "$p: entry point is not the reset vector 0x0000"
  out1=$(scripts/run.sh --cycles "$B/smoke-$p.elf" 2>&1)
  out2=$(scripts/run.sh --cycles "$B/smoke-$p.elf" 2>&1)
  [ "$out1" = "$out2" ] || fail "$p: not deterministic"
  grep -qx 'sim1802 board ok, ticks=5' <<< "$out1" || fail "$p: $out1"
  echo "ok: $p smoke ($(grep '@ cycles' <<< "$out1"))"

  # Writing into ROM must stop the simulator with status 97.
  link $p smoke-$p-wrom -DSMOKE_WRITE_ROM "$D/smoke.S"
  set +e; out=$(scripts/run.sh "$B/smoke-$p-wrom.elf" 2>&1); rc=$?; set -e
  [ $rc -eq 97 ] && grep -q 'write to write-protected address 0x0000' <<< "$out" \
    || fail "$p: ROM write not trapped (status $rc)"
  echo "ok: $p ROM write -> 97"
done

# HW32/32 layout: .data runs in RAM, its initial image lives in ROM.
nm=$($T-nm "$B/smoke-hw32.elf")
[ "$(awk '$3=="_sdata"{print $1}' <<< "$nm")" = 00008000 ] || fail "hw32: .data not at 0x8000"
[ "$(awk '$3=="__sim1802_rom_end"{print $1}' <<< "$nm")" = 00008000 ] || fail "hw32: ROM end"

# Linker scripts refuse images that do not fit.
printf '\t.section .rodata\n\t.space 33000\n' > "$B/big.S"
if link hw32 big-hw32 "$D/smoke.S" "$B/big.S" 2> "$B/big-hw32.log"; then
  fail "hw32: 33 KB of rodata linked"
fi
grep -q 'HW32/32: ROM overflow' "$B/big-hw32.log" || fail "hw32: wrong overflow message"
printf '\t.data\n\t.space 65000\n' > "$B/huge.S"
if link sim64 big-sim64 "$D/smoke.S" "$B/huge.S" 2> "$B/big-sim64.log"; then
  fail "sim64: image above 0xFF00 linked"
fi
grep -q 'loadable image must end below 0xFF00' "$B/big-sim64.log" || fail "sim64: wrong error: $(cat "$B/big-sim64.log")"
echo "ok: linker scripts reject oversized images"

for f in docs/cdp1802/board-sim1802.md docs/adr/0005-sim1802-board.md; do
  [ -s "$f" ] || fail "missing $f"
done
echo "PASS: step 03"
