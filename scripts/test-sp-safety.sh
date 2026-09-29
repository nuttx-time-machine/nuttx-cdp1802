#!/usr/bin/env bash
# scripts/test-sp-safety.sh — toolchain issue 0001 / ADR 0007: the patched
# compiler never leaves R2 above the live stack top.
#
# 1. Static: check-sp-safety.py accepts every composite R2 update in images
#    built by the installed compiler (validation programs, which include
#    libgcc soft-float and mikpe's libc).
# 2. Dynamic: an interrupt with a standard R2-stack handler fires every few
#    hundred machine cycles while functions with 20-byte, 300-byte and
#    variable-size frames check their frames around nested calls, with the
#    stack shifted over all 256 alignments.  Any torn SP update would corrupt
#    a live frame (demonstrated with the unpatched compiler: 30 corrupted
#    bytes at period 211, and a hang at period 157; see the journal).
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
B=build/sp-safety
mkdir -p "$B"
fail() { echo "FAIL: $*"; exit 1; }

# mikpe's crt0 _start sets the first SP at boot, with interrupts disabled by
# the simulator's loader bootstrap (DIS) and never enabled before it: exempt.
chk() { python3 scripts/check-sp-safety.py --allow _start "$1"; }

for t in hello softfloat abi; do
  $T-gcc -Os -o "$B/$t.elf" "toolchain/tests/$t.c"
  chk "$B/$t.elf" | tail -1 | grep -q 'sp-safety: OK' || { chk "$B/$t.elf"; fail "$t"; }
done
echo "ok: static check of hello, softfloat, abi (libgcc + libc included)"

$T-gcc -Os -Wall -Werror -o "$B/stress.elf" toolchain/tests/sp-safety/stress.c \
  toolchain/tests/sp-safety/isr_r2.S toolchain/tests/sim-audit/sim_io.S
chk "$B/stress.elf"
for p in 157 211 331; do
  out=$(RUN_TIMEOUT=300 scripts/run.sh "$B/stress.elf" $p 256) || fail "stress period $p: $out"
  echo "$out"
  grep -q 'errors=0$' <<< "$out" || fail "stress period $p"
done
echo "PASS: sp-safety"
