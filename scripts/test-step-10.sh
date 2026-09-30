#!/usr/bin/env bash
# scripts/test-step-10.sh -- Step 10 exit check: NSH with help, ps, free and
#   uptime.  sim1802:nsh (HWB banked profile, serial console driver, procfs
#   mounted by board_late_initialize()) reads a command script from the
#   simulated console input; "poweroff" ends the run with status 0.
#   PASS needs status 0, the four commands' expected output, "command not
#   found" for an unknown command, and no ROM write (--rom-writes trap: a
#   stack that runs out of RAM writes to ROM first).
#   Then each command runs alone, to record its cost in machine cycles
#   (cycles to "poweroff" minus the cycles of a run with "poweroff" only).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

name=step10-nsh
scripts/build.sh sim1802:nsh $name > /dev/null || fail "build"
b=build/$name
[ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "diagnostics"; }
grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "sp-safety"; }
echo "ok: sim1802:nsh builds ($(grep '^banked' $b/size.txt))"

run() {  # run <output> <commands...>: one command per input line
  local out=$1; shift
  printf '%s\n' "$@" | RUN_TIMEOUT=900 scripts/run.sh --cycles --rom-writes trap \
    --max-cycles 2000000000 $b/nuttx.elf > "$out.raw" 2>&1
  local rc=$?
  tr -d '\r' < "$out.raw" > "$out"  # the console sends CR LF
  rm -f "$out.raw"
  return $rc
}

run $b/output.txt help ps free uptime nosuchcmd poweroff
rc=$?
cat $b/output.txt
[ $rc = 0 ] || fail "exit status $rc"
expect() { grep -q -- "$1" $b/output.txt || fail "missing: $1"; }
expect "NuttShell (NSH)"
expect "help usage:"
for c in help ps free uptime; do
  sed -n '/help usage:/,/^nsh>/p' $b/output.txt | grep -qw "$c" || fail "help lists no $c"
done
expect "PID  PPID PRI POLICY"
expect " Idle_Task$"
expect " nsh_main$"
expect "total *used *free"
expect "Umem$"
expect " up .*load average:"
expect "nsh: nosuchcmd: command not found"
grep -q "^!" $b/output.txt && fail "simulator trap"
echo "ok: help, ps, free, uptime, unknown command, poweroff"

run $b/cost-base.txt poweroff || fail "poweroff-only run"
base=$(awk '/^@ cycles/ { print $3 }' $b/cost-base.txt)
echo "boot to prompt + poweroff: $base machine cycles"
for c in help ps free uptime; do
  run $b/cost-$c.txt "$c" poweroff || fail "$c run"
  n=$(awk '/^@ cycles/ { print $3 }' $b/cost-$c.txt)
  echo "$c: $((n - base)) machine cycles"
done

base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -r -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h') include/fcntl.h; do
  o=$(build/nxstyle "nuttx/$f"); [ -z "$o" ] || { echo "$o"; fail "nxstyle $f"; }
done
echo "ok: nxstyle, checkpatch"
echo "PASS: step 10"
