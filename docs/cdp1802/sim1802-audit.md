# sim1802 capability audit (Step 02)

Simulator: `mikpe/sim1802` at `3b28ed21695b` (Apache-2.0, Erlang, 3 625 lines
in `src/`), run with Erlang/OTP 28.5.0.7.

Every statement below is backed by (S) a line in the simulator source, or (E)
an experiment in `toolchain/tests/sim-audit/`, re-run by
`scripts/test-step-02.sh`. Hardware references: [MPM] RCA MPM-201A (printed
page numbers); [DS1805] Intersil *CDP1805AC, CDP1806AC* datasheet, March 1997
(30 pp., from cosmacelf.com `publications/data-sheets/cdp1806.pdf`).

## Summary

| Capability | NuttX needs it for | sim1802 | Verdict |
|------------|--------------------|---------|---------|
| CDP1802 instruction set | everything | complete (S: `execute/2` covers 00–FF) | ✅ |
| CDP1804/1804AC extended ops | optional (`-march=1804`) | partial: DBNZ, RLXA, SCAL, SRET, RSXD, RNX, RLDI, the BCD ops; **no** counter/timer ops, **no** XIE/XID/CIE/CID/BCI/BXI, **no** DSAV (E) | ⚠ 1804 code generation works; the 1805/6 timer is unusable |
| INT pin / interrupt entry | tick, context switch | exact [MPM p. 40] semantics: X,P→T; P=1; X=2; IE=0 (S: `interrupt/1`) | ✅ |
| Interrupt sources | tick, console | 8-line controller on I/O ports 6/7: IRQ0 = timer, IRQ6 = console (reserved, **no input implemented**) | ⚠ |
| Periodic timer | system tick | IRQ0 at 0.1, 1 or 10 Hz of **host wall-clock time** (S: `timer_delay/1`, Erlang `after DelayMs`) | ⚠ usable, not deterministic, 100 ms minimum period |
| Cycle counting | performance numbers (H5), deterministic time | **none** (S: no cycle accounting in `sim1802_core.erl`) | ❌ |
| Console output | lowputc, syslog, serial driver | `OUT 6` byte, `OUT 7` 0xE0 → host stdout (S: `console_putchar/0`) | ✅ |
| Console input | NSH (Step 10) | command 0xE1 is defined in `sim1802_io.hrl` but **not implemented**: prints `@ Invalid I/O command 0xE1` (E) | ❌ |
| DMA (R0) | not needed | **not modelled** (no DMA code in S). R0 is only the reset PC | ✅ (NuttX still leaves R0 to DMA by convention, ADR 0006) |
| IDLE | idle loop | `IDL` blocks until an interrupt is pending; with IE=0 it traps `deadlock` (S: `emu_IDL/1`) | ✅ |
| Memory | whole system | 64 KiB flat RAM (S: `atomics:new(65536)`) | ✅ SIM64 |
| ROM emulation | HW32/32 profile | write-protects `[0, _fini)` or `[0, __DTOR_END__)` if the symbol exists; this toolchain defines neither, so nothing is protected (E: probe `wp`) | ⚠ a NuttX linker script can define `_fini` at the end of ROM |
| Exit/halt for tests | automated tests | `OUT 6` status, then `OUT 7` 0x00 → process exits with that status (E: probe `halt` → 42). Trap → 97, NYI → 98, bad opcode → 1 | ✅ |
| Loader | boot | ELF or Intel HEX. For ELF it writes `DIS; 0x00; LBR entry` at address 0 and the boot args (magic 0x1802, argc/argv/envp) at the top of RAM, down from 0xFFF8 | ✅ note the RAM-top overwrite |
| Debugging | bring-up | `-t` trace of every instruction (with symbols), `-d` interactive debugger with breakpoints | ✅ |
| Speed | test run time | ≈ 5–7 M instructions/s on the dev host (E: `speed.c`, 135 instructions/iteration) | ✅ ≈ 50–90× a 1.76 MHz 1802 (see below) |

## Details

### Interrupt entry (E: `irqtest.c` + `sim_io.S`)

The experiment installs an ISR through R1 and enables IRQ0 at 10 Hz. It counts
ticks while busy-waiting, then counts `IDL` wake-ups:

```
IE at entry: 0
IE after DIS: 0
IE after RET: 1
busy: 10 ticks, 38401 spins, 3840 spins/tick
idle: 10 wakeups, irq_count advanced 10
```

This also validates three design points for Step 07:

1. **`LSIE` reads IE** [MPM p. 38]. `ie_is_set()` returns 0/0/1 as expected.
   A software shadow of IE (H3) is not needed.
2. **The `DIS`/`RET` inline-byte technique** [MPM p. 41, p. 65–66] works with
   `SEX 3; DIS; .byte 0x23`, which restores X=2, P=3.
3. **An ISR that uses R0, not R2, as its save pointer** works. The interrupted
   R2 is never written through, which sidesteps the torn-SP hazard of
   [toolchain issue 0001](../toolchain-issues/0001-non-atomic-sp-update.md).

