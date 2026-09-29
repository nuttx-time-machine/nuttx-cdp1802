#!/usr/bin/env bash
# scripts/test-step-02.sh — Step 02 check: every simulator capability claimed
# in docs/cdp1802/sim1802-audit.md is re-verified against the installed
# sim1802.  If the simulator changes (e.g. a fork adds features), this script
# says which audit statements no longer hold.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
S=toolchain/tests/sim-audit
B=build/step02
mkdir -p "$B"
fail() { echo "FAIL: $*"; exit 1; }
cc() { $T-gcc -Os -Wall -Werror -o "$B/$1.elf" "$S/$1.c" "${@:2}"; }

cc irqtest "$S/sim_io.S"
cc probe "$S/sim_io.S"
cc speed

# 1. Interrupts: entry via R1, R0-based ISR, DIS/RET inline byte, LSIE, IDL.
start=$(date +%s.%N)
out=$(scripts/run.sh "$B/irqtest.elf" 10)
elapsed=$(echo "$(date +%s.%N) - $start" | bc)
echo "$out"
grep -qx 'IE at entry: 0' <<< "$out" || fail "loader bootstrap no longer DISables IE"
grep -qx 'IE after DIS: 0' <<< "$out" || fail "DIS/LSIE"
grep -qx 'IE after RET: 1' <<< "$out" || fail "RET/LSIE"
grep -qx 'idle: 10 wakeups, irq_count advanced 10' <<< "$out" || fail "IDL/interrupt"
# 21 ticks (1 sync + 10 busy + 10 idle) at 10 Hz of *host* time => ~2.1 s.
echo "wall-clock for 21 timer ticks: ${elapsed}s"
(( $(echo "$elapsed > 1.8 && $elapsed < 4.0" | bc) )) \
  || fail "timer no longer looks like a 10 Hz wall-clock timer"
echo "ok: interrupts, IE readback, 10 Hz wall-clock timer"

# 2. I/O and ISA probes: "expected status|expected output line".
probe() {
  local arg=$1 want_rc=$2 want_out=$3 out rc
  set +e; out=$(scripts/run.sh "$B/probe.elf" "$arg" 2>&1); rc=$?; set -e
  [ "$rc" = "$want_rc" ] || fail "probe $arg: exit $rc, expected $want_rc ($out)"
  grep -qF "$want_out" <<< "$out" || fail "probe $arg: missing '$want_out' in: $out"
  echo "ok: probe $arg -> $rc, $want_out"
}
probe getc 0 "@ Invalid I/O command 0xE1"   # no console input
probe stm  1 "@ Invalid opcode 0x6807"      # no 1805/6 counter/timer
probe xie  1 "@ Invalid opcode 0x680A"      # no 1805/6 interrupt control
probe dsav 1 "@ Invalid opcode 0x6876"      # 1804AC DSAV missing
probe rldi 0 "rldi executed"                # 1804 register ops present
probe wp   0 "wrote to .text"               # no _fini => no write protection
probe halt 42 ""                            # HALT command status -> exit code

# 3. No cycle counter anywhere in the simulator sources.
if grep -qi 'cycle' <(sed 's/%.*//' toolchain/work/sim1802/src/*.erl); then
  echo "note: 'cycle' appears in sim1802 code (not only comments); re-audit"
fi

# 4. Simulator speed (informative only).
set +e
n1=$(scripts/run.sh -t "$B/speed.elf" 100 2>&1 >/dev/null | wc -l)
n2=$(scripts/run.sh -t "$B/speed.elf" 1000 2>&1 >/dev/null | wc -l)
set -e
per=$(( (n2 - n1) / 900 ))
start=$(date +%s.%N); scripts/run.sh "$B/speed.elf" 100000; t=$(echo "$(date +%s.%N) - $start" | bc)
echo "speed: $per instructions/iteration, 100000 iterations in ${t}s" \
     "=> $(echo "$per * 100000 / $t / 1000000" | bc -l | cut -c1-4) M instr/s (incl. startup)"

echo "PASS: step 02"
