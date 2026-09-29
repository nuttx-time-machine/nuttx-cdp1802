# The CDP1802 for NuttX developers

A short primer: just enough of the RCA CDP1802 (COSMAC, 1976) to read the
port's code. References: **[MPM]** RCA MPM-201A *User Manual for the CDP1802
COSMAC Microprocessor* (printed page numbers); **[DS1805]** Intersil
CDP1805AC/1806AC datasheet. The C ABI is in [abi.md](abi.md), the virtual
board in [board-sim1802.md](board-sim1802.md).

## Registers

| Register | Width | Role |
|----------|-------|------|
| R0–RF | 16 bits each | general "scratch-pad" registers; any of them can be the program counter or the memory pointer [MPM p. 9] |
| P | 4 bits | *which* R register is the program counter |
| X | 4 bits | *which* R register is the data pointer for memory-operand instructions |
| D | 8 bits | the only accumulator: all arithmetic and logic goes through D |
| DF | 1 bit | carry/borrow flag |
| T | 8 bits | holds X,P after an interrupt [MPM p. 40] |
| IE | 1 bit | interrupt enable; tested with `LSIE` [MPM p. 38], set/cleared by `RET`/`DIS` |
| Q | 1 bit | an output flip-flop (not used by the sim1802 board) |

There is **no stack pointer and no call instruction** in the 1802: both are
software conventions. "Jumping" to a subroutine can be done by changing P
(`SEP n`): the new register already points at the subroutine
[MPM pp. 54–64].

## Instructions in one paragraph

One-byte opcodes, high nibble = operation, low nibble = register N. Memory is
reached through registers only: `LDN n`/`LDA n` (load via R(n), with
advance), `STR n`, `LDX`/`LDXA`/`STXD` (via R(X), with advance/decrement),
`GLO/GHI/PLO/PHI n` (move bytes between D and R(n)), `INC/DEC n` (16-bit,
atomic), `ADD/ADC/SD/SM…` (D op M(R(X))), immediate forms (`ADI`, `LDI`, …),
short branches (2 bytes, **within the same 256-byte page**) and long branches
and skips (3 bytes) [MPM pp. 99–105]. Every instruction takes 2 machine cycles
(3 for long branches, long skips and NOP), and a machine cycle is 8 clock
periods [MPM p. 8, p. 70]. There is **no base+offset addressing** and no
16-bit arithmetic, which is why C code is large (journal step-04).

## Reset and interrupts

- **Reset:** I, N, X, P = 0, R0 = 0, Q = 0, IE = 1; execution starts at
  M(0x0000) with R0 as PC [MPM p. 72]. Start-up code switches the PC to R3
  (`SEP 3`); R0 is then left for DMA (ADR 0006).
- **Interrupt** (INTERRUPT line low and IE = 1): T ← X,P; P ← 1; X ← 2;
  IE ← 0 [MPM p. 40]. So **R1 is the interrupt handler's PC** and the handler
  must be able to push through **R2**, the stack pointer by convention
  [MPM pp. 64–65, Fig. 76]. `RET` restores X,P from memory and sets IE;
  `DIS` does the same but clears IE.
- Interrupts are sampled between instructions only, so any single
  instruction is atomic. A 16-bit register **cannot** be written in one
  instruction (two byte writes), which is why stack-pointer updates needed a
  compiler fix (toolchain issue 0001, ADR 0007).
- **DMA** uses R0 as its pointer and steals cycles between instructions
  [MPM p. 9, p. 54]. Real machines use it for video and memory refresh
  ([real-machines.md](real-machines.md)).

## I/O

`OUT n` (n = 1–7) puts M(R(X)) on the bus and increments R(X); `INP n` reads
a byte into both D and M(R(X)). The three N lines select the device. Four
flag inputs EF1–EF4 can be tested by branch instructions. The sim1802 board
uses only `OUT/INP 6` (argument buffer) and `OUT 7` (command).

## The CDP1804/1805/1806 extensions

The 1804AC-family CPUs add 68-prefixed instructions: 16-bit register load and
store (`RLDI`, `RLXA`, `RSXD`, `RNX`), `SCAL`/`SRET` (call/return),
`DBNZ`, BCD arithmetic, and (1805/1806) an 8-bit counter/timer that can
interrupt [DS1805 pp. 12–13]. mikpe's GCC can use the register instructions
(`-march=1804`, about 4 % smaller code); sim1802 implements those but not the
counter/timer.

## What this means for a NuttX port

- A context is 15 × 16-bit registers plus D, DF, T, IE and X/P: about 35
  bytes, saved one byte at a time (Step 08 measures the cost).
- Every C call goes through the NCRT routines at R4/R5 ([abi.md](abi.md)),
  which is also what makes transparent code banking possible (ADR 0013).
- Interrupt-state save/restore needs no software flag (`LSIE`), but changing
  IE takes `DIS`/`RET` with an inline X,P byte.
