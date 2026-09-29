# Step 03 — Virtual board definition (in progress)

**Goal:** define the `sim1802` virtual board (memory map, reset, ROM/RAM
layout, console, timer, halt) on top of the simulator chosen at the Step 02
gate.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## Part 1 — the sim1802 fork (ADR 0003, accepted)

Alan: "ok to fork sim1802 … create a local git repository to it. Then I will
add it to my github later."

### What was done, in order

1. Added `simulator/` as a submodule (full upstream history, 72 commits) and
   created branch `cdp1802-nuttx` at `3b28ed21695b`. The `.gitmodules` URL
   is mikpe's repository until Alan publishes the fork (amendment A4).
2. Looked up machine-cycle counts: RCA MPM-201A p. 8 (2, or 3 for long
   branch/skip) and the Intersil CDP1805AC/1806AC datasheet instruction
   summary for the 68-prefixed instructions (RLDI/RLXA/RSXD/DBNZ 5, RNX 4,
   SCAL 10, SRET 8, DSAV 6, BCD ops 4, counter ops 3). NOP is also 3 cycles
   (datasheet: "NO OPERATION 3 NOP C4").
3. Implemented cycle accounting in `sim1802_core`, then the timer, counter
   and console commands in `sim1802_io`, then the command-line options.
4. **Failures along the way**, in order:
   - Build failed: `function cycle_timer/0 undefined`, among others.
     Erlang macros must be defined before use, and some `-define`s had been
     placed next to the code that used them, *after* earlier uses. Moved them
     to the top of the module.
   - Every program crashed: `no case clause matching 0 in
     sim1802_core:sync_cycle_timer/1`. `cycle_timer/0` returned only the
     period (`ets:lookup_element(…, 2)`), not `{Period, Generation}`.
   - `test-step-02.sh` failed (`probe getc`). This was expected: the fork
     implements console input on purpose. Upstream sim1802 is now built and
     installed as `cdp1802-unknown-elf-sim-upstream`, and the Step 02 audit
     test runs against it (`SIM=` override in `scripts/run.sh`).
   - The first console-input design (read-modify-write of one ETS queue value
     from two processes) could lose bytes. It was replaced before any test
     by an `ordered_set` with a single inserter and `ets:take/2` for the
     consumer.
   - `conirq` (interrupt-driven input) **hung** (killed by the 120 s timeout).
     First cause: the generic test ISR re-enabled IRQ 6 without draining
     input, so it re-entered forever. The test now re-enables from the main
     loop after draining.
   - It **hung again** with input arriving in two delayed chunks. A trace
     showed only 2 `IDL`s. Cause: `GETCHAR` re-raised IRQ 6 while bytes
     remained, but nothing cleared the pending bit once the queue was empty.
     Re-enabling IRQ 6 fired a stale interrupt, whose acknowledge disabled
     IRQ 6 again just before `IDL`. Fix: IRQ 6 is now level-triggered
     (pending exactly while input is queued). While reading this code I found
     that the pending register is read-modify-written by several Erlang
     processes (a latent upstream race), and made the per-IRQ updates atomic.
   - End of input: an interrupt-driven reader sleeping in `IDL` would never
     notice EOF, so the simulator raises IRQ 6 once at EOF.
   - While splitting the work into logical commits, eunit reported "6 tests"
     where 8 were expected: stale `_build/test` artefacts. Each fork commit
     was then re-verified from a clean build: `f9250e7` 6 tests, `fd79dc3`
     8, `a63cf9e` 8, all builds OK (xref + dialyzer).
5. Integrated the fork into the meta repo: `toolchain/VERSIONS` (`SIM_SRC`,
   `SIM_SHA`, `SIM_UPSTREAM_*`). `build-toolchain.sh` builds the fork from the
   submodule and refuses to build if it is not at `SIM_SHA` or has
   uncommitted changes. The Dockerfile copies `simulator/`, and
   `.dockerignore` keeps the large trees out of the build context.
6. Wrote `scripts/test-sim-fork.sh` and `docs/cdp1802/sim1802-fork.md`.

### Test output

```
$ scripts/test-sim-fork.sh
busy: 10 ticks, 371 spins, 100256 cycles
idle: 10 wakeups, irq_count +10, 96734 cycles
@ cycles 758681
ok: deterministic cycle timer (10 ticks = 100256 cycles incl. read-out)
ok: --pace (.402454131s)
ok: --max-cycles -> 96
ok: console input (polled, IRQ 6, delayed chunks, EOF)
ok: upstream 10 Hz timer mode unchanged
PASS: sim1802 fork
$ scripts/test-step-01.sh | tail -1
PASS: step 01
$ scripts/test-step-02.sh | tail -1        # against upstream sim1802
PASS: step 02
```

### Measurements

- `hello.elf`: 1 313 instructions (trace) = 2 740 machine cycles
  (`--cycles`), i.e. 2.09 cycles per instruction.
- The cycle-timer run is identical across runs *and* across environments: the Docker container (Ubuntu 24.04, `docker build` + all three test scripts, `EXIT 0`) also measures `10 ticks = 100256 cycles`.

## Part 2 — board definition

Not started yet.
