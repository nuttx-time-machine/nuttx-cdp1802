#!/usr/bin/env bash
# scripts/measure-flat-nsh.sh -- the smallest NSH, and whether it fits a
# flat ROM (journal step-10, "Flat NSH").
#   sim1802:nshflat is NSH with only help/poweroff/quit, no signals,
#   pthreads, message queues, environment, mount points or procfs, the
#   minimal console driver (CONFIG_SIM1802_CONSOLE) instead of the serial
#   driver, NSH started by the board (CONFIG_SIM1802_START_NSH, no
#   task_spawn()), and inline comparisons (smaller code).  The defconfig
#   uses the banked HWB profile, where it runs: help, an unknown command
#   and poweroff are checked.  Then the same configuration is linked flat
#   for HW48/16 (48 KiB ROM) and the size and overflow are reported; the
#   flat link is expected to fail (not an error of this script).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

scripts/build.sh sim1802:nshflat nshflat-hwb > /dev/null || fail "build (HWB)"
b=build/nshflat-hwb
out=$(printf 'help\nnosuchcmd\npoweroff\n' | RUN_TIMEOUT=600 scripts/run.sh \
      --rom-writes trap --max-cycles 100000000 $b/nuttx.elf 2>&1 | tr -d '\r')
rc=$?
[ $rc = 0 ] && grep -q "help usage:" <<< "$out" && grep -q "poweroff" <<< "$out" \
  || { echo "$out"; fail "sim1802:nshflat on HWB"; }
echo "ok: sim1802:nshflat runs on HWB ($(grep '^banked' $b/size.txt | cut -d'(' -f1))"

printf 'CONFIG_BOARD_SIM1802_PROFILE_HW48=y\n# CONFIG_BOARD_SIM1802_PROFILE_HWB is not set\n' \
  > build/frag-hw48-only
BUILD_FRAGMENT=$PWD/build/frag-hw48-only scripts/build.sh sim1802:nshflat nshflat > /dev/null
b=build/nshflat
over=$(grep -ao "overflowed by [0-9]* bytes" $b/build.log | head -1)
echo "flat HW48/16: $(grep '^ROM' $b/size.txt | cut -d, -f1); ${over:-fits}"
