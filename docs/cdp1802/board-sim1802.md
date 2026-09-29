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

## 2. Reset

On reset the CPU has I, N, X, P = 0, R(0) = 0, Q = 0, IE = 1 and starts at
M(0x0000) with R(0) as program counter [MPM p. 72, Fig. 86]. The simulator
matches this (`sim1802_core:init/2`), and because a NuttX image's entry point
is 0x0000, the loader installs no bootstrap of its own
(`install_bootstrap(0) -> ok`).

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
        | heap ↓ / stacks           |          | heap / stacks             |
        | (boot args written here   |          | (boot args written here   |
        |  by the loader, unused)   |          |  by the loader, unused)   |
        +---------------------------+          +---------------------------+
        | .bss   (NOLOAD, cleared)  |          | .bss  (NOLOAD, cleared)   |
        +---------------------------+          +---------------------------+
        | .data  (loaded in place,  |          | .data (run address; copied|
        |  LMA = VMA, no copy)      |   0x8000 |  from ROM at start-up)    |
 rom_end+---------------------------+   0x7FFF +===========================+
        | .rodata                   |  RAM ↑   | (unused ROM)              |
        | .text                     |  ROM ↓   | .data initial values(LMA) |
        | .reset (reset code)       |          | .rodata                   |
 0x0000 +---------------------------+          | .text                     |
                                               | .reset (reset code)       |
  write-protected: [0, __sim1802_rom_end)  0x0000 +---------------------------+
  __sim1802_rom_end = end of .rodata        write-protected: [0, 0x8000)
```

| | SIM64 | HW32/32 |
|--|--|--|
| ROM | 0x0000 – end of `.rodata` (grows with the image) | 0x0000 – 0x7FFF (32 KiB) |
| RAM | end of `.rodata` – 0xFFFF | 0x8000 – 0xFFFF (32 KiB) |
| `.data` | loaded in place (LMA = VMA) | LMA in ROM, VMA in RAM, copied by start-up code |
| write protection | `[0, __sim1802_rom_end)` | `[0, 0x8000)` |
| linker-script prototype | `toolchain/tests/board/sim64.ld` | `toolchain/tests/board/hw32.ld` |
| selected by | `CONFIG_BOARD_SIM1802_PROFILE_SIM64` | `CONFIG_BOARD_SIM1802_PROFILE_HW32` (default for size judgements) |

Rules and constraints, each checked by `scripts/test-step-03.sh`:

- **The reset code must be first** in `.text` (`KEEP(*(.reset))`).
- **Loadable bytes must end below 0xFF00:** the simulator's ELF loader rejects
  anything above (`load_phdr/2`: `PAddr + FileSz =< 65536 - 256`). Only
  NOLOAD sections (`.bss`, heap, stacks) may use the top 256 bytes. Both
  linker scripts assert this.
- **Segments are loaded at their physical address** (`p_paddr`), as a ROM
  programmer would (fork commit `1be386b`). That is what makes the HW32/32
  `.data` copy work.
- **Boot arguments:** after loading, the simulator writes a boot-argument
  block (magic 0x1802, argc/argv/envp and a few filtered environment strings:
  HOME, HOSTNAME, USER, …) downwards from 0xFFF8. NuttX ignores it; the area
  becomes stack/heap. Nothing loadable may live there (guaranteed by the
  0xFF00 rule).
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
linker-script prototypes and runs it: reset at 0x0000, `.data` copy from ROM,
`.bss` clear, console output, 5 cycle-timer interrupts through the R0-based
ISR while in `IDL`, halt with status 0. It also checks that a write into ROM
traps.

```
--- hw32: 00000151 A _eronly 00008000 D _sdata 00008000 B __sim1802_rom_end
sim1802 board ok, ticks=5
@ cycles 26109
--- sim64: 00000151 A _eronly 00000151 D _sdata 00000151 T __sim1802_rom_end
sim1802 board ok, ticks=5
@ cycles 26109
```
