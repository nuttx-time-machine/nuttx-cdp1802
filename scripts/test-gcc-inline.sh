#!/usr/bin/env bash
# scripts/test-gcc-inline.sh -- the GCC options -minline-calls,
# -minline-compare and -minline-shifts (toolchain patch 0002, ADR 0023).
# toolchain/tests/inline/gen.py writes a program that prints every 16-bit
# comparison code on edge values (register and constant operands), every
# constant shift and some calls, and the expected text computed in Python.
# The program is built with each option alone, all three together and none,
# at -Os and -O2, run in sim1802, and its output must equal the expected
# text exactly.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }
B=build/gcc-inline; mkdir -p $B
python3 toolchain/tests/inline/gen.py $B/inline.c $B/expected.txt || fail "gen"
n=0
for opt in -Os -O2; do
  for flags in "" -minline-calls -minline-compare -minline-shifts \
               "-minline-calls -minline-compare -minline-shifts"; do
    name=$(echo "x$opt$flags" | tr -d ' ')
    $CDP1802_TARGET-gcc $opt $flags -o $B/$name.elf $B/inline.c \
      || fail "compile $opt $flags"
    RUN_TIMEOUT=600 scripts/run.sh $B/$name.elf > $B/$name.out 2>&1 \
      || { tail -5 $B/$name.out; fail "run $opt $flags"; }
    diff -q $B/expected.txt $B/$name.out > /dev/null \
      || { diff $B/expected.txt $B/$name.out | head -10; fail "output $opt $flags"; }
    echo "ok: $opt ${flags:-(no inline options)}: $(wc -c < $B/$name.out) bytes of output match"
    n=$((n + 1))
  done
done
echo "PASS: gcc inline options ($n builds)"
