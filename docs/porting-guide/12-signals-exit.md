# 12. Signals and task exit

> First tag: `step-08-context`. ADR 0017; journal `step-08.md`.

## 12.1 What NuttX expects

With `CONFIG_ENABLE_ALL_SIGNALS`, NuttX calls `up_schedule_sigaction(tcb)`
when a signal action must run on `tcb` and cannot run immediately. That
happens when `tcb` is not running, or when it is the running task and we
are inside an interrupt handler. (A task that signals itself at thread
level gets the handler called directly.) The port arranges for `tcb` to run
a *signal trampoline* the next time it resumes. The trampoline:
1. enables interrupts;
2. calls `tcb->sigdeliver(tcb)` (repeating while actions are pending);
3. disables interrupts;
4. clears `tcb->sigdeliver`;
5. resumes the original context exactly.

`up_exit()` runs after `nxtask_exit()` has removed the running task. It
resumes the new head of the ready-to-run list and never returns.

## 12.2 Where to build the trampoline's context

Most ports keep the interrupted frame (`xcp.saved_regs`) and build a copy
*below* it on the thread's stack that enters the trampoline. That is only
safe if nothing else uses that memory at that moment. **If your interrupt
handlers run on the interrupted thread's stack**, the handler itself is
there when a signal is sent from interrupt context.

> **CDP1802 example:** the copy-below approach overwrote the running
> interrupt handler's return addresses: the test jumped into RAM and
> stopped on an `IDL` with IE=0. The port now *redirects the frame in
> place*. The original 31 bytes go to the TCB; the frame's PC becomes
> `cosmac_sigdeliver`, with IE = 0 and the NCRT registers reset. At the end,
> `cosmac_sigreturn` copies the original back over the trampoline's own
> stack. It uses registers only, with interrupts disabled, then resumes.

## 12.3 Test both cases

- A signal to a task **blocked** in `sem_wait()`: the handler runs and
  `sem_wait()` returns `EINTR`.
- A signal sent **from an interrupt** (e.g. a watchdog callback calling
  `nxsig_kill()`) to the task that is running: the handler runs, and the task
  continues where it was interrupted.

> **CDP1802 example:** both are in `sim1802:threads`
> (`boards/.../sim1802_threadtest.c`), checked by `scripts/check-threads.py`.

## Checklist

- [ ] The trampoline resumes the exact interrupted context (all
      registers, interrupt state, and any per-thread state such as banks).
- [ ] Signals to blocked and to running (interrupted) tasks both work.
- [ ] Tasks can return from their entry point, and the next task resumes.

## Common pitfalls

- The copy-below frame when handlers share the thread stack (12.2).
- Registers that are "constant" for C code but may be anything in an
  interrupted frame (on the 1802, R4/R5): reset them in the trampoline's
  frame.
