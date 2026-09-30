#!/usr/bin/env bash
# scripts/test-step-09.sh [--clock HZ] -- Step 09 exit check: ostest.
#   sim1802:ostest (HWB banked profile, serial console driver, stdin at
#   EOF) runs apps/testing/ostest.  ostest waits for its test task and
#   powers off with the result (CONFIG_TESTING_OSTEST_POWEROFF), so the
#   simulator's exit status is ostest's status; an assertion stops it with
#   status 3 (CONFIG_BOARD_RESET_ON_ASSERT).  PASS needs status 0,
#   "ostest_main: Exiting with status 0" and no "ERROR" line.
#   The configuration runs at a virtual 16 MHz (ADR 0020); --clock runs it
#   at another nominal clock, e.g. 4000000, to see which timing-dependent
#   tests fail at a real COSMAC speed (that run does not have to pass).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

clock=
[ "${1:-}" = --clock ] && clock=$2
name=step09-ostest${clock:+-$clock}
if [ -n "$clock" ]; then
  echo "CONFIG_BOARD_SIM1802_CLOCK_HZ=$clock" > build/frag-clock
  export BUILD_FRAGMENT=$PWD/build/frag-clock
fi
scripts/build.sh sim1802:ostest $name > /dev/null || fail "build"
b=build/$name
[ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "diagnostics"; }
grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "sp-safety"; }
echo "ok: sim1802:ostest builds ($(grep '^banked' $b/size.txt))"

start=$(date +%s)
RUN_TIMEOUT=7200 scripts/run.sh --cycles --max-cycles 100000000000 $b/nuttx.elf \
  < /dev/null > $b/output.txt 2>&1
rc=$?
secs=$(( $(date +%s) - start ))
cycles=$(awk '/^@ cycles/ { print $3 }' $b/output.txt)
tests=$(grep -c "^user_main: .* test" $b/output.txt)
errors=$(grep -c "ERROR" $b/output.txt)
echo "ostest: exit $rc, $tests tests started, $errors ERROR lines, $cycles machine cycles, ${secs}s host time"
if [ -n "$clock" ]; then
  grep -B2 "ERROR" $b/output.txt | head -20
  echo "(informational run at $clock Hz)"
  exit 0
fi
[ $rc = 0 ] && grep -q "ostest_main: Exiting with status 0" $b/output.txt && [ "$errors" = 0 ] \
  || { tail -30 $b/output.txt; fail "ostest"; }
echo "ok: ostest passed"

base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -r -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h'); do
  o=$(build/nxstyle "nuttx/$f"); [ -z "$o" ] || { echo "$o"; fail "nxstyle $f"; }
done
echo "ok: nxstyle, checkpatch"
[ -s docs/porting-guide/13-serial.md ] && [ -s docs/porting-guide/14-validation.md ] \
  || fail "missing guide chapters 13/14"
echo "PASS: step 09"
