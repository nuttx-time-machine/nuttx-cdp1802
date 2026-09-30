# Step 09 — Serial driver and ostest

**Goal (contract):**
- an upper-half serial driver for the simulator console;
- `ostest` in a reduced configuration, with every disabled test documented
  and the reason why.

**Exit:** `ostest` completes without failure in the automated test.
Profile: HWB (banked).

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

> **Erratum (found in Step 10, fixed after this tag).** This tag contains
> the Step 08 signal-delivery bug described in the erratum at the top of
> journal step-08 (a signal in a 2–3-instruction window of the NCRT
> routines corrupts a return address). ostest passed without hitting the
> window. The fix is in `step-10-nsh`.

## What was done, in order

1. **Serial driver** (`boards/.../sim1802_serial.c`, `CONFIG_SIM1802_UART0`,
   the lower half of NuttX's serial upper half):
   - PUTCHAR output with no transmit interrupt: `txint(true)` sends the
     buffer immediately;
   - interrupt-driven input on IRQ 6 (level-triggered);
   - input flow control: when the buffer fills, IRQ 6 is masked and the
     rest of the input waits in the simulator.
   `up_initialize()` calls the board's `cosmac_serialinit()`
   (`CONFIG_MCU_SERIAL`).
2. **`sim1802:ostest`**: pthreads, full signals, round robin, line-buffered
   stdio, 1 KiB stacks, 16 banks.
3. Making it fit and run. The problems in the next table were found in
   this order.

## Problems met

| # | Symptom | Cause | Class | Fix |
|---|---------|-------|-------|-----|
| 1 | build: `lib_get_stream` undeclared | `stderr` needs `CONFIG_FILE_STREAM` (off with `DEFAULT_SMALL`) | config | enabled |
| 2 | warnings: integer overflow in ostest (`usleep(200 * 1000)` = 3 392 µs, …) | ostest assumes 32-bit `int` | apps bug on 16-bit targets | apps commit (ADR 0018) |
| 3 | fixed ROM overflow: 24 objects "take the address of their own function"; `spinlock.c` 35 KB > one bank | placement per object | tool limit | tool v2: placement by function, and every cross-bank reference rewritten to a stub, own addresses included (ADR 0013 revision) |
| 4 | libgcc's 10.5 KB `__udivdi3` linked instead of the port's | libgcc inside the library group | link order | libgcc after the group (ADR 0018) |
| 5 | fixed ROM still full: read-only strings about 20 KB | read-only data is always fixed | structural | architecture library (apart from the switching code) and memory manager banked; kernel debug strings off in `sim1802:ostest` |
| 6 | no output past the first test with stdin at `/dev/null`; IRQ 6 storm | **simulator bug**: after EOF each STATUS started a new console reader, which signalled EOF again | simulator | reader kept after EOF (fork commit `d52240f`) |
| 7 | cancellation test 5 hangs (idle, `pthread_join` forever) | **common-code bug**: `pthread_cond_t.wait_count` and the `wcnt` locals are `int`, but they are used as 32-bit atomics. On a big-endian 16-bit target the count never changes: a lost wake-up. The host `sim:ostest` passes the same test | common code | 3 lines, own commit (ADR 0019; needs Alan's review) |
| 8 | timed semaphore test: `sem_timedwait` → ETIMEDOUT | the waiter's 2 s deadline covers two printed lines and a 1 s sleep of the poster. At 4 MHz one character costs about 18 ms (profile: about 9 000 cycles/char plus 42 % tick load) | timing | virtual clock (ADR 0020) |
| 9 | printing about 23 000 cycles/char | the stdio chain spread over 5 banks, several far calls per character | placement | stdio chain in bank 0, write path in bank 1: −34 % |
| 10 | after an assertion the CPU runs into string data | **port bug**: `up_exit()` → `nxtask_exit()` is a far call whose return entry is on the bank return stack inside the TCB that `nxtask_exit()` frees | port | static bank return stack for the exit path |
| 11 | signal handler test: waiter "did not exit" | the waiter prints 5 lines (about 3.5 s) before waiting; the signal comes at 2 s | timing | virtual clock |
| 12 | timed mutex test failed in one build, passed in another | timing, depends on code layout | timing | virtual clock |
| 13 | at a virtual 16 MHz: task_restart test deadlocks (only the tick runs) | `--dump` and the TCB walker (`scripts/nuttx-tasks.py`) show the restarted task waiting for the serial transmit mutex (`xmit.lock`), whose holder is its own PID: `task_restart()` came during `uart_write()`, and NuttX does not release mutexes on restart. A test hazard on any slow system | timing | 64 MHz virtual clock |
| 14 | round-robin test: hours | primes < 30 000 by trial division up to n/2, 10 runs × 2 threads ≈ 10¹¹ cycles | resources | `CONFIG_TESTING_OSTEST_RR_RANGE=1000` |

The tools that found #6, #7, #10 and #13:
- the simulator's `--dump`, and `scripts/nuttx-tasks.py`: task states, wait
  objects and holders from a memory image;
- bank-aware trace profiles (`scripts/trace-profile.py --elf`);
- a host `sim:ostest` build with the port's options for comparison.

## ostest: what runs and what does not

**Runs** (with `sim1802:ostest`): argument, getopt, libc, setvbuf,
task_restart, waitpid, mutex, timed mutex, cancellation (tests 1, 3 and 5;
tests 2, 6 and 7 print "Skipped" because they need
`CONFIG_CANCELLATION_POINTS`), semaphore, timed semaphore, condition variable,
pthread_exit, rwlock, rwlock cancel, timed wait, sigprocmask, signal
handler, nested signal handler, spinlock, watchdog, round-robin, barrier,
scheduler lock.

**Compiled out, and why:**

| Test | Needs | Why not here |
|------|-------|--------------|
| vfork(), fork() | `ARCH_HAVE_VFORK/FORK` | not implemented by the port (no MMU; vfork would need stack copying) |
| sched_thread_local | `SCHED_THREAD_LOCAL` | not implemented by the port |
| /dev/null, AIO, chroot, multi-user, named semaphores | `DEV_NULL`, `FS_AIO`, `FS_CHROOT`, `SCHED_USER_IDENTITY`, `FS_NAMED_SEMAPHORES` | file-system features not in the small configuration (ROM/RAM) |
| FPU | `ARCH_FPU` | no FPU |
| work queue | `SCHED_WORKQUEUE` | not enabled (RAM: one more thread) |
| recursive mutex, robust mutex | `PTHREAD_MUTEX_TYPES`, not `PTHREAD_MUTEX_UNSAFE` | `DEFAULT_SMALL` mutex options (ROM) |
| pthread-specific data, pthread_cleanup | `TLS_NELEM`, `TLS_NCLEANUP` > 0 | 0 in the small configuration (TCB/stack RAM) |
| message queue tests, cancellation tests with message queues | `!DISABLE_MQUEUE` | message queues disabled (ROM) |
| POSIX timer, SIGEV_THREAD timer | `!DISABLE_POSIX_TIMERS` | disabled (ROM) |
| cancellation tests 2, 6, 7 (printed as "Skipped") | `CANCELLATION_POINTS` | not enabled by `DEFAULT_SMALL` (ROM) |
| signal action (SIGSTOP/SIGKILL) | `SIG_SIGSTOP_ACTION`, `SIG_SIGKILL_ACTION` | not enabled |
| hrtimer, sporadic scheduler, priority inheritance, nxevent, SMP, perf counters | `HRTIMER`, `SCHED_SPORADIC`, `PRIORITY_INHERITANCE`, `SCHED_EVENTS`, `SMP`, `ARCH_PERF_EVENTS` | not enabled or not applicable |
| setjmp | `ARCH_SETJMP_H` | not implemented by the port |
| environment variables | `!DISABLE_ENVIRON` | disabled (RAM) |

**Reduced:** test stacks 1 024 bytes (default 8 192); 2 barrier threads
(default 8); spinlock loop scale 1 (100 000 loops; default 100); round-robin
range 1 000 (default 30 000).

**Every one of these options can be enabled** on this port with enough
ROM (banks are cheap: 16 of 256 used) and RAM (16 KiB is the limit). The
ones listed as "not implemented by the port" are Step 11 candidates.

## Test

```
$ scripts/test-step-09.sh
ok: sim1802:ostest builds (banked: fixed ROM = 32619 bytes, banks = 216148 bytes (bank 0: 16128, ... bank 13: 11430))
ostest: exit 0, 24 tests started, 0 ERROR lines, 2308627862 machine cycles, 188s host time
ok: ostest passed
ok: nxstyle, checkpatch
PASS: step 09
```

The 24 tests, in the order they ran: argument, getopt, libc, setvbuf,
task_restart, waitpid, mutex, timed mutex, cancel, semaphore, timed
semaphore, condition variable, pthread_exit, pthread_rwlock,
pthread_rwlock_cancel, timed wait, sigprocmask, signal handler, nested
signal handler, spinlock, wdog, round-robin scheduler, barrier, scheduler
lock. The run ends with "ostest_main: Exiting with status 0", and ostest
powers off with that status. At the end the heap (13 534 bytes) has
6 240 bytes in its largest free block.

## At the real 4 MHz

```
$ scripts/test-step-09.sh --clock 4000000
ostest: exit 3, 11 tests started, 1 ERROR lines, 247809919 machine cycles, 24s host time
semtimed_test: Waiting for two second timeout
poster_func: Waiting for 1 second
semtimed_test: ERROR: sem_timedwait failed with: 110
(informational run at 4000000 Hz)
```

The first 10 tests pass at 4 MHz. The 11th (timed semaphore) fails as
analysed in #8, and the assertion stops the run (status 3). Earlier runs,
with the time-based tests skipped by hand, showed that the signal handler
test (#11) and, depending on code layout, the timed mutex test (#12) fail
for the same reason.

## Notes

- The 4 MHz run is informational (`scripts/test-step-09.sh --clock
  4000000`; ADR 0020).
- Fixed ROM is the port's tightest resource: `sim1802:ostest` uses 32 619
  of 32 768 bytes, most of it read-only strings. See Step 10.

## Time spent

About 10 h (debugging #6, #7, #10 and #13 dominated).
