# 14. Validation: ostest and step tests

> First tag: `step-09-ostest`. ADRs 0019, 0020; journal `step-09.md`.

## 14.1 Test every step, automatically

Each step of this port ends with a script (`scripts/test-step-NN.sh`) that
builds the configuration, runs it in the simulator, and checks output and
exit status. Make the target **stop by itself** with a status:

- a test that passes powers off with status 0
  (`CONFIG_TESTING_OSTEST_POWEROFF`, `board_power_off()`);
- an assertion stops the run with a failure status
  (`CONFIG_BOARD_RESET_ON_ASSERT`, `board_reset()`);
- a cycle limit (`--max-cycles`) catches hangs.

> **CDP1802 example:** `board_power_off()` and `board_reset()` halt
> sim1802 with the given status (`sim1802_boardctl.c`). `ostest` exits 0
> when it passes; an assertion exits 3; a hang exits 96.

## 14.2 ostest on a small, slow target

`apps/testing/ostest` exercises tasks, pthreads, mutexes, condition
variables, semaphores, cancellation, signals, watchdogs, round-robin
scheduling and more. Expect three kinds of trouble:

1. **Real bugs** in your port, and in common code for unusual
   architectures (16-bit `int`, big-endian, no MMU).
2. **Resources:** ROM and RAM for the test itself. Reduce stack sizes,
   thread counts and loop counts, and record each reduction.
3. **Timing assumptions.** Many tests synchronise with `sleep()`: "the other
   thread will have printed its line and blocked within one second". On a
   slow CPU this fails, or deadlocks, without any bug.

> **CDP1802 example**, in the order found:
> - `ostest` never passed its first test with stdin at `/dev/null`: a
>   simulator bug (endless IRQ 6 after end of input).
> - Cancellation test 5 hung: a **common-code bug**. `pthread_cond_t`'s
>   wait count was an `int` accessed as a 32-bit atomic, and on a
>   big-endian CPU with 16-bit `int` the count never changed (ADR 0019).
> - After an assertion, the CPU ran into string data: a **port bug**. A
>   far call's return entry was on the bank return stack inside the TCB
>   that `nxtask_exit()` frees.
> - The timed semaphore and signal handler tests failed, and the task
>   restart test deadlocked: **timing** (printing costs about 18 ms per
>   character at 4 MHz). The ostest configuration runs at a virtual 64 MHz
>   (ADR 0020), and the 4 MHz behaviour is recorded.

## 14.3 Tools that pay for themselves

- **An instruction trace with symbols** (`sim1802 -t`), profiled per function
  (`scripts/trace-profile.py`). This showed where a tick, a far call or a
  printed character spends its cycles.
- **A memory dump at exit** (`sim1802 --dump`) and a task-list walker
  (`scripts/nuttx-tasks.py`). When everything is blocked and only the
  tick runs, a trace shows nothing; the TCBs show who waits on what, and
  who holds it.
- **A reference run on the host simulator** (`sim:ostest`), with the same
  options where possible. It separates "the test or common code does this
  everywhere" from "only my port does this".

## Checklist

- [ ] Every test run ends with a status: pass, assertion, or cycle limit.
- [ ] ostest passes; every disabled or reduced test is listed with the
      reason.
- [ ] Failures are classified as port bug, common-code bug, resource limit,
      or timing assumption, each with its evidence.
- [ ] You can inspect a hung system's task list.

## Common pitfalls

- Chasing a "hang" that is really the CPU being too slow for the test's
  sleeps. Measure how long one printed line takes first.
- Atomic operations on fields that are not the size the atomic API
  assumes (`volatile void *` parameters hide it from the compiler).
- Stdin tied to a terminal or socket in automated runs: use `/dev/null`
  or a file.
