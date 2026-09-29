#!/usr/bin/env bash
# scripts/test-banking.sh -- Step 06b: code banking without NuttX.
#   The far-call trampoline (nuttx arch/cosmac/src/common/cosmac_farcall.S),
#   the placement/stub tool (nuttx tools/cosmac/cosmac_bank.py) and the
#   simulator's bank window, on a freestanding program with three banks
#   (toolchain/tests/banking): calls across banks with stack arguments,
#   function pointers, a tail call, recursion through all banks, and an
#   interrupt routine that calls banked code, with the cycle timer
#   interrupting every 1 499-3 001 machine cycles (the interrupt routine
#   itself takes about 1 170 cycles: two far calls), so interrupts land at
#   every point of the trampolines.  Booted from the raw ROM
#   image (--rom --banks 3), several RAM seeds and interrupt periods.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

T=cdp1802-elf
S=toolchain/tests/banking
B=build/banking
rm -rf "$B"; mkdir -p "$B"
CFLAGS="-Os -march=1802 -ffunction-sections -fdata-sections -fno-split-wide-types -Wall -Werror -I$S"

build() {  # build <name> <extra cflags>
  local o="$B/$1"; mkdir -p "$o"
  for f in bank_a bank_b bank_c main; do
    $T-gcc $CFLAGS $2 -c -o "$o/$f.o" "$S/$f.c"
  done
  for f in head isr_bank; do
    $T-gcc -c -o "$o/$f.o" "$S/$f.S"
  done
  $T-gcc $CFLAGS -c -o "$o/ncrt.o" nuttx/arch/cosmac/src/common/cosmac_ncrt.S
  $T-gcc $CFLAGS -c -o "$o/farcall.o" nuttx/arch/cosmac/src/common/cosmac_farcall.S
  $T-gcc $CFLAGS -c -o "$o/sim_io.o" toolchain/tests/sim-audit/sim_io.S
  rm -f "$o/libbanktest.a"
  $T-ar rcs "$o/libbanktest.a" "$o/bank_a.o" "$o/bank_b.o" "$o/bank_c.o"
  local objs=("$o/head.o" "$o/main.o" "$o/isr_bank.o" "$o/ncrt.o" "$o/farcall.o" "$o/sim_io.o")
  local libgcc; libgcc=$($T-gcc -march=1802 -print-libgcc-file-name)
  # 1. measuring link, 2. placement and stubs, 3. banked link
  $T-ld --gc-sections -T $S/flat.ld -Map "$o/flat.map" -o "$o/flat.elf" \
    "${objs[@]}" "$o/libbanktest.a" "$libgcc"
  python3 nuttx/tools/cosmac/cosmac_bank.py --rules $S/rules.txt --banks 3 \
    --map "$o/flat.map" --outdir "$o/banked" --stubs "$o/stubs.S" \
    --ldscript "$o/banked/banks.ld" --report "$o/report.txt" \
    --objcopy $T-objcopy --ar $T-ar "$o/libbanktest.a"
  $T-gcc -c -o "$o/stubs.o" "$o/stubs.S"
  $T-ld --gc-sections -L "$o/banked" -T $S/hwb.ld -Map "$o/banked.map" \
    -o "$o/banked.elf" "${objs[@]}" "$o/stubs.o" "$o/banked/libbanktest.a" "$libgcc"
  $T-objcopy -O binary --gap-fill 0xff "$o/banked.elf" "$o/banked.bin"
}

build main "${MAIN_CFLAGS:-}"
o=$B/main
cat "$o/report.txt"
size=$(stat -c %s "$o/banked.bin")
[ "$size" = $((32768 + 3 * 16384)) ] || fail "image is $size bytes, expected 32 KiB + 3 x 16 KiB"
python3 scripts/check-sp-safety.py --allow __start "$o/banked.elf" | tail -1

# Every function of a bank lives in the window; a_apply -> a_local is a
# direct call inside bank 0 (no stub), a_chain -> b_chain goes through the
# stub in fixed ROM.
nm=$($T-nm "$o/banked.elf")
for f in a_chain b_chain c_chain a_local isr_hook; do
  a=$(awk -v s="__bank_$f" '$3 == s { print $1 }' <<< "$nm")
  [ -n "$a" ] && [ $((16#$a)) -ge $((0x8000)) ] && [ $((16#$a)) -lt $((0xC000)) ] \
    || fail "__bank_$f not in the bank window ($a)"
  s=$(awk -v s="$f" '$3 == s { print $1 }' <<< "$nm")
  [ -z "$s" ] || [ $((16#$s)) -lt $((0x8000)) ] || fail "stub $f not in fixed ROM"
done
# Call targets (the word after "sep 4") inside __bank_a_apply
targets=$($T-objdump -d "$o/banked.elf" | awk '/<__bank_a_apply>:/,/^$/' \
  | awk '$2 == "d4" { n = 2; w = ""; next } n > 0 { w = w $2; if (--n == 0) print w }')
local_addr=$(awk '$3 == "__bank_a_local" { print $1 }' <<< "$nm" | sed 's/^0000//')
stub_addr=$(awk '$3 == "a_local" { print $1 }' <<< "$nm")
grep -qx "$local_addr" <<< "$targets" || fail "a_apply does not call __bank_a_local directly ($targets)"
[ -z "$stub_addr" ] || fail "a_local has a stub that is kept: nobody outside bank 0 calls it"
echo "ok: layout (banks in the window, stubs in fixed ROM, same-bank call direct)"

build noirq "-DNO_IRQ" > /dev/null
out=$(RUN_TIMEOUT=600 scripts/run.sh --cycles "$B/noirq/banked.elf" 2>&1) \
  || { echo "$out"; fail "without interrupts"; }
echo "no interrupts: $out" | tr '\n' ' '; echo
grep -q ' errors=0$' <<< "$(head -1 <<< "$out")" || fail "without interrupts"

for seed in 1 7 42; do
  for period in 1499 1999 3001; do
    [ $period = 1999 ] || [ $seed = 1 ] || continue
    build p$period "-DPERIOD=${period}UL" > /dev/null
    out=$(RUN_TIMEOUT=600 scripts/run.sh --ram-seed $seed --max-cycles 400000000 \
          "$B/p$period/banked.elf" 2>&1) || { echo "$out"; fail "seed $seed period $period"; }
    echo "seed=$seed period=$period: $out"
    grep -q ' errors=0$' <<< "$out" || fail "seed $seed period $period"
    grep -q ' irqs=0 ' <<< "$out" && fail "no interrupts"
  done
done

# Cost of a far call: 1000 far calls vs 1000 near calls, same loop
for k in 1 2; do
  build bench$k "-DBENCH=$k -DNO_IRQ" > /dev/null
  c[$k]=$(RUN_TIMEOUT=600 scripts/run.sh --cycles "$B/bench$k/banked.elf" 2>&1 \
          | awk '/^@ cycles/ { print $3 }') || fail "bench $k"
done
echo "ok: far call + return costs $(( (c[1] - c[2]) / 1000 )) machine cycles more than a near one (${c[1]} vs ${c[2]} cycles for 1000 calls)"

build overflow "-DDEPTH=20 -DROUNDS=21" > /dev/null
out=$(RUN_TIMEOUT=600 scripts/run.sh --max-cycles 400000000 "$B/overflow/banked.elf" 2>&1) && rc=0 || rc=$?
[ $rc = 3 ] && grep -q "BRS overflow" <<< "$out" || { echo "$out"; fail "overflow: exit $rc"; }
echo "ok: bank return stack overflow detected (depth 20 > 16)"
echo "PASS: banking"
