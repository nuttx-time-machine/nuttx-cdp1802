# 0020 — ostest runs with a virtual 64 MHz clock; the 4 MHz limits are documented

Status: Proposed (agent). Flagged for Alan: this decides how the Step 09
exit criterion is met.
Date: 2026-09-29
Step: step-09

## Context

ostest verifies OS behaviour: ordering, wake-ups, cancellation, signals.
Many of its tests synchronise by *time*: a thread prints, sleeps, then
posts; the other side waits with a 1–2 s deadline. On the CDP1802 at the
board's nominal 4 MHz (500 000 machine cycles/s):

- console output through NuttX's stdio and serial layers costs about
  9 000 machine cycles per character. That is about 18 ms per character,
  so a 40-character line takes about 0.7 s;
- the 50 Hz tick takes another 34–42 % of the CPU (ADR 0016).

Observed at 4 MHz:
- **timed semaphore test:** the waiter's deadline (2 s) expires before the
  poster has printed two lines and slept 1 s;
- **signal handler test:** the waiter prints five lines (about 3.5 s)
  before it waits, but the signal comes after 2 s;
- **timed mutex test:** it passed in one build and failed in another,
  after an unrelated change in code layout.

These are properties of the test's timing assumptions and of the CPU's
speed, not port faults: the same logic passes when there is time. The
nominal 4 MHz is already close to the family's limit: the CDP1805AC's
maximum clock is 5 MHz [DS1805 p. 4] (board-sim1802.md §1). A real COSMAC
system would fail the same tests.

The simulation is cycle-exact. The board's clock (`CONFIG_BOARD_SIM1802_CLOCK_HZ`)
only converts time to machine cycles for the timer and for measurements.

## Options considered

1. Disable the time-dependent tests one by one. Rejected: which tests
   fail depends on code layout. The set would be unstable, and it would
   remove the most interesting tests (timed waits, signals).
2. Make the port faster. Tickless mode, placement, and a faster NCRT or
   compiler all help, but none gives the 3–5× that these tests need. This
   remains worthwhile future work (Step 11, NSH usability).
3. **Run ostest with a faster virtual clock, declared as virtual.**
   The code, the cycle counts and the scheduling are unchanged. Only
   simulated time runs slower relative to the instructions.

## Decision

Option 3, at **64 MHz**:
- `sim1802:ostest` sets `CONFIG_BOARD_SIM1802_CLOCK_HZ=64000000`. That is
  8 M machine cycles/s, so a 40-character line takes about 45 ms. The
  50 Hz tick is 160 000 cycles, and its overhead is about 2 %.
- 16 MHz was tried first. There, ostest's task_restart test deadlocked,
  deterministically. The test restarts a task every 5 s while that task
  prints every 2 s. At 16 MHz a print took about 0.2 s, and the restart
  landed inside `uart_write()`. The restarted task then waited for the
  serial transmit mutex that its previous incarnation still held
  (`nxtask_restart()` does not release mutexes), and so did the test.
  This was found with the simulator's new `--dump` and the TCB list
  (journal step-09). It is a hazard of the test on any slow system, not a
  port fault. At 64 MHz a print takes a few percent of the loop, as on a
  typical MCU.
- The Kconfig help and the journal say that no CDP1802 runs at 64 MHz.
- The journal records which tests fail at 4 MHz, and why.
- Assertions stop the simulator with status 3
  (`CONFIG_BOARD_RESET_ON_ASSERT`), and ostest powers off with its result
  (`CONFIG_TESTING_OSTEST_POWEROFF`), so a run cannot hang silently.

## Consequences

- The exit criterion "ostest completes without failure" is met for OS
  logic, not for real-time performance at a real COSMAC clock.
- Performance work (tickless, the tick path, the stdio path) has a clear
  target: the same ostest at 4 MHz.

## How to revisit

After the Step 11 performance work, run `sim1802:ostest` with the clock at
4 MHz and update the list of failing tests (`scripts/test-step-09.sh
--clock 4000000`).
