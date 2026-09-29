# 0003 — Simulator strategy: periodic interrupt, time base and console input

Status: **Proposed — awaiting Alan's decision (Step 02 GATE)**
Date: 2026-09-29
Step: step-02-sim-audit

## Context

The port needs a periodic interrupt and a console (CONTRACT Step 02). The
audit ([`docs/cdp1802/sim1802-audit.md`](../cdp1802/sim1802-audit.md)) found
that sim1802 at `3b28ed21695b` provides:

- the exact CDP1802 interrupt entry, an 8-line interrupt controller, IDL, console output, exit status, ELF loading and a debugger;
- a periodic IRQ0 at 0.1/1/10 Hz of **host wall-clock time**. It is not deterministic: instructions per tick varied from 2 927 to 4 097 across runs, depending on host load;
- **no** cycle counter, **no** console input (command 0xE1 reserved but unimplemented) and **no** 1805/1806 counter/timer.

## Options considered

a. **Minimal fork of sim1802** (Apache-2.0): add a machine-cycle counter, a
   timer mode driven by that counter, console input (0xE1 + IRQ6) and
   `--cycles`/`--max-cycles`. All existing behaviour is unchanged. Estimated
   size: a few hundred lines of Erlang in `sim1802_io.erl`/`sim1802_core.erl`,
   plus tests.
b. **MAME COSMAC core** (BSD-3-Clause core): cycle-accurate, with a real 1805
   Timer mode. Needs a new MAME machine driver in C++, a large MAME build, and
   ELF→raw conversion. It is also a different simulator from the one the GCC
   testsuite runs on.
c. **Emma 02**: its licence forbids commercial use without permission, and it
   is GUI-oriented. Rejected.
d. **sim1802 unchanged**: use the 10 Hz wall-clock tick, accept non-deterministic
   timing tests, measure performance by instruction counts from `-t` traces,
   and have no interactive NSH.

## Decision

Pending. **Recommendation: (a)**, as a git submodule `simulator/` (a fork of
mikpe/sim1802, branch `cdp1802-nuttx`), so that the port and its tests are
deterministic and NSH can be interactive.

## Consequences (if (a) is accepted)

- `toolchain/VERSIONS` gets `SIM_URL`/`SIM_SHA` pointing at the fork, and
  `build-toolchain.sh` builds it instead of upstream.
- The board definition (Step 03) uses the deterministic timer as the NuttX
  tick. The 10 Hz host timer remains for compatibility.
- Performance numbers (H5, `performance.md`) become real cycle counts.
- A pull request to mikpe could be drafted but not sent (CONTRACT §10).

## How to revisit

If mikpe adds equivalent features upstream, switch back to upstream sim1802
with a new ADR. If cycle accuracy against real silicon becomes important
(e.g. before real-hardware bring-up), reconsider MAME.
