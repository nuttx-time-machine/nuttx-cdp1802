# 9. Interrupts

> First tag: `step-07-irq-timer`. ADR 0015; journal `step-07.md`.

## 9.1 What NuttX expects

| Interface | Role |
|-----------|------|
| `up_irq_save()` / `up_irq_restore()` / `up_irq_enable()` | global interrupt enable; every critical section is built on them |
| `up_irqinitialize()` | called by `nx_start()`: install the vector, quiet the controller, and usually enable interrupts |
| `up_enable_irq()` / `up_disable_irq()` | per-source enable at the interrupt controller |
| `g_current_regs` / `up_current_regs()` / `up_interrupt_context()` | non-NULL while a handler runs; points at the interrupted register frame |
| your interrupt entry | save the context, call `irq_dispatch(irq, regs)`, restore a context (maybe another thread's) |

The port **calls** NuttX with `irq_dispatch()`. Drivers register handlers
with `irq_attach()`.

## 9.2 Design the register frame first

The entry saves a frame, and the context switch (chapter 11) resumes one.
Design both with **one frame layout and one restore path**:

- The frame lives on the interrupted thread's stack. `struct xcptcontext`
  holds a *pointer* to it (`xcp.regs`), as in the ARM and RISC-V ports.
  NuttX's assert code uses `running_regs()` = `xcp.regs`.
- After `irq_dispatch()` the dispatcher returns the frame of whatever
  `this_task()` is now, and the exit path restores that. A context switch
  inside an interrupt is then nothing more than returning a different
  pointer.
- Leave out registers that are not per-thread state (e.g. a DMA pointer),
  and ones that can be computed from the frame itself (the stack pointer).

> **CDP1802 example** (`arch/cosmac/include/irq.h`,
> `common/cosmac_irqentry.S`, `common/cosmac_doirq.c`):
> - The frame is 31 bytes: T (X,P), D, DF, IE, R3–R15 and the sim1802 I/O
>   buffer. R0 belongs to DMA, R1 is the interrupt PC, and R2 = frame + 31.
> - The exit ends with `RET` placed immediately before the entry, so R1
>   points at the entry again. A frame resumed with interrupts disabled ends
>   with `DIS` followed by `lbr entry`.
> - **Pitfall met:** an interrupt can arrive while P=4 or P=5, inside the
>   NCRT call/return routines. R4/R5 then point into the middle of them, so
>   the entry must reload them before calling C (they are in the frame).

## 9.3 Reading the interrupt state

`up_irq_save()` must return the *previous* state and disable. Use the
hardware state if the CPU exposes it in any way; most NuttX ports do.
Keep a software copy only if you must, and then list every point that
changes the hardware flag. Each of them must also update the copy.

> **CDP1802 example:** IE has no "load" instruction, but `LSIE` (long skip
> if IE=1) reads it. It is the default. The Kconfig option
> `COSMAC_IRQSTATE_SWFLAG` keeps a RAM copy instead (Alan's Step 02
> decision). ADR 0015 lists its four update points; the rule is "change the
> copy only while IE=0". Both variants pass the Step 07 test.

## 9.4 Measure the cost

Count the entry and exit in cycles from an instruction trace, and the
whole path of your most frequent interrupt, the tick. It decides the tick
rate (chapter 10) and the minimum stack of every thread.

> **CDP1802 example:** entry 175 + exit 119 = 294 machine cycles; the C
> dispatch path adds about 550. `scripts/trace-profile.py` turns a sim1802
> trace into cycles per function.

## Checklist

- [ ] The frame layout is written down byte by byte, and one restore path
      serves both interrupt return and the thread-level switch.
- [ ] `up_irq_save()` is race-free: think about an interrupt arriving
      between reading the state and disabling.
- [ ] Every register the interrupted code may be using is saved, including
      "fixed" ones such as call-helper registers.
- [ ] Handlers run with enough stack: measure the peak.
- [ ] Entry/exit cycles are measured and recorded.

## Common pitfalls

- Registers that are constant for C code but not at every instruction
  (R4/R5 on the 1802).
- A controller that masks a source on acknowledge: re-arm it after the
  handler, or the second interrupt never comes.
- Interrupt handlers deeper than the smallest thread stack.
- An address-based static checker on banked images: decode each function
  from its own section (Step 07 fixed `check-sp-safety.py`).
