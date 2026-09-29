# Real CDP1802 machines vs the sim1802 board

Alan asked (2026-09-29) whether the ROM-at-0 layout booted from the raw ROM
binary (ADR 0005) would work on real hardware such as the **PECOM 64**, the
**COSMAC Elf** and the **COMX-35**. This page records what was checked and
the answer. Hardware facts come from MAME's machine drivers (BSD-3-Clause)
at commit `184fb77c08ac` of `mamedev/mame`, which are emulations, not
schematics: **verify against the machines' technical documentation before
building anything.**

- COMX-35: `src/mame/comx/comx35.cpp`
- Pecom 32/64: `src/mame/sfrj/pecom.cpp`
- Netronics Elf II (a COSMAC Elf derivative): `src/mame/netronics/elf.cpp`

## Facts

| | COMX-35 | Pecom 32/64 | Elf II |
|---|---|---|---|
| ROM | 0x0000–0x3FFF, 16 KiB (`mem_r`: `offset < 0x4000` → ROM) | 0x8000–0xEFFF, plus 0xF000–0xFFFF when video is not mapped (`mem_map`) | none |
| RAM | 0x4000–0xBFFF, 32 KiB (`mem_r`/`mem_w`) | 0x0000–0x7FFF, 32 KiB | 256 bytes (`RAM(...).set_default_size("256")`, `global_mask(0xff)`) |
| Video / other memory | char RAM 0xF400–0xF7FF, page RAM 0xF800– (CDP1869/1870) | 0xF000–0xFFFF shared with the CDP1869 after `OUT 1` with data 2 | CDP1861 fetches pixels by DMA |
| Reset / boot | CPU starts at 0 → ROM | ROM's first 16 KiB is shadowed at 0x0000–0x3FFF for reads (`machine_reset`: `bank1` → ROM); `OUT 1` (`bank_w`) switches RAM back in | LOAD mode: bytes entered by DMA-IN into RAM; RUN from 0 |
| DMA (uses R0) | DMA-OUT on every other S1 cycle once interrupts/DMA are enabled (`sc_w`, "memory refresh DMA"); enabled by the first `SEQ` (`q_w`: `m_iden = 0`), after which the display interrupt (PRD) is also active | DMA-OUT on every other PRD from the video chip (`prd_w`, "memory refresh DMA") | CDP1861 DMA-OUT while the display is on |

## Answer

**The same `nuttx.bin` built for the sim1802 board will not boot on any of
these three machines**, and the sim1802 board does not claim to model them.
The reasons are per machine:

1. **Memory map.** HW32/32 assumes 32 KiB ROM at 0x0000 and 32 KiB RAM at
   0x8000. COMX-35 has 16 KiB ROM at 0 and RAM at 0x4000–0xBFFF. The Pecom has
   RAM at 0 and ROM at 0x8000 (reached at reset through a shadow). The Elf II
   has 256 bytes of RAM and no ROM, which is far too small for NuttX without
   a memory expansion.
2. **DMA on R0.** All three machines use DMA for video and/or memory refresh
   once it is enabled, and DMA uses R0 as its pointer. The interrupt entry
   planned for sim1802 uses R0 as its save pointer (toolchain issue 0001),
   which is **not usable while DMA is active**. On these machines NuttX needs
   the R2-based interrupt entry, and that is only safe with a compiler whose
   stack-pointer updates are interrupt-safe (the fix proposed in the draft
   report to mikpe).
3. **Devices.** Console, tick and halt on sim1802 are the simulator's I/O
   controller on ports 6/7. The real machines have a keyboard, video (CDP1861
   or CDP1869/1870), cassette and machine-specific expansion I/O instead; the
   natural tick on COMX-35/Pecom is the video frame interrupt, which only
   exists while DMA is running.

**What does carry over unchanged** is everything above the board layer:
`arch/cosmac` (start-up structure, NCRT, interrupt dispatch, the `LSIE`
irq-state code, context switching) and the ROM-at-reset boot principle
itself. COMX-35 in particular boots from ROM at 0x0000 exactly like the
sim1802 board, only with a smaller ROM. Each real machine needs its own
board directory (e.g. `boards/cosmac/cdp1802/comx35/`) with its own linker
script, start-up memory setup (for the Pecom: run the first instructions from
the shadow, jump to the ROM's real address, then `OUT 1`), drivers and
interrupt-entry variant.

## What would make a real-machine claim testable

MAME emulates COMX-35, Pecom 32/64 and the Elf II. A later step (outside the
current contract; real hardware is out of scope, §10) could build a NuttX
board for one of them and run its ROM image in MAME. That would exercise
the real memory map, reset behaviour and DMA, which sim1802 does not model.
Recommended first target: COMX-35 (ROM at 0 like sim1802; 32 KiB RAM), if
NuttX can fit its 16 KiB ROM, which Step 04 will show. If it cannot, banked
expansion ROMs would be needed.
