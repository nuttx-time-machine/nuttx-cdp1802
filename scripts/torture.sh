#!/usr/bin/env bash
# scripts/torture.sh <name> <cflags...> — run GCC's gcc.c-torture/execute
# tests (from the pinned GCC source) with the installed cdp1802 compiler and
# the given flags, in sim1802, in parallel.  Result per test, in
# build/torture/<name>/results.txt:
#   PASS     exit status 0
#   FAIL     other exit status (abort() etc.): wrong code, or a real limit
#   NYI      exit 98: the test needs a libc function mikpe's libc only stubs
#   TIMEOUT  more than RUN_TIMEOUT seconds
#   TRAP     exit 97 (simulator trap)
#   NOBUILD  does not compile or link (e.g. too large, unsupported feature)
# Used to compare optimisation levels (toolchain issue 0002).  Tests that
# need dg-options/special flags are run with plain flags; they only matter
# when their outcome differs between flag sets.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

name=$1; shift
cflags="$*"
src=toolchain/work/gcc/gcc/testsuite/gcc.c-torture/execute
out=build/torture/$name
mkdir -p "$out"
export out cflags CDP1802_TARGET

one() {
  t=$1
  b=$(basename "$t" .c)
  if ! "$CDP1802_TARGET-gcc" $cflags -w -o "$out/$b.elf" "$t" -lm > "$out/$b.log" 2>&1; then
    echo "NOBUILD $b"; return
  fi
  set +e
  RUN_TIMEOUT=${RUN_TIMEOUT:-20} scripts/run.sh "$out/$b.elf" > "$out/$b.out" 2>&1
  rc=$?
  set -e
  case $rc in
    0) echo "PASS $b" ;;
    98) echo "NYI $b" ;;
    124) echo "TIMEOUT $b" ;;
    97) echo "TRAP $b" ;;
    *) echo "FAIL $b" ;;
  esac
  rm -f "$out/$b.elf" "$out/$b.elf.bin"
}
export -f one

ls "$src"/*.c | xargs -P "$(nproc)" -I{} bash -c 'one {}' | sort -k2 > "$out/results.txt"
awk '{print $1}' "$out/results.txt" | sort | uniq -c | sort -rn
