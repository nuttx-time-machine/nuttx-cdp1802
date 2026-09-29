#!/usr/bin/env bash
# scripts/test-step-01.sh — Step 01 exit check.
#
# 1. The pinned toolchain is installed (toolchain/build-toolchain.sh).
# 2. hello, a soft-float test and the ABI probes compile, link and run in
#    sim1802 with the expected output and exit status.
# 3. Key ABI facts documented in docs/cdp1802/abi.md still hold for the
#    installed compiler (argument registers, return register, NCRT call).
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
B=build/step01
mkdir -p "$B"
fail() { echo "FAIL: $*"; exit 1; }

command -v $T-gcc > /dev/null || fail "$T-gcc not on PATH; run toolchain/build-toolchain.sh"
command -v $T-sim > /dev/null || fail "$T-sim not on PATH; run toolchain/build-toolchain.sh"
$T-gcc --version | head -1
[ "$($T-gcc -print-multi-directory)" = 1802 ] || fail "default multilib is not 1802"
# Amendment A3: the contract's cdp1802-elf-* names must exist too.
for t in gcc as ld size nm objdump objcopy readelf sim; do
  command -v cdp1802-elf-$t > /dev/null || fail "cdp1802-elf-$t missing (amendment A3)"
done

# expect <name> <expected-output-file-content>
run_expect() {
  local name=$1 expected=$2 out
  $T-gcc -Os -Wall -Werror -o "$B/$name.elf" "toolchain/tests/$name.c"
  out=$(scripts/run.sh "$B/$name.elf") || fail "$name exited with status $?"
  if [ "$out" != "$expected" ]; then
    printf 'expected:\n%s\ngot:\n%s\n' "$expected" "$out"
    fail "$name output mismatch"
  fi
  echo "ok: $name"
}

run_expect hello "hello, cdp1802"
run_expect softfloat "f*1000   = 3375
d*10000  = 109955
e*2      = 200001
f<d      = 1
softfloat: PASS"
run_expect abi "sizeof: short=2 int=2 long=4 llong=8 ptr=2 float=4 double=8
abi: PASS"

# Exit status propagation (used by every later step test).
echo 'int main(void){return 3;}' > "$B/ret3.c"
$T-gcc -Os -o "$B/ret3.elf" "$B/ret3.c"
set +e; scripts/run.sh "$B/ret3.elf"; rc=$?; set -e
[ $rc -eq 3 ] || fail "exit status not propagated (got $rc)"
echo "ok: exit status"

# ABI facts from the generated assembly.
$T-gcc -Os -S -fno-inline -o "$B/abi.s" toolchain/tests/abi.c
fn() { awk "/^$1:/,/\\.size\\t$1,/" "$B/abi.s"; }
fn add16 | tr -d '\t' | tr '\n' ' ' | grep -q 'glo 8 str 2 glo 7 add plo 7' \
  || fail "add16: args no longer in R7/R8 or result not in R7"
fn add16 | grep -q 'sep 5' || fail "add16: return is not 'sep 5' (NCRT)"
fn keep_live | grep -A1 'sep 4' | grep -q '.hword opaque' \
  || fail "keep_live: direct call is not 'sep 4; .hword callee'"
fn call_ptr | grep -q '.hword __call_reg' || fail "call_ptr: indirect call changed"
[ -z "$(fn mkpair | grep -v -e '^mkpair:' -e 'sep 5' -e '\.size')" ] \
  || fail "mkpair: small struct is no longer returned in R7/R8"
echo "ok: ABI facts"

[ -s docs/cdp1802/abi.md ] || fail "docs/cdp1802/abi.md missing"
echo "PASS: step 01"
