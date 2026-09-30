#!/usr/bin/env bash
# scripts/cycles-per-tick.sh <.config> -- machine cycles per system tick of
# a sim1802 build: CONFIG_BOARD_SIM1802_CLOCK_HZ (default 4 MHz) / 8 clocks
# per machine cycle x CONFIG_USEC_PER_TICK, as sim1802_timer.c computes it.
set -euo pipefail
clock=$(sed -n 's/^CONFIG_BOARD_SIM1802_CLOCK_HZ=//p' "$1"); clock=${clock:-4000000}
usec=$(sed -n 's/^CONFIG_USEC_PER_TICK=//p' "$1")
echo $((clock / 8 * usec / 1000000))
