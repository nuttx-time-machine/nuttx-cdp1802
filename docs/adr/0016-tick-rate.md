# 0016 — System tick at 50 Hz, 1 KiB idle stack, tick path in fixed ROM

Status: Proposed (agent)
Date: 2026-09-29
Step: step-07

## Context

Step 07 measured one timer tick (interrupt entry, dispatch,
`nxsched_process_timer()`, exit) at **3 407 machine cycles**. The breakdown
comes from an instruction trace (`build/step07-hwb-lsie/tick-profile.txt`):

- about 1 050 cycles are NCRT call/return overhead (about 20 C calls);
- about 890 are the scheduler tick counter's seqlock
  (`clock_increase_sched_ticks`, `clock_get_sched_ticks`: 32-bit sequence
  updates);
- 294 are the entry and exit assembly.

At the nominal 4 MHz (500 000 machine cycles/s), the NuttX default of
100 Hz (`CONFIG_USEC_PER_TICK` = 10 000, 5 000 cycles per tick) would take
**68 %** of the CPU. With banking, the tick path first went through far
calls and took 5 795 cycles, more than the tick period. The system then
spent all its time in the tick interrupt (livelock).

## Decision

- `CONFIG_USEC_PER_TICK=20000` (50 Hz) in the sim1802 configurations: about
  34 % of a 4 MHz CPU. A real 1.76 MHz COSMAC board would need 20 Hz or
  less.
- The tick path is fixed ROM in the HWB placement rules (`banks.txt`):
  `irq_dispatch.o`, `sched_processtick.o`, `wd_start.o`,
  `clock_sched_ticks.o`, `clock_systime_ticks.o`,
  `sched_switchcontext.o`. With it fixed, a banked tick costs the same as
  a flat one (3 407 cycles).
- `CONFIG_IDLETHREAD_STACKSIZE` stays at its default of 1024 bytes (512
  before). The Step 07 test measured 684–696 bytes used (`syslog` output
  from the idle thread plus a timer interrupt on top). With 512 it
  overflowed into `.bss`.

## Consequences

- `usleep()` and time-out resolution is 20 ms.
- The tick overhead remains large; it is the first performance item for
  Step 11.

## Revision (Alan, after step-10): 20 Hz

Alan chose a 20 Hz tick (`CONFIG_USEC_PER_TICK=50000`) for every sim1802
configuration: "20 Hz is fine for a hobbyist system". A tick still costs
about 3 400 machine cycles, but now once every 25 000 cycles at 4 MHz,
so the tick takes about 14 % of the CPU instead of 34 %.
- Measured: NSH `ps` went from 9.59 M to 8.06 M cycles (−16 %).
- Timer resolution is 50 ms. `usleep()` and time slices round up to it.
- The `threads` test's round-robin interval went from 100 to 200 ms
  (4 ticks), so that its 60 ms samples still see the tasks take turns.
- The tests take their expectations from the build's tick rate
  (`scripts/cycles-per-tick.sh`).

## How to revisit

- **Tickless mode** (`CONFIG_SCHED_TICKLESS`) with the simulator's timer in
  one-shot use removes idle ticks entirely.
- A cheaper tick counter for uniprocessor builds would change common code
  (a separate commit with its own ADR).
- An interrupt stack reduces every thread's stack requirement.
