# 0015 — Interrupts: IE state (LSIE, optional RAM copy), one register frame, one restore path

Status: Proposed (agent). The IE part implements Alan's Step 02 decision (Q4).
Date: 2026-09-29
Step: step-07

## Context

The contract (Step 07, hypothesis H3) assumed that IE cannot be read back
and asked for a "shadow-IE" `up_irq_save/restore` with an ADR explaining
the technique. Step 02 found that H3 is false: `LSIE` (long skip if IE=1)
reads IE (journal step-02, Q4). Alan decided: "use LSIE by default, but add
the option to use software interrupt-enable flag. That option should be
later selected on NuttX Kconfig."

The interrupt entry and the context switch (Step 08) must also agree on a
register frame, and the 1802 has two further constraints:

- a thread may be interrupted while P=4 or P=5 (inside NCRT);
- after the handler, R1 must point at the entry again, and `DIS`/`RET` are
  the only instructions that can restore X,P.

## Decision

**IE state** (Kconfig choice in `arch/cosmac/Kconfig`, `cosmac_irqsave.S`):

- `COSMAC_IRQSTATE_LSIE` (default): `up_irq_save` reads IE with `LSIE`,
  then `DIS` with the inline byte 0x23 (X=2, P=3). `up_irq_restore` uses
  `RET` or `DIS`. There is no RAM state. If an interrupt arrives between
  `LSIE` and `DIS`, the handler returns with `RET` (IE=1), so the value read
  is still true.
- `COSMAC_IRQSTATE_SWFLAG`: a RAM copy `g_cosmac_ie` (0/1) is kept equal to
  IE at every point where C code can observe it. The update points are:
  1. `up_irq_save`: `DIS` first, then read the copy and set it to 0;
  2. `up_irq_restore` / `up_irq_enable`: `DIS`, write the copy, then `RET`
     if it is 1. The copy never changes while IE=1, so an interrupt cannot
     see it half updated;
  3. interrupt entry: copy := 0 (the hardware cleared IE);
  4. interrupt exit / context switch: copy := the IE byte of the frame
     being resumed, just before `RET` (1) or `DIS` (0).

  The far-call trampolines (ADR 0013) disable interrupts and restore IE
  without touching the copy. No C code or interrupt runs in between, so the
  copy is never observed stale. They read IE with `LSIE` in both modes.

**Register frame** (31 bytes, `arch/cosmac/include/irq.h`,
`docs/cdp1802/context.md` in Step 08). It is pushed below the interrupted
stack pointer E, leaving M(E) (the thread's free byte) alone. Contents:
T (X,P), D, DF, IE, R3..R15, and the sim1802 I/O argument buffer.

- R0 (DMA) and R1 (interrupt PC) are not per-thread state.
- R2 is implied: E = frame + 31.
- `struct xcptcontext` holds only a pointer to the frame on the thread's
  own stack (the pointer model of the ARM/RISC-V ports, which the common
  assert code's `running_regs()` expects). There is no copy into the TCB.

**Entry** (`cosmac_irqentry.S`, P=1):
1. push the frame;
2. reload R4/R5 with the NCRT entries (their interrupted values are in the
   frame);
3. call `cosmac_doirq(frame)` with R3 as the PC;
4. `cosmac_doirq` acknowledges the source at the board's controller,
   dispatches it, re-arms the controller, and returns the frame to resume
   (another thread's after a switch).

**One restore path** for interrupts and (Step 08) thread-level switches.
R2 := frame; pop everything in address order; then `RET` if the frame's IE
is 1, else `DIS`. The `RET` sits immediately before the entry, so R1 is
left at the entry. The `DIS` is followed by `lbr cosmac_irq_entry`, so the
next interrupt, whenever it comes, reaches the entry through R1.

**Interrupt controller in the board** (layering, ADR 0001):
`cosmac_irq_initialize/acknowledge/rearm` and `up_enable/disable_irq` are
in `boards/.../sim1802_irq.c`. The sim1802 controller clears a source's
enable bit on acknowledge, so the board rewrites its enable mask after each
handler.

## Consequences

- Entry + exit cost **294 machine cycles** (entry 175, exit 119, from an
  instruction trace), plus 1 cycle of interrupt response. The C dispatch
  path (`cosmac_doirq` 284, acknowledge 83, re-arm 27, and their NCRT
  calls) adds about 550 more. A whole tick costs about 3 400 (ADR 0016).
- SWFLAG costs 32–43 cycles more per tick (3 439–3 450 against 3 407
  measured) and 1 byte of RAM.
- No nested interrupts; the handler runs on the interrupted thread's stack.
  Every stack needs room for a frame plus the deepest handler: the idle
  stack peaked at 684–696 bytes with `syslog` output (ADR 0016).
- The composite R2 update in the entry (switch to the frame to resume)
  runs with IE=0 and is exempted in `check-sp-safety.py` by name
  (`scripts/build.sh`).

## How to revisit

An interrupt stack (`CONFIG_ARCH_INTERRUPTSTACK`) would take the handler
depth off every thread's stack, at the cost of an R2 switch in the entry.
If a CDP1802 variant or emulator lacks `LSIE`, the trampolines would also
have to use the RAM copy.
