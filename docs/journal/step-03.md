# Step 03 — Virtual board definition

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

### What was done, in order

1. Collected the facts the board depends on:
   - reset state: I, N, X, P = 0, R(0) = 0, Q = 0, IE = 1, execution from
     M(0000) [MPM p. 72, Fig. 86] — and the simulator's `init/2` matches;
   - the loader writes a boot-argument block (magic, argc/argv/envp and the
     filtered environment variables HOME, HOSTNAME, HOSTTYPE, MACHTYPE, OSTYPE,
     PATH, USER) down from 0xFFF8, after loading the image;
   - the loader rejects loadable bytes above 0xFF00 (`PAddr + FileSz =< 65536 - 256`);
   - clock: MPM uses a 4-MHz example (p. 68); CDP1805AC maximum 5 MHz at 5 V
     [DS1805 p. 4]. Chosen: nominal 4 MHz, configurable.
2. Added `__sim1802_rom_end` to the fork (commit `bef5700`) so that a board
   image, which has no `_fini`, can get ROM write protection. Verified with a
   probe program: with the limit at 0x8000 but `.data` still in low memory,
   mikpe's libc start-up **trapped** writing its own `.data` at 0x2D1B —
   correct behaviour for an image not laid out for ROM; relinked with
   `-Wl,-Tdata=0x8000` it runs, and a write into `main` traps (status 97).
3. Wrote a **freestanding smoke program** (`toolchain/tests/board/smoke.S`, no
   libc, no NCRT) and a HW32/32 linker-script prototype (`hw32.ld`): reset at
   0, `.data` copy, `.bss` clear, console, cycle-timer IRQs via the R0 ISR,
   IDL, halt.
4. **First run printed `ticks=` followed by an unprintable byte.** `readelf -l`
   showed the `.data` segment with VirtAddr 0x8000 and PhysAddr 0x151; the
   loader loaded at `p_vaddr`, so the ROM copy at 0x151 was never written and
   the start-up copy moved zeros (ticks = 0 + 5 = 0x05). Fixed in the fork:
   load at `p_paddr` (commit `1be386b`). Then: `sim1802 board ok, ticks=5`.
   hello/softfloat/abi still pass (their `p_paddr == p_vaddr`).
5. Wrote the SIM64 prototype (`sim64.ld`) and ran the same program. Added
   linker `ASSERT`s: HW32/32 ROM overflow, and the 0xFF00 loader limit.
6. Wrote `docs/cdp1802/board-sim1802.md` (memory-map diagram, devices,
   constraints), ADR 0005 and `scripts/test-step-03.sh`.
7. The first version of the SIM64 oversize check passed for the wrong reason
   (the test image overflowed the whole region, so the generic "will not fit"
   error fired). Changed it to an image ending between 0xFF00 and 0xFFFF and
   required the specific assert message.

### Test

```
$ scripts/test-step-03.sh
PASS: sim1802 fork
ok: hw32 smoke (@ cycles 26109)
ok: hw32 ROM write -> 97
ok: sim64 smoke (@ cycles 26109)
ok: sim64 ROM write -> 97
ok: linker scripts reject oversized images
PASS: step 03
```

### Measurements

- Smoke program: 26 109 machine cycles for start-up, 5 ticks of 5 000
  cycles, and 26 bytes of console output — identical on every run and in
  both profiles.
- Image: `.text`+`.rodata` 0x151 = 337 bytes, `.data` 5, `.bss` 4.

### Hypotheses

- **H2** (interrupt entry, R1 = ISR PC): used as designed by the smoke test's
  R0-based ISR; see toolchain issue 0001 for the R2 part.
- **H6**: nothing new (no NuttX code yet); the profiles that the judgement
  will use are now defined and executable.

### Open questions for Alan

- **ADR 0005 needs your acceptance** (the contract's Step 03 exit criterion
  is "the ADR is accepted"). The step will be tagged `step-03-board` after that.
- `docs/cdp1802/primer.md` (CONTRACT §7.4) is not written yet; planned
  alongside Step 05 (porting-guide chapters 3–5).

### Time spent

About 2 h wall-clock for both parts.
