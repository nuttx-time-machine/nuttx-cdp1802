#!/usr/bin/env bash
# scripts/test-sim-fork.sh — checks the cdp1802-nuttx sim1802 fork (ADR 0003)
# from the guest side: deterministic cycle timer, cycle counter, IDL
# fast-forward, --pace, --max-cycles, console input (polled and IRQ 6), and
# that upstream behaviour (10 Hz wall-clock timer) still works.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

T=$CDP1802_TARGET
A=toolchain/tests/sim-audit
F=toolchain/tests/sim-fork
B=build/simfork
mkdir -p "$B"
fail() { echo "FAIL: $*"; exit 1; }
cc() { $T-gcc -Os -Wall -Werror -o "$B/$1.elf" "$2" "$A/sim_io.S"; }

cc cyctimer "$F/cyctimer.c"
cc conin "$F/conin.c"
cc conirq "$F/conirq.c"
cc irqtest "$A/irqtest.c"

# 1. Determinism: the full output, including the total cycle count, is
#    identical on every run.
out1=$(scripts/run.sh --cycles "$B/cyctimer.elf" 2>&1)
out2=$(scripts/run.sh --cycles "$B/cyctimer.elf" 2>&1)
echo "$out1"
[ "$out1" = "$out2" ] || fail "cycle timer output differs between runs"
busy=$(sed -n 's/^busy: 10 ticks, [0-9]* spins, \([0-9]*\) cycles$/\1/p' <<< "$out1")
[ -n "$busy" ] && [ "$busy" -ge 100000 ] && [ "$busy" -lt 101000 ] \
  || fail "10 ticks of 10000 cycles measured as '$busy' cycles"
grep -q '^idle: 10 wakeups, irq_count +10, ' <<< "$out1" || fail "IDL fast-forward"
echo "ok: deterministic cycle timer (10 ticks = $busy cycles incl. read-out)"

# 2. --pace 4 MHz: 10 idle ticks of 10000 cycles = 10 x 20 ms of host time.
start=$(date +%s.%N)
scripts/run.sh --pace 4000000 "$B/cyctimer.elf" > /dev/null
t=$(echo "$(date +%s.%N) - $start" | bc)
(( $(echo "$t >= 0.2" | bc) )) || fail "--pace did not wait (${t}s)"
echo "ok: --pace (${t}s)"

# 3. --max-cycles
set +e; out=$(scripts/run.sh --max-cycles 5000 "$B/cyctimer.elf" 2>&1); rc=$?; set -e
[ $rc -eq 96 ] && grep -q '@ Cycle limit 5000 reached' <<< "$out" || fail "--max-cycles ($rc)"
echo "ok: --max-cycles -> 96"

# 4. Console input, polled and interrupt driven, including delayed input.
[ "$(printf 'Hello, NuttX!\n' | scripts/run.sh "$B/conin.elf")" = "hELLO, nUTTx!
[14 bytes]" ] || fail "polled console input"
out=$( (sleep 0.3; printf 'late\n'; sleep 0.3; printf 'later\n') | RUN_TIMEOUT=20 scripts/run.sh "$B/conirq.elf")
[ "$out" = "late
later
[11 bytes, irq]" ] || fail "IRQ-driven console input: $out"
echo "ok: console input (polled, IRQ 6, delayed chunks, EOF)"

# 5. ROM emulation: __sim1802_rom_end write-protects [0, limit).
printf '.global __sim1802_rom_end\n.set __sim1802_rom_end, 0x8000\n' > "$B/romend.s"
$T-gcc -Os -o "$B/probe-rom.elf" "$A/probe.c" "$A/sim_io.S" "$B/romend.s" -Wl,-Tdata=0x8000
set +e; out=$(scripts/run.sh "$B/probe-rom.elf" wp 2>&1); rc=$?; set -e
[ $rc -eq 97 ] && grep -q 'write to write-protected address' <<< "$out" \
  || fail "ROM write not trapped ($rc)"
set +e; scripts/run.sh "$B/probe-rom.elf" halt; rc=$?; set -e
[ $rc -eq 42 ] || fail "program with protected ROM does not run ($rc)"
echo "ok: __sim1802_rom_end write protection"

# 6. Upstream behaviour kept: 10 Hz wall-clock timer, LSIE, DIS/RET, IDL.
out=$(scripts/run.sh "$B/irqtest.elf" 5)
grep -qx 'idle: 5 wakeups, irq_count advanced 5' <<< "$out" || fail "10 Hz timer: $out"
echo "ok: upstream 10 Hz timer mode unchanged"

echo "PASS: sim1802 fork"
