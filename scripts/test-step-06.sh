#!/usr/bin/env bash
# scripts/test-step-06.sh — Step 06 exit check: reset, start-up and boot.
#   sim1802:boot is built and run from its raw ROM image (--rom mode:
#   0xFF-filled ROM, random RAM and registers, like a real machine) and must
#   print NuttX's boot messages up to the idle loop, then keep running until
#   the cycle limit (exit 96).  sim1802:minimal still builds cleanly; nxstyle
#   and checkpatch pass on the port.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

scripts/build.sh sim1802:boot step06-boot > /dev/null || fail "build boot"
b=build/step06-boot
[ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "diagnostics"; }
grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "sp-safety"; }
echo "ok: sim1802:boot builds ($(grep '^ROM' $b/size.txt))"

for seed in 1 2 3; do
  out=$(RUN_TIMEOUT=300 scripts/run.sh --ram-seed $seed --max-cycles 2000000 \
        $b/nuttx.elf 2>&1); rc=$?
  [ $rc = 96 ] || { echo "$out"; fail "seed $seed: exit $rc, expected 96 (cycle limit)"; }
  for l in "Entry" "No init thread" "CPU0: Beginning Idle Loop"; do
    grep -q "$l" <<< "$out" || { echo "$out"; fail "seed $seed: missing '$l'"; }
  done
  grep -qi "assert\|panic" <<< "$out" && { echo "$out"; fail "seed $seed: assertion"; }
done
echo "ok: boots to the idle loop from ROM (3 RAM seeds)"

scripts/build.sh sim1802:minimal step06-minimal > /dev/null || fail "build minimal"
[ -s build/step06-minimal/diagnostics.txt ] && fail "minimal diagnostics"
echo "ok: sim1802:minimal builds ($(grep '^ROM' build/step06-minimal/size.txt))"

gcc -o build/nxstyle nuttx/tools/nxstyle.c 2> /dev/null || fail "cannot build nxstyle"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h'); do
  out=$(build/nxstyle "nuttx/$f") ; [ -z "$out" ] || { echo "$out"; fail "nxstyle $f"; }
done
echo "ok: nxstyle"
base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -r -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
echo "ok: checkpatch $base..HEAD"
[ -s docs/porting-guide/07-startup.md ] || fail "missing guide chapter 07"
echo "PASS: step 06"
