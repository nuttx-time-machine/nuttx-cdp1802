# 0017 — Context switch: one frame, one restore path; signals redirect the frame in place; per-thread bank state

Status: Proposed (agent)
Date: 2026-09-29
Step: step-08

## Context

Step 07 fixed the register frame and the restore path (ADR 0015). Step 08
has to add:
- the thread-level switch (`up_switch_context` outside interrupts);
- new threads (`up_initial_state`), stacks and `up_exit`;
- signal delivery;
- banking state per thread (ADR 0013).

Constraints:
- The restore path must run with P ≠ 3, because it reloads R3.
- There is no interrupt stack: an interrupt handler's C code runs on the
  interrupted thread's stack, just below its frame.

## Decision

1. **Thread-level switch** = `cosmac_switchcontext(&rtcb->xcp.regs,
   tcb->xcp.regs)`. It builds the same 31-byte frame as the interrupt entry,
   with T = 0x23 and R3 = a `sep 5` that returns from the call. IE comes
   from LSIE or the RAM copy. It then jumps to the interrupt exit path with
   P=1 (R1 is free while IE=0). One restore path serves every case, so the
   IE, R1 and R4/R5 handling exists once.
2. **New threads**: a frame at the top of the stack, as if the thread had
   been interrupted before its first instruction (IE=1), with a return
   address (`cosmac_thread_return`, PANIC) above it. That address is needed
   because a banked entry point's stub treats its entry as a call.
3. **Signals**: `up_schedule_sigaction` **redirects the frame in place** and
   keeps the original 31 bytes in the TCB (`xcp.sigregs`). This differs
   from RISC-V/ARM, which build a copy below the frame: here that region is
   the running interrupt handler's stack. `cosmac_sigdeliver` delivers, and
   `cosmac_sigreturn` copies the frame back over its own stack region with
   IE=0, using registers only, then resumes it.
4. **Banking**: every TCB has `bankstate[4]` and its own bank return stack
   (`brs[3 × CONFIG_COSMAC_BRS_DEPTH]`). `cosmac_bank_switch(from, to)` runs
   in fixed code with IE=0 and makes no calls, and so no banked calls
   (loops, not `memcpy`). It runs wherever the running task changes: in
   `cosmac_doirq`, `up_switch_context` and `up_exit`.
5. `ARCH_COSMAC` selects `ARCH_HAVE_STACKCHECK`; `up_check_tcbstack` scans
   for the fill byte 0xa5 (`CONFIG_STACK_COLORATION`).

## Consequences

- **H5 validated:** a thread-level switch costs **311 machine cycles =
  2 488 clocks** (trace: save 170 + restore 141); H5 said "roughly 2 000".
  The interrupt path is 294 + 1 machine cycles.
- TCB growth: 2 + 2 + 31 bytes (signals), plus 4 + 48 bytes (banking,
  depth 16).
- The signal copy-back needs no free stack below the frame.
- Full signal support (`CONFIG_ENABLE_ALL_SIGNALS`, needed for handlers) is
  large: `sim1802:threads` no longer fits the flat 64 KiB SIM64 profile, and
  in HWB it needs a fourth bank. The default bank count became 8.
- Round-robin processing (`sched_roundrobin.o`) is on the tick path and was
  added to the fixed-ROM rules (ADR 0016).

## How to revisit

- An interrupt stack would allow the usual copy-below signal frame, and
  smaller thread stacks.
- If the scheduler's own cost dominates, move its hot objects to fixed ROM.
  A `sched_yield()` plus switch costs about 11 900 cycles (400 of them took
  7.30 M cycles, of which about 2.56 M were 731 ticks); the switch itself
  is 311 of those.
