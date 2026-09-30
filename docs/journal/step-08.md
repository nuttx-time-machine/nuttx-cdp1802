# Step 08 — Context switching

**Goal (contract):**
- the context layout, with a byte-accurate diagram (`docs/cdp1802/context.md`);
- `up_initial_state`, the switch path (from interrupts and from thread
  level), stack creation/use/release and task exit;
- signal delivery;
- the measured context-switch cost (H5).

**Exit:** two threads alternate under preemption, semaphores and `usleep`
work, and the test script verifies interleaved output. Profile: HWB
(banked).

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

> **Erratum (found in Step 10, fixed after `step-09-ostest`).** The signal
> delivery code in this tag has a bug. A signal delivered to a *running*
> thread resumes `cosmac_sigdeliver()` with SP at the thread's free byte
> M(SP), and its first push overwrites that byte. The byte is live for
> 2–3 instructions inside `cosmac_ncrt_ret`/`cosmac_ncrt_call` and in
> compiled ALU sequences, so a signal landing there corrupts a return
> address. This tag's tests pass only because no signal hit that window.
> The fix (save and restore M(SP) with the frame) and a "signal storm"
> test that fails without it are in `step-10-nsh`: journal step-10,
> problem #3; ADR 0017, "Revision at step-10".

## What was done, in order

1. **Thread-level switch** (`cosmac_doswitch.S`: `cosmac_switchcontext`,
   `cosmac_fullcontextrestore`). It builds the Step 07 frame and resumes
   through the interrupt exit path with P=1 (ADR 0017).
2. `up_switch_context`, `up_exit`, `up_initial_state` for new threads (a
   frame at the stack top with IE=1, plus a trap return address), and
   `up_create/use/release_stack`.
3. **Per-thread banking state** (`xcp.bankstate`, `xcp.brs`,
   `cosmac_bank_switch`), switched wherever the running task changes.
4. **Signals:** `up_schedule_sigaction`, `cosmac_sigdeliver`,
   `cosmac_sigreturn` (with `CONFIG_ENABLE_ALL_SIGNALS`).
5. `ARCH_HAVE_STACKCHECK`, `up_check_tcbstack` (fill byte 0xa5).
6. **Test** `sim1802:threads` (`sim1802_threadtest.c`, the init task's
   entry point) and `scripts/check-threads.py`.
7. Tools:
   - the simulator's trace names the selected bank (`[bN]`), and
     `trace-profile.py --elf` resolves banked names from it;
   - `trace-profile.py` gained `--whole`, `--stop` and stdin input.

## Problems met

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cosmac_switchcontext.o` built twice (make warning) | an `.S` and a `.c` file with the same base name | the assembly is `cosmac_doswitch.S` (as AVR's `avr_doswitch.S`) |
| `tcb_s` has no member `sigdeliver` | signal actions exist only with `CONFIG_ENABLE_ALL_SIGNALS`; `DEFAULT_SMALL` selects the partial level | signal files built only with it; the test config enables it |
| Signal from a watchdog (interrupt) to the running task: jump into RAM (`R3 = g_wdog`), then `IDL` with IE=0 trapped as deadlock | `up_schedule_sigaction` built the trampoline frame *below* the interrupted frame, as RISC-V does. Here the interrupt handler's own C stack is there, and was overwritten | the frame is redirected in place; the original goes to `xcp.sigregs`; `cosmac_sigreturn` copies it back with IE=0, using registers only (ADR 0017) |
| Round-robin tasks never alternated in the first test | test bug: the busy-wait measured its start time before a `syslog()` line that itself takes about 90 ticks, so the task was almost never preemptible when a tick came | counter-based test: two tasks count, a higher-priority task samples the counters every 60 ms |
| RR time slices still costly | `sched_roundrobin.o` runs on every tick with `CONFIG_RR_INTERVAL` and had been banked | fixed in `banks.txt` |
| Yield test hung | test bug: a higher-priority partner started first and yielded forever to nobody | both tasks created under `sched_lock()` |
| Fixed ROM overflow (`.text` will not fit in `rom`) | full signal support plus the tick path made fixed code about 31 KB | 64-bit division helpers banked; default bank count 8 |
| No stack-usage lines | `STACK_COLORATION` depends on `ARCH_HAVE_STACKCHECK` | `ARCH_COSMAC` selects it |
| `sim1802:threads` does not fit SIM64 | full signal support: the flat image is 22.7 KB over 64 KiB | the test runs on HWB only (the Step 07+ profile) |
| Step 06 regression: `sim1802:minimal` (SIM64) failed to link, 458 bytes over 64 KiB | the real interrupt, timer and switch code replaced the Step 04 stubs | `minimal` moved to HWB (amendment A5: Steps 07+ on HWB); it now prints "Hello, World!!" from the banked image. `sim1802:boot` still covers SIM64 |
| size reports understated banked images | `size-report.py` ignored `.bankN.text` sections | it counts them and prints fixed ROM and per-bank totals |

## Test

```
$ scripts/test-step-08.sh
ok: lsie: rr turns=8, usleep ticks=[13, 12, 13]; 200 sched_yield() round trips: 7469199 cycles, 747 ticks
ok: swflag: rr turns=8, usleep ticks=[15, 12, 12]; 200 sched_yield() round trips: 7681125 cycles, 769 ticks
    sigblocked used 532 of 998 stack bytes
    sigrunning used 501 of 998 stack bytes
    init used 702 of 985 stack bytes
ok: thread-level context switch 311 machine cycles = 2488 clocks (H5: ~2000 clocks)
ok: nxstyle, checkpatch
PASS: step 08
```

The interleaved output (LSIE run). The counters of rrA and rrB take turns
between samples:

```
threads: rr A=13 B=0
threads: rr A=13 B=0
threads: rr A=13 B=0
threads: rr A=15 B=0
threads: rr A=15 B=26
threads: rr A=35 B=26
threads: rr A=35 B=40
threads: rr A=51 B=41
threads: rr A=65 B=41
threads: rr A=65 B=71
threads: rr A=95 B=71
threads: rr A=95 B=81
threads: sem ping 1 / sem pong 1 / ... / sem pong 4   (strictly alternating)
threads: signal 10 handled
threads: blocked task: sem_wait() EINTR
threads: signal 12 handled
threads: running task stopped by its signal
```

The counters are small because the sampling task's own `syslog()` lines
take most of the CPU: one line costs about 11 000 cycles per character on
the banked build (several far calls per character). That is a Step 09/11
tuning item.

## Measurements

| | machine cycles |
|--|--:|
| thread-level context switch (trace: save 170 + restore 141) | **311** = 2 488 clocks (H5: ~2 000 clocks, validated within 25 %) |
| interrupt entry + exit | 294 (+1) |
| `sched_yield()` + switch, from the test (400 yields, ticks removed) | ≈ 11 900 |
| `usleep(1)`: CPU time of the call (trace, ticks excluded) | ≈ 26 000 (about 11 000 of it NCRT call overhead) |
| task stacks used (1 KiB stacks) | 501–702 bytes |

`usleep(200 ms)` takes 11 ticks plus that CPU time: 12–15 ticks at 50 Hz.
The test accepts 11–16.

## Notes

- H5 ("a full context save plus restore costs roughly 2 000 clocks") holds:
  2 488 clocks.
- Full signal support is expensive in ROM: 4 banks plus 30 KB fixed for
  this test.
- The NSH gate (Step 10) will need the tuning items above.

## Time spent

About 5 h.
