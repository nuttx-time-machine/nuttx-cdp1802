#!/usr/bin/env bash
# scripts/test-step-03.sh — Step 03 exit check: the sim1802 virtual board
# (docs/cdp1802/board-sim1802.md, ADR 0005) behaves as documented, in both
# memory profiles, booting the raw ROM binary exactly like the real machine
# (sim1802 fork --rom mode, via scripts/run.sh).
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

  # Boots from the raw ROM binary; two runs are identical.
  out1=$(scripts/run.sh --cycles "$B/smoke-$p.elf" 2>&1)
  out2=$(scripts/run.sh --cycles "$B/smoke-$p.elf" 2>&1)
  [ "$out1" = "$out2" ] || fail "$p: not deterministic"
  grep -qx 'sim1802 board ok, ticks=5' <<< "$out1" || fail "$p: $out1"
  [ "$(head -c 2 "$B/smoke-$p.elf.bin" | od -An -tx1 | tr -d ' ')" = 7100 ] \
    || fail "$p: ROM image does not start with the reset code (DIS; 0x00)"
  echo "ok: $p boots from its $(stat -c %s "$B/smoke-$p.elf.bin")-byte ROM image ($(grep '@ cycles' <<< "$out1"))"

  # The ELF loader path gives the same result (the ROM image is the same program).
  [ "$(RUN_MODE=elf scripts/run.sh --cycles "$B/smoke-$p.elf" 2>&1)" = "$out1" ] \
    || fail "$p: ELF-loader run differs from ROM run"

  # Power-on RAM is undefined: without the .data copy the result is garbage,
  # and it depends on the power-on state (seed).
  link $p nocopy-$p -DSMOKE_NO_DATA_COPY "$D/smoke.S"
  a=$(scripts/run.sh "$B/nocopy-$p.elf" | od -An -tx1)
  b=$(scripts/run.sh --ram-seed 7 "$B/nocopy-$p.elf" | od -An -tx1)
  ok=$(printf 'sim1802 board ok, ticks=5\n' | od -An -tx1)
  [ "$a" != "$ok" ] && [ "$b" != "$ok" ] && [ "$a" != "$b" ] \
    || fail "$p: RAM looks initialised at power-on"
  echo "ok: $p RAM is undefined at power-on (missing .data copy is caught)"

  # A write into ROM is ignored like on hardware, or trapped on request.
  link $p wrom-$p -DSMOKE_WRITE_ROM "$D/smoke.S"
  set +e; out=$(scripts/run.sh "$B/wrom-$p.elf" 2>&1); rc=$?; set -e
  [ $rc -eq 0 ] && grep -qx 'sim1802 board ok, ticks=5' <<< "$out" \
    || fail "$p: ROM write not ignored (status $rc)"
  set +e; out=$(scripts/run.sh --rom-writes trap "$B/wrom-$p.elf" 2>&1); rc=$?; set -e
  [ $rc -eq 97 ] && grep -q 'write to write-protected address 0x0000' <<< "$out" \
    || fail "$p: ROM write not trapped with --rom-writes trap (status $rc)"
  echo "ok: $p ROM write ignored (default) / trapped (--rom-writes trap)"
done

# HW32/32 layout: .data runs in RAM at 0x8000, its initial image lives in ROM.
nm=$($T-nm "$B/smoke-hw32.elf")
[ "$(awk '$3=="_sdata"{print $1}' <<< "$nm")" = 00008000 ] || fail "hw32: .data not at 0x8000"
[ "$(awk '$3=="__sim1802_rom_end"{print $1}' <<< "$nm")" = 00008000 ] || fail "hw32: ROM end"

# Linker scripts refuse images that do not fit.
printf '\t.section .rodata\n\t.space 33000\n' > "$B/big.S"
if link hw32 big-hw32 "$D/smoke.S" "$B/big.S" 2> "$B/big-hw32.log"; then
  fail "hw32: 33 KB of rodata linked"
fi
grep -q 'HW32/32: ROM overflow' "$B/big-hw32.log" || fail "hw32: wrong error: $(cat "$B/big-hw32.log")"
printf '\t.section .rodata\n\t.space 65500\n' > "$B/huge.S"
if link sim64 big-sim64 "$D/smoke.S" "$B/huge.S" 2> "$B/big-sim64.log"; then
  fail "sim64: image larger than 64 KiB linked"
fi
grep -q "will not fit in region \`mem'" "$B/big-sim64.log" || fail "sim64: wrong error: $(cat "$B/big-sim64.log")"
echo "ok: linker scripts reject oversized images"

for f in docs/cdp1802/board-sim1802.md docs/adr/0005-sim1802-board.md; do
  [ -s "$f" ] || fail "missing $f"
done
echo "PASS: step 03"
