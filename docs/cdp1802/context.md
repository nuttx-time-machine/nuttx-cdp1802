# The CDP1802 thread context (register frame)

Defined at Step 07 (ADR 0015) and completed at Step 08 (ADR 0017).
Sources:
- `arch/cosmac/include/irq.h`: the `REG_*` offsets;
- `common/cosmac_irqentry.S`: interrupt entry and exit;
- `common/cosmac_doswitch.S`: thread-level switch, full restore, signal
  return;
- `common/cosmac_initialstate.c`: a new thread's first frame.

## What a thread's context is

| Part | Where it lives while the thread is not running |
|------|-----------------------------------------------|
| T (X,P), D, DF, IE, R3–R15, sim1802 I/O buffer | the **register frame**, 31 bytes on the thread's own stack; `tcb->xcp.regs` points at it |
| R2 (stack pointer) | implied: `xcp.regs + 31` |
| bank state (HWB): BRS pointer, free BRS entries, bank | `tcb->xcp.bankstate[4]` (copied to and from `g_cosmac_bankstate` by `cosmac_bank_switch`) |
| bank return stack | `tcb->xcp.brs[3 × CONFIG_COSMAC_BRS_DEPTH]` (idle thread: `g_cosmac_idle_brs`) |
| original frame during signal delivery | `tcb->xcp.sigregs[31]`; its place on the stack in `tcb->xcp.saved_regs` |

Not part of any thread's context:
- **R0**: the DMA pointer, shared and changed by hardware (ADR 0006).
- **R1**: the interrupt PC. It always points at `cosmac_irq_entry`, or at
  the `lbr cosmac_irq_entry` that follows the exit path's `DIS`.
- **Q**: not used by the port.

## The frame, byte by byte

E is the thread's stack pointer when the frame was made: the interrupted
SP, or the SP inside `cosmac_switchcontext()`. M(E) is the thread's free
byte (ABI: SP points one byte below the last pushed byte) and is not
touched. The frame occupies E−31 … E−1, and `xcp.regs` = E−31. Registers
are stored high byte first (big-endian), like every 16-bit value on this
target.

```
 address   offset  REG_ name       contents
 -------   ------  ------------    ---------------------------------------
 E+1 ...           (live stack)    the thread's data (return addresses...)
 E                                 free byte of the thread (not saved)
 E-1       30      REG_XP          T: X (high nibble) and P (low nibble)
 E-2       29      REG_D           D
 E-3       28      REG_DF          DF in bit 0
 E-4       27      REG_IE          1: resume with RET (IE=1), 0: with DIS
 E-5       26      REG_R(3)+1      R3 low     (REG_PCL)
 E-6       25      REG_R(3)        R3 high    (REG_PCH)
 E-7       24      REG_R(4)+1      R4 low
 E-8       23      REG_R(4)        R4 high
 E-9       22      REG_R(5)+1      R5 low
 E-10      21      REG_R(5)        R5 high
 E-11      20      REG_R(6)+1      R6 low
 E-12      19      REG_R(6)        R6 high
 E-13      18      REG_R(7)+1      R7 low
 E-14      17      REG_R(7)        R7 high
 E-15      16      REG_R(8)+1      R8 low
 E-16      15      REG_R(8)        R8 high
 E-17      14      REG_R(9)+1      R9 low
 E-18      13      REG_R(9)        R9 high
 E-19      12      REG_R(10)+1     R10 low
 E-20      11      REG_R(10)       R10 high
 E-21      10      REG_R(11)+1     R11 low
 E-22       9      REG_R(11)       R11 high
 E-23       8      REG_R(12)+1     R12 low
 E-24       7      REG_R(12)       R12 high
 E-25       6      REG_R(13)+1     R13 low
 E-26       5      REG_R(13)       R13 high
 E-27       4      REG_R(14)+1     R14 low
 E-28       3      REG_R(14)       R14 high
 E-29       2      REG_R(15)+1     R15 low
 E-30       1      REG_R(15)       R15 high
 E-31       0      REG_BUF         sim1802 I/O argument buffer    <- xcp.regs
 E-32                              free byte below the frame (SP while
                                   the interrupt handler runs C code)
```

`REG_R(n) = 1 + 2 × (15 − n)` for n = 3 … 15. `XCPTCONTEXT_SIZE` = 31.

## How frames are made and consumed

| Event | Makes the frame | Frame's IE | Resumes a frame |
|-------|-----------------|:----------:|-----------------|
| interrupt | `cosmac_irq_entry`: `dec 2; sav`, then `stxd` down to the buffer (`inp 6`) | 1 | `cosmac_doirq()` returns the frame of `this_task()`; `cosmac_irq_exit` pops it |
| thread-level switch (`up_switch_context`) | `cosmac_switchcontext()`: T = 0x23 (X=2, P=3); R3 = `.Lresume`, a `sep 5` that returns from the call; IE from LSIE or `g_cosmac_ie` (normally 0: the scheduler switches inside a critical section) | normally 0 | `cosmac_fullcontextrestore()` → `cosmac_irq_exit` with P=1 |
| new thread (`up_initial_state`) | at the top of the new stack: T = 0x23, IE = 1, R3 = `tcb->start`, R4/R5 = NCRT entries, the rest 0. Above it, at top−2 … top−1, the return address `cosmac_thread_return` (PANIC); E = top−3 | 1 | the first switch to the thread |
| task exit (`up_exit`) | — | — | `cosmac_fullcontextrestore(this_task()->xcp.regs)` |
| signal (`up_schedule_sigaction`) | the frame is **redirected in place**: its 31 bytes are copied to `xcp.sigregs`, then T = 0x23, IE = 0, R3 = `cosmac_sigdeliver`, R4/R5 = NCRT entries | 0 | `cosmac_sigdeliver()` runs the handlers; `cosmac_sigreturn()` copies `xcp.sigregs` back over E−31 … E−1 (IE = 0, registers only) and resumes it |

The exit path (`cosmac_irq_exit`) runs with P=1 and X=2:
1. `out 6` restores the I/O buffer.
2. `lda 2` pops R15 … R3 in address order.
3. It pops IE, then DF (`lda 2; shr`) and D.
4. It ends with `RET` (IE := 1), placed immediately before
   `cosmac_irq_entry`, or with `DIS` (IE := 0) followed by
   `lbr cosmac_irq_entry`. In both cases T at E−1 is read last, and R2
   ends at E.

## Why signals do not use a copy of the frame below it

Other ports build the signal trampoline's frame *below* the interrupted
one. On this port the interrupt handler's C code runs on the interrupted
thread's own stack, exactly there (there is no interrupt stack). Building
the copy there overwrote the handler's return addresses; Step 08 found this
as a jump into RAM. Hence the redirect in place.

## Measured cost (Step 08, machine cycles; 1 machine cycle = 8 clocks)

| Path | Cycles |
|------|------:|
| interrupt entry (up to the C call) | 175 |
| interrupt exit (frame pop, RET) | 119 |
| thread-level save (`cosmac_switchcontext`) | 170 |
| thread-level restore (`cosmac_fullcontextrestore` + exit) | 141 |
| **thread-level context switch, total** | **311** (2 488 clocks; H5: "roughly 2 000") |
