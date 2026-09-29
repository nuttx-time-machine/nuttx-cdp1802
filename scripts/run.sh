#!/usr/bin/env bash
# scripts/run.sh <elf> [args...] — run an ELF in sim1802.
#
# The simulator's exit status is the program's exit status (the value written
# with the HALT I/O command; see docs/cdp1802/board-sim1802.md from Step 03).
# RUN_TIMEOUT (seconds, default 120) bounds wall-clock time, so that a hung
# test cannot block CI; timeout(1) returns 124 in that case.
set -euo pipefail
. "$(dirname "$0")/env.sh"
[ $# -ge 1 ] || { echo "usage: $0 <elf> [args...]" >&2; exit 2; }
exec timeout "${RUN_TIMEOUT:-120}" "$CDP1802_TARGET-sim" "$@"
