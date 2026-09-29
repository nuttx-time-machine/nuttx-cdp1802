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

## Gate outcome (Alan, 2026-09-29)

| Question | Decision |
|----------|----------|
| 1. Simulator | **Fork sim1802** (ADR 0003 accepted). Local fork, amendment A4. |
| 2. A1 workspace | Accepted: stays in `/home/alan/NUTTX_CDP1802`. |
| 2. A2 upstream remotes | Accepted ("ok, no problem"). |
| 2. A3 triplet | Provide `cdp1802-elf-*` → implemented as symlinks in `build-toolchain.sh`. |
| 3. R0-based ISR | **Superseded by ADR 0006** (register convention, R0 free for DMA). Originally: OK *if it works on a real machine without hardware modification*. Analysis added to toolchain issue 0001: yes on boards without DMA; boards that use DMA need the R2 entry plus an interrupt-safe toolchain. |
| 4. LSIE vs shadow IE | Alan asked for an explanation of the impact and NuttX precedent. Answer below; decision still open. |

### Q4: using `LSIE` instead of a software interrupt-enable flag

NuttX asks the architecture for `irqstate_t up_irq_save(void)` (return the
current enable state and disable) and `void up_irq_restore(irqstate_t)`.
Critical sections (`enter_critical_section()` in non-SMP builds) are built on
them.

**Precedent: every existing NuttX port reads the hardware state.** No port
keeps a software shadow (`grep` over `arch/*/include` and `arch/*/src` at
the pinned commit):

| Port | How the state is read | Where |
|------|----------------------|-------|
| AVR | `in %0, __SREG__; cli` | `arch/avr/include/avr/irq.h:183` |
| Z80 | `ld a, i` (copies IFF2 into the P/V flag), `di` | `arch/z80/src/z80/z80_irq.c:46` |
| eZ80 | same `ld a, i; di` trick | `arch/z80/src/ez80/ez80_irqsave.asm:50` |
| Z8 | reads the IRQCTL register, `DI()` | `arch/z80/src/z8/z8_irq.c:83` |
| ARMv7-M | PRIMASK/BASEPRI, also saved per context (`REG_BASEPRI`) | `arch/arm/src/armv7-m/arm_initialstate.c:164` |

The Z80 is the closest precedent. Like the 1802, it has no instruction that
simply loads the IE flip-flop. NuttX uses a side effect of another instruction
(`ld a,i` sets P/V from IFF2), just as `LSIE` exposes IE through a skip.

Consequences of `LSIE` for the CDP1802 port:

1. **Same model as the other ports.** `irqstate_t` is a `uint8_t` (0/1),
   returned in R7. No NuttX common code changes.
2. **Race-free read-then-disable.** If an interrupt arrives between `LSIE`
   and `DIS`, the ISR ends with `RET`, which sets IE=1 again, so the value
   just read is still true. If that interrupt causes a context switch, the
   thread's IE is restored to 1 when it resumes, and the pending `DIS`
   executes then. The same argument holds for Z80 `ld a,i; di`.
3. **The context switch gets IE for free.** A thread-level switch
   (`up_switch_context()`) must save the outgoing thread's IE. With `LSIE`
   that is one skip instruction. On restore, the port ends with `RET` (IE=1)
   or `DIS` (IE=0), which also restore X and P from the saved byte. That is
   the same exit path as an interrupt return, so one code path serves both.
   A software shadow instead has to be kept equal to the hardware flip-flop
   everywhere: the hardware clears IE on every interrupt entry without
   telling the shadow, so every ISR entry/exit, every context switch and
   every `DIS`/`RET` would also have to update a RAM variable, and each
   thread would need its own copy.
