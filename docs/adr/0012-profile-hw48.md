# 0012 — Memory profile HW48/16 (48 KiB ROM, 16 KiB RAM)

Status: Accepted (Alan requested it at the Step 04 gate, 2026-09-29)
Date: 2026-09-29
Step: step-04 follow-up

## Context

HW32/32 is 2.3× too small for the minimal kernel. RAM use is modest (static
544 bytes plus heap and stacks), so trading RAM for ROM is the obvious lever.

## Decision

Add `CONFIG_BOARD_SIM1802_PROFILE_HW48`, linker script `hw48.ld`: ROM
0x0000–0xBFFF, RAM 0xC000–0xFFFF, `.data` copied from ROM, whole ROM
write-protected, `__sim1802_rom_end = 0xC000`.

## Consequences

- Measured: the minimal kernel with 32-bit time overflows it by 12 828 bytes
  (61 978 > 49 152). Flat HW48/16 therefore needs either a fixed compiler
  (issue 0002 workaround: 13 KB) or banking.
- The same address split is the basis of the banked profile HWB (ADR 0013),
  where 0x8000–0xBFFF becomes the bank window.
- 16 KiB of RAM must hold static data, the heap, all stacks (with the 256-byte
  interrupt guard band each) and the per-thread bank return stacks. It is
  checked in Step 08.

## How to revisit

Re-measure whenever the compiler or NuttX changes: this profile is the most
likely one to become feasible without banking.
