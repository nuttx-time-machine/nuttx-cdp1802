# 11. Context switching and the interrupt frame

> First tag: `step-08-context`. ADR 0017; `docs/cdp1802/context.md`;
> journal `step-08.md`.

## 11.1 What NuttX expects

| Interface | Role |
|-----------|------|
| `up_initial_state(tcb)` | prepare a new thread's context so that switching to it starts `tcb->start` |
| `up_create_stack` / `up_use_stack` / `up_release_stack` | the thread's stack: `stack_alloc_ptr`, `stack_base_ptr`, `adj_stack_size`, `TCB_FLAG_FREE_STACK` |
| `up_stack_frame` | carve TLS and arguments from the stack |
| `up_switch_context(tcb, rtcb)` | from thread level: save `rtcb`, resume `tcb`. From an interrupt handler: usually nothing, because the interrupt exit resumes whatever `this_task()` is |
| `up_exit()` | the running task has been destroyed (`nxtask_exit()`); resume the next one |
| `g_running_tasks[]`, `nxsched_switch_context()` | bookkeeping when the running task changes |

## 11.2 One frame, one restore path

Make the thread-level switch build **the same frame** your interrupt entry
builds, and resume it through **the same exit code**. Then:
- a thread saved by an interrupt can be resumed by a thread-level switch,
  and the reverse, without special cases;
- a new thread is just a frame you write by hand;
- `up_exit()` and the end of signal delivery are "resume this frame".

Record in the frame how to resume: the interrupt-enable state belongs there.
A thread that switched from inside a critical section must resume with
interrupts disabled; an interrupted thread with them enabled.

> **CDP1802 example:** `cosmac_switchcontext()` pushes the 31-byte frame
> with R3 = a `sep 5` that returns from the call, then jumps into the
> interrupt exit path with P=1. That path reloads R3, so it cannot run with
> P=3. The resumed frame ends with `RET` or `DIS` depending on its IE byte.

## 11.3 The first frame of a thread

Write the frame as if the thread had been interrupted just before its first
instruction: PC = entry, interrupts enabled, and every register the calling
convention relies on (call helpers, global pointer, etc.) set up. If the
entry point could "return", put a trap there.

> **CDP1802 example:** R4/R5 = the NCRT routines, T = 0x23 (X=2, P=3),
> IE = 1. There is also a return address to a PANIC function above the
> frame: with code banking, the entry point may be a stub, and a stub
> treats its entry as a call.

## 11.4 Measure it

Count one switch in cycles from a trace, and compare it with your budget
(and with any figure your project assumed). Also measure the stacks: fill
them with a pattern (`CONFIG_STACK_COLORATION`, `up_check_tcbstack()`) and
look at the high-water marks.

> **CDP1802 example:** 311 machine cycles (2 488 clocks), against the
> assumed ~2 000 clocks (H5). Tasks of the Step 08 test used 500–700 of about
> 1 000 bytes of stack.

## Checklist

- [ ] One frame layout, documented byte by byte.
- [ ] Interrupt return and thread-level switch share the restore code.
- [ ] The frame records the interrupt state to resume with.
- [ ] New threads start through the normal restore path.
- [ ] Two equal-priority round-robin tasks take turns, and a semaphore
      ping-pong alternates.
- [ ] The switch cost and the stack high-water marks are measured.

## Common pitfalls

- Restoring the PC register while it is the PC (on the 1802: R3 while P=3).
- Forgetting per-thread state outside the registers. On this port that is
  the code-banking state: the selected bank and the bank return stack.
- Test code that does not test what you think. Here, a busy-wait that
  measured its start time before a long `syslog()` call hid the preemption
  it was meant to show (journal step-08).
