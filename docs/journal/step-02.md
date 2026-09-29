# Step 02 — Simulator capability audit (GATE)

**Goal:** find out exactly what sim1802 models, compare it with alternatives
and recommend how to get the periodic interrupt and console the port needs.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

Full audit: [`docs/cdp1802/sim1802-audit.md`](../cdp1802/sim1802-audit.md).
Automated re-check: `scripts/test-step-02.sh`.

## What was done, in order

1. Read the whole simulator source at `3b28ed21695b` (`sim1802_io.erl`,
   `sim1802_core.erl`, the loaders, the debugger, the memory module).
2. Wrote the experiments in `toolchain/tests/sim-audit/`:
   - `sim_io.S`: I/O helpers, `LSIE`-based IE readback, `DIS`/`RET`
     inline-byte enable/disable, `IDL`, and an ISR that saves T, D and DF
     through **R0** (never through R2);
   - `irqtest.c`: 10 Hz timer, ticks counted while busy and while idle;
   - `probe.c`: console input, 1804/5/6 opcodes, write protection, HALT;
   - `speed.c`: instructions per second.
3. First `irqtest` run stopped with `@ PC 0x06CE NYI 0x16`. The disassembly
   showed `atoi` is a *stub* in mikpe's libc (`ldi 0x16; .byte 0x68,0x1f`).
   Switched to `strtoul`.
4. First `probe` build failed: `unknown register name 'r6' in 'asm'`. GCC's
   `REGISTER_NAMES` for this target are `"0".."15"`, so the clobber is `"6"`.
5. First `speed` run was meaningless: GCC had turned the loop into a
   multiplication (`n=10^6` took the same time as `n=0`). Made the
   accumulator `volatile`.
6. Downloaded the CDP1805AC/1806AC datasheet (Intersil, March 1997) from
   cosmacelf.com for H4. bitsavers has no 1805 datasheet in
   `components/rca/cosmac/`.
7. Surveyed the alternatives: MAME `src/devices/cpu/cosmac/cosmac.cpp`
   (licence header, `stm()` timer, TODO list) at master `184fb77c08ac`, and the
   Emma 02 repo (`etxmato/emma_02`, licence header of `src/cdp1802.cpp`).

## Commands and trimmed output

```
$ scripts/test-step-02.sh
IE at entry: 0
IE after DIS: 0
IE after RET: 1
busy: 10 ticks, 29277 spins, 2927 spins/tick      <- host busy with a docker build
idle: 10 wakeups, irq_count advanced 10
wall-clock for 21 timer ticks: 2.321163048s
ok: interrupts, IE readback, 10 Hz wall-clock timer
ok: probe getc -> 0, @ Invalid I/O command 0xE1
ok: probe stm -> 1, @ Invalid opcode 0x6807
ok: probe xie -> 1, @ Invalid opcode 0x680A
ok: probe dsav -> 1, @ Invalid opcode 0x6876
ok: probe rldi -> 0, rldi executed
ok: probe wp -> 0, wrote to .text
ok: probe halt -> 42,
speed: 135 instructions/iteration, 100000 iterations in 2.229074531s => 6.05 M instr/s (incl. startup)
PASS: step 02
```

The same `irqtest` on an otherwise idle host (three runs) gave 3 840, 3 997
and 4 097 spins/tick.

```
$ speed: n=0 / 100 / 1000 -> 2 627 / 17 399 / 139 751 traced instructions
$ time speed 100000 -> 2.14 s ; time speed 300000 -> 7.95 s
$ cdp1802-unknown-elf-gcc -march=1804 ... abi.c && run -> abi: PASS (text 12 417 vs 12 792 for 1802)
```

## Measurements

- Simulator speed ≈ 5–7 M instructions/s, roughly 50–90× a 1.76 MHz CDP1802.
- Timer: 10 Hz of host time. Instructions per tick vary by about ±17% with host load.
- `-march=1804` code is 3% smaller on `abi.c` (12 417 vs 12 792 bytes).

## Hypotheses

| # | Result | Evidence |
|---|--------|----------|
| H2 | Interrupt entry semantics confirmed *in the simulator* too (S: `interrupt/1`: T←(X,P), P←1, X←2, IE←0). The R0-based ISR works. | irqtest |
| H3 | Refuted (see step 01). **Confirmed by experiment:** `LSIE` returns IE correctly after DIS and RET. | irqtest lines 1–3 |
| H4 | **Confirmed.** No timer is described for the CDP1802 [MPM, architecture chapter]. The 1805AC/1806AC have an 8-bit presettable down-counter with a TPA÷32 prescaler in Timer mode that raises an internal interrupt on underflow [DS1805 pp. 12–13]. sim1802 does **not** emulate it (`STM` → invalid opcode). | probe stm |

## GO / NO-GO report

**GO for the port**, provided a decision on the time base and console input is made.

Things that already work well enough in sim1802 unchanged: the interrupt model,
an interrupt controller, a periodic interrupt, console output, IDL, exit
status, a debugger, and 64 KiB of RAM.

Problems:

1. **Time is host time.** Tests that depend on timing are non-reproducible, and
   the Step 07 exit criterion ("fires at the expected rate in *simulated* time")
   cannot be checked. The minimum tick is 100 ms.
2. **No cycle counter**, so H5 and `performance.md` cannot report cycles.
3. **No console input**, so no interactive NSH (Step 10).

| Option | Cost | Gets us |
|--------|------|---------|
| **(a) Minimal sim1802 fork** (cycle counter, cycle-driven timer, console input, `--cycles`/`--max-cycles`) | small (Erlang, a few hundred lines + tests) | everything; deterministic tests |
| (b) MAME COSMAC core + new machine driver | large (C++ driver, big MAME build, ELF conversion) | cycle accuracy, real 1805 timer |
| (c) Emma 02 | — | rejected: non-commercial licence, GUI |
| (d) sim1802 unchanged | none | a port with a 10 Hz non-deterministic tick, no interactive NSH, no cycle numbers |

**Recommendation: (a)** — see [ADR 0003](../adr/0003-simulator-strategy.md) (Proposed).

## Decisions requested from Alan

1. **Simulator:** (a) fork sim1802 with the extensions above, or (b)/(d)?
   (§9: "substantially modify the simulator" requires your approval.)
   If (a): where should the fork live (e.g. `github.com/acassis/sim1802`)?
   Until then it would be a local submodule only, like the NuttX branches
   (amendment A2).
2. **Amendments A1–A3** (workspace path, fork location for NuttX/apps, triplet
   spelling). See `docs/amendments.md`.
3. **Toolchain issue 0001** (non-atomic SP update): OK to use the R0-based ISR
   entry as the workaround (a formal ADR comes in Step 07)? Do you want to send
   the draft report to mikpe yourself?
4. **H3 refuted:** Step 07 will use `LSIE` for `up_irq_save()` instead of a
   shadow IE variable. This is a plan change under §9. Please confirm.

## Open questions

- Real-hardware note: the R0-based ISR conflicts with DMA use of R0 on real
  boards. This is out of scope now, but it is documented in issue 0001.
- The simulator's boot-argument block at the top of RAM (down from 0xFFF8)
  overlaps the SIM64 profile's highest addresses. Step 03 must reserve it or
  prove it is harmless (it is written before the program starts).

## Time spent

About 1.5 h wall-clock.