4. **Smaller and faster.** Sketch (NCRT ABI, flags in R7):
   ```
   up_irq_save:                      up_irq_restore:
       ldi  0                            glo  7
       phi  7                            lbz  1f
       ldi  1       ; assume IE=1        sex  3
       lsie         ; IE=1: skip 2 bytes ret           ; IE := 1
       ldi  0       ; IE was 0           .byte 0x23    ; X=2, P=3
       plo  7                            sep  5
       sex  3                        1:  sex  3
       dis          ; IE := 0            dis           ; IE := 0
       .byte 0x23   ; X=2, P=3           .byte 0x23
       sep  5                            sep  5
   ```
   `up_irq_save` is 13 bytes and `up_irq_restore` 12, with no RAM and no
   pointer setup. This exact code runs in the simulator
   (`toolchain/tests/sim-audit/irqsave.{S,c}`, checked by
   `scripts/test-step-02.sh`: nested save/restore with IE both 1 and 0).
   The first attempt used the short branch `bz` and failed to link
   (`relocation truncated to fit: R_CDP1802_8`): 1802 short branches only
   reach targets in the same 256-byte page [MPM p. 31], so arch code must use
   long branches unless the placement is controlled. A shadow needs its
   16-bit address loaded into a register first (4 instructions on this CPU,
   because there is no absolute addressing), plus the load/store. Code size
   is the main risk of this port (H6).
5. **Constraint:** the inline byte `0x23` hard-codes X=2, P=3. That is valid
   because all compiled code runs with P=3 and X=2 (abi.md §2), but these
   routines must never be called from code running with another P, such as
   the NCRT routines (which never call them).
6. **Verified so far only in sim1802** (irqtest: IE 0 → DIS 0 → RET 1).
   `LSIE` is documented for the plain CDP1802 [MPM p. 38, p. 99, p. 103], but
   has not been tested on real silicon.

**Recommendation:** use `LSIE` (as the other NuttX ports read their hardware
state). The Step 07 ADR will record this, unless Alan decides otherwise.

### Follow-up: GPL libc, newlib and NuttX's own libc (Alan, 2026-09-29)

Alan asked whether newlib could replace mikpe's GPL libc, and noted that NuttX has its own libc.

- NuttX does not link an external libc: GNU ports use `-nostdlib` and
  `libs/libc/` (Apache-2.0). mikpe's libc was only ever meant for the
  toolchain validation programs.
- newlib: no CDP1802 port, neither upstream (`configure.host`, 0 matches out of 981
  lines) nor in mikpe's newlib fork (only other targets' branches).
- A real, hidden dependency was found and removed: libgcc had been built
  against mikpe's headers (`_eprintf.o` → `__libc_stderr`). GCC is now built
  with `--without-headers --with-newlib` (`inhibit_libc = true`).
  - First attempt with `--without-headers` alone failed with
    `The directory (BUILD_SYSTEM_HEADER_DIR) ... does not exist`. Creating an
    empty `sysroot/usr/include` fixed that, but the next failure was
    `tsystem.h:95:10: fatal error: stdio.h: No such file or directory`,
    because GCC's configure only sets `inhibit_libc` with a sysroot when
    `--with-newlib` is also given (`gcc/configure.ac:2578`).
  - Result: libgcc's external symbols are `abort free malloc memcpy memset strlen`,
    the member list is unchanged, and the validation images are byte-identical.
  - The GCC rebuild took 3 min 24 s. `test-step-01.sh` and `test-step-02.sh` pass.
- Decision recorded in [ADR 0004](../adr/0004-libc-independence.md).
- Docker image rebuilt with the new GCC configuration (`nuttx-cdp1802-toolchain:latest`). `scripts/test-step-01.sh` passes inside it, including the `cdp1802-elf-*` name check.

### Q4 decision (Alan, 2026-09-29)

"use LSIE by default, but add the option to use software interrupt-enable
flag. That option should be later selected on NuttX Kconfig."

→ Step 07 implements both behind a Kconfig choice in `arch/cosmac/Kconfig`,
e.g. `COSMAC_IRQSTATE_LSIE` (default) and `COSMAC_IRQSTATE_SWFLAG`. Both are
covered by the Step 07 ADR and the step tests. The software-flag variant must
keep the flag coherent with the hardware IE on interrupt entry/exit and on
context switch. The ADR will list those update points.

Alan also asked for the sim1802 fork to be a local git repository that he
will publish on GitHub later (amendment A4).
