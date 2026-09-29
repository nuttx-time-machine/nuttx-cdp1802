#!/usr/bin/env bash
# scripts/test-step-07.sh -- Step 07 exit check: interrupts and the system
# timer.  sim1802:tick (HWB banked profile) replaces the idle loop with a
# watchdog that re-arms itself every 50 ticks: the tick counter must
# advance and every period must be exactly 51 ticks (wd_start() adds one
# tick) = 51 x 10 000 machine cycles (50 Hz tick at the nominal 4 MHz) in
# simulated time.  Run for both interrupt-state implementations (LSIE and
# the software IE flag, Kconfig choice) and for the flat SIM64 profile.
# Also measures the interrupt entry + exit cost from an instruction trace.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

printf '# CONFIG_BOARD_SIM1802_PROFILE_HWB is not set\nCONFIG_BOARD_SIM1802_PROFILE_SIM64=y\nCONFIG_RAM_START=0x0\nCONFIG_RAM_SIZE=65536\n' > build/frag-sim64
printf '# CONFIG_COSMAC_IRQSTATE_LSIE is not set\nCONFIG_COSMAC_IRQSTATE_SWFLAG=y\n' > build/frag-swflag
cat build/frag-sim64 build/frag-swflag > build/frag-sim64-swflag

for v in hwb-lsie hwb-swflag sim64-lsie sim64-swflag; do
  case $v in
    hwb-lsie) frag= ;;
    hwb-swflag) frag=$PWD/build/frag-swflag ;;
    sim64-lsie) frag=$PWD/build/frag-sim64 ;;
    sim64-swflag) frag=$PWD/build/frag-sim64-swflag ;;
  esac
  b=build/step07-$v
  BUILD_FRAGMENT=$frag scripts/build.sh sim1802:tick step07-$v > /dev/null || fail "$v: build"
  [ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "$v: diagnostics"; }
  grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "$v: sp-safety"; }
  out=$(RUN_TIMEOUT=300 scripts/run.sh --max-cycles 60000000 $b/nuttx.elf 2>&1); rc=$?
  [ $rc = 0 ] || { echo "$out"; fail "$v: exit $rc"; }
  for n in 2 3 4 5 6; do
    grep -q "wdog $n: +51 ticks, +510000 cycles" <<< "$out" \
      || { echo "$out"; fail "$v: watchdog period $n"; }
  done
  echo "ok: $v: $(grep -c 'wdog' <<< "$out") watchdog callbacks, 51 ticks = 510000 cycles apart;" \
       "$(grep 'timer interrupt' <<< "$out" | sed 's/ticktest: //');" \
       "$(grep 'idle stack' <<< "$out" | sed 's/ticktest: //')"
done

# Interrupt entry + exit (the assembly in cosmac_irqentry.S) from a trace
b=build/step07-hwb-lsie
"$CDP1802_TARGET-objcopy" -O binary --gap-fill 0xff $b/nuttx.elf $b/trace.bin
timeout 300 "$CDP1802_TARGET-sim" -t --max-cycles 1500000 --rom $b/trace.bin \
  --rom-size 32768 --banks 4 --symbols $b/nuttx.elf > $b/trace.txt 2>&1
python3 scripts/trace-profile.py $b/trace.txt --nth 3 --top 40 > $b/tick-profile.txt
entry=$(awk '$1 == "cosmac_irq_entry" { print $2 }' $b/tick-profile.txt)
exit_=$(awk '$1 == "cosmac_irq_exit" { print $2 }' $b/tick-profile.txt)
total=$(awk '/^TOTAL/ { print $(NF-1) }' $b/tick-profile.txt)
[ -n "$entry" ] && [ -n "$exit_" ] || { cat $b/tick-profile.txt; fail "trace profile"; }
echo "ok: interrupt entry $entry + exit $exit_ = $((entry + exit_)) machine cycles (+1 response cycle); whole tick $total (tick-profile.txt)"

base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h'); do
  o=$(build/nxstyle "nuttx/$f"); [ -z "$o" ] || { echo "$o"; fail "nxstyle $f"; }
done
echo "ok: nxstyle, checkpatch"
[ -s docs/porting-guide/09-interrupts.md ] && [ -s docs/porting-guide/10-timer.md ] \
  || fail "missing guide chapters 09/10"
echo "PASS: step 07"
