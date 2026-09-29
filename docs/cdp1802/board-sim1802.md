# The `sim1802` virtual board

`sim1802` is the first NuttX board for the CDP1802. It is *virtual*: the
hardware is whatever the simulator (the `cdp1802-nuttx` fork of mikpe's
sim1802, [sim1802-fork.md](sim1802-fork.md)) provides. It is defined to look
like a plausible real COSMAC board (reset from ROM at 0x0000, RAM above), so
that the arch/chip layers stay valid for real hardware and only the board
layer is simulator-specific. Decision record: [ADR 0005](../adr/0005-sim1802-board.md).

NuttX paths (ADR 0001): `boards/cosmac/cdp1802/sim1802/`, `CONFIG_ARCH_BOARD_SIM1802`.

References: **[MPM]** RCA MPM-201A (printed pages); **[DS1805]** Intersil
CDP1805AC/1806AC datasheet, March 1997.

## 1. CPU and clock

| Item | Value | Source |
|------|-------|--------|
| CPU | CDP1802 instruction set (`-march=1802`); the 1804AC register ops also run on the fork but are not used by default | ADR 0002, sim1802 audit |
| Clock | **nominal 4 MHz**, `CONFIG_BOARD_SIM1802_CLOCK_HZ` | a 4-MHz clock is MPM's own example [MPM p. 68]; CDP1805AC maximum clock input frequency is 5 MHz at 5 V [DS1805 p. 4] |
| Machine cycle | 8 clock periods = **2 µs** at 4 MHz | [MPM p. 70] |
| Instruction | 2 machine cycles (3 for long branch/skip/NOP) = 4–6 µs | [MPM p. 8] |

The simulator has no clock: the nominal clock only converts time
(`CONFIG_USEC_PER_TICK`) into machine cycles for the timer, and cycles into
time for measurements. With `--pace HZ` the simulator slows idle periods to
match.

## 2. The ROM image and reset — exactly like the real machine

**The artefact is the ROM binary.** A NuttX build for this board produces
`nuttx.elf` and, with `objcopy -O binary`, `nuttx.bin`: the exact bytes to
program into an EPROM at address 0x0000. The simulator boots *that file*
(`sim1802 --rom nuttx.bin`, fork commit `f41d9eb`), not the ELF, so what runs
in the simulator is what would run on hardware:

| At power-on | Real CDP1802 board | `sim1802 --rom` |
|-------------|--------------------|-----------------|
| ROM 0x0000.. | the programmed bytes | the `.bin` file |
| unprogrammed ROM | 0xFF (erased EPROM) | 0xFF up to `--rom-size` |
| RAM | undefined | pseudo-random (`--ram-seed`, default 1802; reproducible) |
| I, N, X, P, R(0), Q, IE | 0, 0, 0, 0, 0x0000, 0, 1 [MPM p. 72, Fig. 86] | same |
| R(1)–R(15), D, DF, T | undefined | pseudo-random (same seed) |
| before the first instruction | nothing | nothing (no bootstrap, no boot arguments) |
| write to ROM | no effect | ignored (`--rom-writes warn\|trap` to debug) |
| console bytes | 8-bit | 8-bit clean (fork commit `a3d1933`) |

`scripts/run.sh <elf>` does this automatically for any image that defines
`__sim1802_rom_end`: it writes `<elf>.bin`, and runs
`sim1802 --rom <elf>.bin --rom-size <__sim1802_rom_end> --symbols <elf>`
(the ELF is only used for symbol names in traces). `RUN_MODE=elf` forces the
old ELF-loader path, which the Step 01/02 validation programs still use.

Because RAM and most registers are *not* zero, start-up code that forgets to
copy `.data`, clear `.bss` or initialise a register fails in the simulator
just as it would on the board (tested: the smoke program without its `.data`
copy prints garbage that changes with `--ram-seed`).

The board's first instructions (Step 06; shown working in
`toolchain/tests/board/smoke.S`):

```
0x0000  DIS ; .byte 0x00     IE := 0, X := 0, P := 0 (inline byte via R(X)=R0)
        load R3 := __start_c ; SEP 3     PC := R3 — R0 is now free (no DMA)
        R2 := initial SP, SEX 2, copy .data, clear .bss, set R4/R5 (NCRT) ...
```

## 3. Memory map

Two profiles share one layout rule: **read-only image from 0x0000 up,
read/write memory above it**. The size budget (docs/size-budget.md) reports
both.

```
            SIM64 (development)                 HW32/32 (feasibility target)
 0xFFFF +---------------------------+   0xFFFF +---------------------------+
        | heap / stacks             |          | heap / stacks             |
        +---------------------------+          +---------------------------+
        | .bss   (cleared at boot)  |          | .bss  (cleared at boot)   |
        +---------------------------+          +---------------------------+
        | .data  (copied from ROM   |          | .data (copied from ROM    |
        |  at boot)                 |   0x8000 |  at boot)                 |
 rom_end+===========================+   0x7FFF +===========================+
        | .data initial values      |  RAM ↑   | (unprogrammed: 0xFF)      |
        | .rodata                   |  ROM ↓   | .data initial values      |
        | .text                     |          | .rodata                   |
        | .reset (reset code)       |          | .text                     |
 0x0000 +---------------------------+   0x0000 | .reset (reset code)       |
                                               +---------------------------+
  ROM = [0, __sim1802_rom_end = _sdata)     ROM = [0, 0x8000)
  nuttx.bin = the whole ROM image           nuttx.bin = ROM image (≤ 32 KiB)
```