Interrupts are sampled after every instruction (S: `do_step/1`) when IE=1 and
(enabled ∧ pending) ≠ 0. Acknowledging (command 0x10) returns the lowest
pending+enabled IRQ in the buffer (8 = spurious) and **clears that IRQ's
enable bit**, so the handler must re-enable it (command 0x13).

### The timer is host-time based

`timer_enabled_loop/1` is an Erlang process that sets IRQ0 every `DelayMs`
milliseconds of real time. Consequences, all measured:

- 21 ticks take 2.3 s of wall-clock time (test-step-02).
- Instructions per tick vary with host load: spins per tick were 3 840, 3 997
  and 4 097 on an idle host, and **2 927** while a Docker build ran in parallel.
  Simulated software therefore sees a *different number of instructions per
  tick on every run*. Timing-dependent tests (e.g. `ostest`'s timed waits)
  are not reproducible, and "watchdog fires at the expected rate in *simulated*
  time" (Step 07 exit criterion) cannot be checked, because simulated time
  does not exist.
- The shortest period is 100 ms (`CONFIG_USEC_PER_TICK=100000`). That is
  workable for NuttX but coarse.

### Speed

`speed.c` (a `volatile` 16-bit add plus a 32-bit loop counter) executes 135
instructions per iteration (difference of `-t` traces at n=100 and n=1000).
100 000 iterations = 13.5 M instructions ran in ≈ 2.0–2.2 s, and 300 000
iterations in 7.8 s: **≈ 5–7 M instructions/s**.

A real CDP1802 needs 2 machine cycles per instruction, or 3 for long
branches and long skips [MPM p. 8; per-opcode table pp. 99–105], and each
machine cycle is 8 clock pulses [MPM p. 70]. With a 1.76 MHz clock that is
73–110 k instructions/s, so sim1802 is roughly
50–90 times faster than a typical real 1802. This is an estimate: the
simulator cannot count cycles.

### What is *not* there

- **Cycle counter:** needed for the H5 measurement ("≈2 000 clocks per context
  save+restore") and for deterministic time.
- **Console input:** needed for an interactive NSH (Step 10) and for scripted
  NSH tests.
- **1805/1806 counter/timer:** [DS1805 pp. 12–13] describes an 8-bit
  presettable down-counter with a TPA÷32 prescaler in Timer mode, which
  raises an internal interrupt on underflow. So **H4 is confirmed** for the
  hardware, but sim1802 does not emulate it (`STM` → invalid opcode).
- **DMA, EF1–EF4 inputs** (the `set_ef*` functions exist but nothing calls them).

## Alternatives

| | sim1802 (as is) | sim1802 fork (minimal extensions) | MAME COSMAC core | Emma 02 |
|--|--|--|--|--|
| License | Apache-2.0 | Apache-2.0 | core `cosmac.cpp`: BSD-3-Clause (MAME overall GPL-2.0+) | custom: "may not be used in commercial applications without express written permission" (`src/cdp1802.cpp` header) |
| ELF loading | yes | yes | no (needs raw/HEX conversion or a Lua loader) | no (machine-specific formats) |
| Deterministic time | no | yes (cycle counter) | yes (cycle-accurate scheduler) | yes |
| 1805/1806 timer | no | optional | yes, Timer mode `stm()` (other counter modes TODO in source) | yes |
| Virtual board with console + timer | yes | yes | needs a new MAME *machine driver* (C++) | fixed historical machines only |
| Headless/scripting | yes (CLI, exit status) | yes | `-video none -sound none`, Lua `-autoboot_script` | wxWidgets GUI |
| Build cost | done | small Erlang change | large C++ build (MAME), even with `SOURCES=` subset | GUI toolchain |
| Same simulator as the GCC testsuite | yes | yes (superset) | no | no |

## Recommendation (for the Step 02 gate)

**Option (a): a minimal fork of sim1802**, kept upstream-compatible, adding:

1. an instruction/cycle counter (machine cycles per the [MPM pp. 99–105] table), with
   the total printed on exit when requested (`--cycles`);
2. a **deterministic timer mode**: a new command that sets a period in machine
   cycles and raises IRQ0 from the cycle counter, not from host time. The
   existing 0.1/1/10 Hz modes stay unchanged;
3. **console input**: implement the already-reserved command 0xE1 (GETCHAR) and
   IRQ6 on input, reading host stdin without blocking the CPU loop;
4. (optional) `--max-cycles N` to end runaway tests deterministically.

Rationale: small and local (the I/O file is 323 lines); no licensing
questions; keeps ELF loading, the debugger and exit-status plumbing; could be
offered to mikpe later. MAME would give cycle accuracy and a real 1805 timer,
but it needs a MAME machine driver and a large C++ build for a CPU core that
sim1802 already models adequately. Emma 02's licence is incompatible with the
project's goals.

Fallback if Alan prefers *no* simulator changes: port against the 10 Hz
wall-clock timer, accept non-deterministic timing tests, measure performance
by instruction counts from `-t` traces instead of cycles, and document NSH as
output-only (no interactive prompt).
