#!/usr/bin/env bash
# scripts/test-step-06b.sh -- Step 06b exit check: code banking (ADR 0013,
# amendment A5).
#   1. scripts/test-banking.sh: trampoline, placement tool and simulator
#      bank window on a freestanding three-bank program, with an interrupt
#      routine that calls banked code (stress test).
#   2. sim1802:hwboot (the boot configuration on the banked HWB profile)
#      builds without diagnostics; code really is in two or more banks; the
#      ROM image is 32 KiB + n x 16 KiB; it boots from the raw ROM image to
#      NuttX's idle loop with three RAM seeds (random bank latch at reset).
#   3. The SIM64 configurations still pass (scripts/test-step-06.sh, which
#      also runs nxstyle and checkpatch over all port commits).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

scripts/test-banking.sh > build/test-banking.log 2>&1 \
  || { tail -20 build/test-banking.log; fail "test-banking"; }
grep -E "^seed=|^ok:" build/test-banking.log
echo "ok: banking test"

scripts/build.sh sim1802:hwboot step06b-hwboot > /dev/null || fail "build hwboot"
b=build/step06b-hwboot
[ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "diagnostics"; }
grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "sp-safety"; }
used=$(grep -cE '^bank [0-9]+: [1-9]' $b/nuttx.banks)
[ "$used" -ge 2 ] || { cat $b/nuttx.banks; fail "code in $used banks"; }
size=$(stat -c %s $b/nuttx.bin)
[ $(( (size - 32768) % 16384 )) = 0 ] && [ "$size" -gt 32768 ] \
  || fail "nuttx.bin is $size bytes, not 32 KiB + n x 16 KiB"
echo "ok: sim1802:hwboot builds ($used banks used, nuttx.bin $size bytes)"

for seed in 1 2 3; do
  out=$(RUN_TIMEOUT=300 scripts/run.sh --ram-seed $seed --max-cycles 2000000 \
        $b/nuttx.elf 2>&1); rc=$?
  [ $rc = 96 ] || { echo "$out"; fail "seed $seed: exit $rc, expected 96"; }
  for l in "Entry" "No init thread" "CPU0: Beginning Idle Loop"; do
    grep -q "$l" <<< "$out" || { echo "$out"; fail "seed $seed: missing '$l'"; }
  done
  grep -qi "assert\|panic" <<< "$out" && { echo "$out"; fail "seed $seed: assertion"; }
done
echo "ok: banked image boots to the idle loop from ROM (3 RAM seeds)"

scripts/test-step-06.sh | tail -1 | grep -q "PASS: step 06" || fail "step 06 regression"
echo "ok: SIM64 configurations, nxstyle, checkpatch (test-step-06.sh)"
[ -s docs/porting-guide/15-size-optimisation.md ] || fail "missing guide chapter 15"
echo "PASS: step 06b"
