#!/usr/bin/env bash
# scripts/test-step-08.sh -- Step 08 exit check: context switching.
#   sim1802:threads (HWB banked profile, the init task is the test): two
#   SCHED_RR tasks take turns under preemption, a semaphore ping-pong runs
#   in order, usleep() sleeps the right number of ticks, signals reach a
#   blocked task and (from an interrupt) a running one, tasks exit
#   (scripts/check-threads.py verifies the interleaved output).  Both
#   interrupt-state variants.  Also measures a thread-level context switch
#   from an instruction trace (hypothesis H5).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

printf '# CONFIG_COSMAC_IRQSTATE_LSIE is not set\nCONFIG_COSMAC_IRQSTATE_SWFLAG=y\n' > build/frag-swflag
for v in lsie swflag; do
  [ $v = lsie ] && frag= || frag=$PWD/build/frag-swflag
  b=build/step08-$v
  BUILD_FRAGMENT=$frag scripts/build.sh sim1802:threads step08-$v > /dev/null || fail "$v: build"
  [ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "$v: diagnostics"; }
  grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "$v: sp-safety"; }
  RUN_TIMEOUT=600 scripts/run.sh --max-cycles 400000000 $b/nuttx.elf > $b/output.txt 2>&1
  rc=$?
  [ $rc = 0 ] || { cat $b/output.txt; fail "$v: exit $rc"; }
  r=$(python3 scripts/check-threads.py $b/output.txt) || { cat $b/output.txt; echo "$r"; fail "$v: output"; }
  echo "ok: $v: $r; $(grep 'sched_yield' $b/output.txt | sed 's/threads: //')"
done
grep "stack bytes" build/step08-lsie/output.txt | sed 's/^threads: /    /'

# One thread-level context switch (save + restore) from a trace
b=build/step08-lsie
"$CDP1802_TARGET-objcopy" -O binary --gap-fill 0xff $b/nuttx.elf $b/trace.bin
timeout 900 "$CDP1802_TARGET-sim" -t --max-cycles 12000000 --rom $b/trace.bin \
  --rom-size 32768 --banks 8 --symbols $b/nuttx.elf 2>&1 > /dev/null \
  | python3 scripts/trace-profile.py - --start cosmac_switchcontext --nth 3 \
      --elf $b/nuttx.elf > $b/switch-profile.txt
t=$(awk '/^TOTAL/ { print $(NF-1) }' $b/switch-profile.txt)
[ -n "$t" ] || { cat $b/switch-profile.txt; fail "switch profile"; }
echo "ok: thread-level context switch $t machine cycles = $((t * 8)) clocks (H5: ~2000 clocks)"

base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h'); do
  o=$(build/nxstyle "nuttx/$f"); [ -z "$o" ] || { echo "$o"; fail "nxstyle $f"; }
done
echo "ok: nxstyle, checkpatch"
[ -s docs/cdp1802/context.md ] || fail "missing docs/cdp1802/context.md"
[ -s docs/porting-guide/11-context-switch.md ] && [ -s docs/porting-guide/12-signals-exit.md ] \
  || fail "missing guide chapters 11/12"
echo "PASS: step 08"
