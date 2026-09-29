# 10. The system timer and timekeeping

> First tag: `step-07-irq-timer`. ADR 0016; journal `step-07.md`.

## 10.1 What NuttX expects

In the default (tick) mode, the port provides `up_timer_initialize()`. It
starts a periodic interrupt every `CONFIG_USEC_PER_TICK` microseconds, and
its handler calls `nxsched_process_timer()`. That one call advances the
system clock, expires watchdogs (`wd_start()`), and drives time slicing
and time-outs.

(`CONFIG_SCHED_TICKLESS` replaces the periodic tick with one-shot alarms
and needs `up_alarm_*` or `up_timer_*` interfaces instead.)

## 10.2 Choosing the tick rate

The NuttX default is 100 Hz. On a slow CPU, **measure one tick** first. At
rate *f*, a tick of *c* cycles costs *f × c* cycles per second.

> **CDP1802 example:** one tick costs about 3 400 machine cycles. Of these,
> about 1 050 are C call overhead and about 890 the tick counter's seqlock.
> At 100 Hz that is 68 % of a 4 MHz CPU (500 000 machine cycles/s). The
> sim1802 configurations use 50 Hz (`CONFIG_USEC_PER_TICK=20000`, 34 %).
> Time-outs therefore have 20 ms resolution.

## 10.3 Verify the rate in simulated time

A simulator with a cycle-driven timer lets you check the tick rate
*exactly*. Start a watchdog that re-arms itself, record the tick count and
a cycle counter at every callback, and compare. `wd_start(delay)` expires
after `delay + 1` ticks, because the first, partial tick does not count.

> **CDP1802 example** (`sim1802:tick`, `boards/.../sim1802_ticktest.c`):
> six callbacks, each exactly 51 ticks = 510 000 machine cycles apart, in
> the banked and flat profiles and with both interrupt-state variants
> (`scripts/test-step-07.sh`).

## 10.4 Keep the tick path cheap and always mapped

The tick is the most frequent interrupt. If you bank code (chapter 15),
keep everything the tick calls in fixed memory.

> **CDP1802 example:** with the tick path banked, a tick took 5 795 cycles,
> more than the 5 000-cycle period at 100 Hz. The system never left the
> interrupt: livelock, not a crash. After the rule change it took 3 407.

## Checklist

- [ ] One tick is measured in cycles; the rate leaves most of the CPU to
      the application.
- [ ] A watchdog test shows the exact number of ticks between callbacks.
- [ ] The tick path is in fixed memory (banked systems).

## Common pitfalls

- Expecting `wd_start(n)` to fire after exactly *n* ticks (it is *n* + 1).
- A tick that costs more than its period: the symptom is a system that
  prints its first boot message and then appears to hang.
