# 0006 — Register convention: R0 free for DMA, R1 interrupt PC, R2 always a valid stack, R3 PC

Status: **Accepted** (Alan, 2026-09-29)
Date: 2026-09-29
Step: step-03
Supersedes: the R0-based interrupt entry planned in toolchain issue 0001 and
accepted conditionally at the Step 02 gate (journal step-02, Q3).

## Context

Alan's requirement (2026-09-29): keep compatibility with the established
COSMAC convention:

- **R1** is the interrupt handler's program counter: on an interrupt the
  CPU sets P=1 and X=2 [MPM p. 40, Fig. 61] (hardware-mandated).
- **R2** is the stack pointer. Because the hardware forces X=2, any
  standard interrupt routine expects R2 to point to a valid stack for
  saving the context [MPM pp. 64–65, Fig. 76].
- **R3** is the main program counter: after reset R0 is the PC at 0x0000
  [MPM p. 72]; the start-up code loads R3 and executes `SEP 3`, which frees
  R0 for DMA [MPM p. 54: "R(0) Initial program counter … Later, DMA pointer"].

This matches mikpe's ABI (`cdp1802-abi.txt`: r0 fixed "DMA and PC at boot",
r1 fixed "interrupt handler PC", r2 fixed "SP", r3 fixed "PC by software
convention") and is required on real machines, which use DMA through R0 for
video or memory refresh (COMX-35, Pecom, Elf II; `real-machines.md`).

The earlier plan used R0 as the interrupt routine's private save pointer to
avoid toolchain issue 0001 (GCC's two-step SP updates can leave R2 256 bytes
too high for a few instructions). That breaks the convention and cannot work
on any machine that uses DMA.

## Options considered

1. R0-based interrupt entry (previous plan). Rejected: breaks the convention
   and DMA.
2. The standard R2-stack interrupt entry, with the guarantee that R2 is a valid
   stack at every instruction boundary provided by the toolchain.

## Decision

Option 2. NuttX on the CDP1802:

- never uses R0 after the reset code's `SEP 3` (R0 belongs to DMA);
- loads R1 with the interrupt entry before enabling interrupts; the entry is
  the MPM Fig. 76 form: `DEC 2; SAV; DEC 2; STR 2 …`, exit `… LDA 2; RET`;
- keeps R2 a valid stack pointer at all times (the ISR's first `DEC 2`
  protects the scratch byte M(R2) that compiled code uses);
- runs all C code with P=3 (R3 = PC), X=2.

The board smoke test (`toolchain/tests/board/smoke.S`) already follows this
convention (commit with this ADR) and never touches R0 after reset.

## Consequences

- **Toolchain issue 0001 becomes a prerequisite of Step 07** (interrupts): the
  compiler must not leave R2 above the live stack top between two
  instructions. Options (GCC patch, which needs Alan's approval under
  CONTRACT §5.9; a build-time rewrite of the generated assembly plus a
  verifier; or waiting for mikpe) are listed in the issue. Steps 04–06 do not
  enable interrupts and are not blocked.
- The `LSIE` irq-state default and the software-flag option (Step 02 Q4) are
  unaffected.
- Every ISR costs a few more bytes of R2 stack per thread (T, D, DF and the
  saved registers), which the context-switch design (Step 08) accounts for.

## How to revisit

Only if a board cannot provide a valid R2 at interrupt time; there is no
known reason to.