| | SIM64 | HW32/32 |
|--|--|--|
| ROM | 0x0000 – end of the ROM image (exactly as big as needed) | 0x0000 – 0x7FFF (32 KiB) |
| RAM | end of ROM image – 0xFFFF | 0x8000 – 0xFFFF (32 KiB) |
| `.data` | LMA in ROM (after `.rodata`), VMA in RAM, copied by start-up code | same |
| `__sim1802_rom_end` (= `--rom-size`) | `_sdata`, the first RAM byte | 0x8000 |
| linker-script prototype | `toolchain/tests/board/sim64.ld` | `toolchain/tests/board/hw32.ld` |
| selected by | `CONFIG_BOARD_SIM1802_PROFILE_SIM64` | `CONFIG_BOARD_SIM1802_PROFILE_HW32` (default for size judgements) |

Rules and constraints, each checked by `scripts/test-step-03.sh`:

- **The reset code must be first** in `.text` (`KEEP(*(.reset))`).
- **The ROM image must fit the ROM**: HW32/32 asserts it in the linker script
  (`HW32/32: ROM overflow`); in SIM64 ROM + RAM must fit in 64 KiB (`will not
  fit in region 'mem'`).
- **ELF-loader mode only** (`RUN_MODE=elf`, validation programs): the loader
  places segments at their physical address `p_paddr` (fork commit
  `1be386b`, so the ELF path agrees with the ROM path), rejects loadable
  bytes above 0xFF00, and writes a boot-argument block (magic 0x1802,
  argc/argv/envp, a few environment strings) down from 0xFFF8. None of this
  exists in ROM mode or on hardware; NuttX never relies on it.
- **Stacks:** the idle-thread stack follows `.bss`, the heap runs from the end
  of the idle stack to 0xFFFF (standard NuttX pattern, Step 05). SP points one
  byte *below* the last pushed byte (ABI), so the highest usable stack byte of
  an empty stack at `top` is `top` itself with SP = `top`.

## 4. I/O devices

All devices are behind the simulator's I/O controller on **two ports**:
`OUT 6`/`INP 6` = 8-bit argument/result buffer, `OUT 7` = command. The CPU's
other I/O lines (N = 1–5), EF1–EF4 and Q are not connected. There is **no DMA**,
so R0 is free after reset (used by the interrupt entry, toolchain issue 0001).

| Device | Commands (`OUT 7`) | IRQ | NuttX user |
|--------|--------------------|-----|-----------|
| Interrupt controller | 0x10 ACK (→ buffer: lowest pending+enabled IRQ, 8 = spurious; **clears that IRQ's enable bit**), 0x11/0x12 read enabled/pending, 0x13/0x14 write enabled/pending | — | `up_enable_irq`/`up_disable_irq`, IRQ dispatch (Step 07) |
| Timer | 0x81–0x83 period (24 bits, machine cycles), 0x80 control: **4 = periodic, cycle-driven** (0–3: upstream wall-clock modes, not used) | 0 | system tick `up_timer_initialize` (Step 07) |
| Cycle counter | 0x84 latch, 0x85–0x88 read bytes 0–3 | — | `up_perf_*`, measurements (Steps 07–08) |
| Console | 0xE0 PUTCHAR (buffer → stdout), 0xE1 GETCHAR, 0xE2 STATUS (bit 0 data, bit 1 EOF) | 6, level-triggered | `up_putc`/lowputc (Step 06), serial driver (Step 09) |
| Halt | 0x00 HALT: exit the simulator with the buffer as status | — | `board_power_off()`, test exit codes |

Exit statuses reserved by the simulator: 1 (invalid opcode), 96
(`--max-cycles` reached), 97 (trap: write to ROM, IDL with IE=0, …), 98
(`NYI` pseudo-op). Test programs use 0 for success.

**Tick period.** At 4 MHz, `CONFIG_USEC_PER_TICK = 10000` (10 ms) is 5 000
machine cycles per tick. The default tick is decided in Step 07 from the
measured interrupt cost (a tick that takes a large share of 5 000 cycles
would argue for a longer period); the period register allows up to
16 777 215 cycles (33.5 s at 4 MHz).

## 5. What a real board would change

Only `boards/cosmac/cdp1802/sim1802/` should know about the simulator's I/O
controller. A real board would supply a UART (e.g. a CDP1854 on the N lines),
a tick source (e.g. the CDP1805/1806 on-chip timer [DS1805 pp. 12–13] or an
external one on the INT line), its own memory decoding, and possibly DMA
(which conflicts with the R0-based interrupt entry, see toolchain issue 0001).

## 6. Verification

`scripts/test-step-03.sh` links `toolchain/tests/board/smoke.S` with both
linker-script prototypes, converts each to its raw ROM binary and boots it
with `--rom`: reset at 0x0000, `.data` copy from ROM, `.bss` clear, console
output, 5 cycle-timer interrupts through the R0-based ISR while in `IDL`,
halt with status 0. It also checks that the binary starts with the reset
code, that the ELF-loader run gives the same output, that a build *without*
the `.data` copy fails (undefined RAM), and that ROM writes are ignored or
trapped as selected.

```
ok: hw32 boots from its 342-byte ROM image (@ cycles 26109)
ok: hw32 RAM is undefined at power-on (missing .data copy is caught)
ok: hw32 ROM write ignored (default) / trapped (--rom-writes trap)
ok: sim64 boots from its 342-byte ROM image (@ cycles 26109)
ok: sim64 RAM is undefined at power-on (missing .data copy is caught)
ok: sim64 ROM write ignored (default) / trapped (--rom-writes trap)
ok: linker scripts reject oversized images
PASS: step 03
```
