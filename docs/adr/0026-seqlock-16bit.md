# 0026 — Common code: the tick seqlock's sequence number must be uint32_t

Status: Proposed — common-code bug fix, needs Alan's review. A patch for
mainline is prepared in `docs/upstream/` (not sent).
Date: 2026-09-30
Step: after step-10 (found by Alan testing NSH by hand)

## Context

Alan ran NSH in sim1802 and typed `ps`. There was no answer, and nothing
he typed afterwards got one either.

Tracking it down (journal step-10, "NSH stops after 65 536 ticks"):
- the hang did not depend on the command but on elapsed time. Without
  `--pace` the simulator runs idle time at full speed, so a pause of
  about 13 s at the terminal is 65 536 ticks;
- memory dumps showed `g_system_ticks` stuck at exactly 65 536, and the
  tick seqlock's sequence number at exactly 0x00010000;
- `clock_get_sched_ticks()` (sched/clock/clock_sched_ticks.c) stores the
  `uint32_t` from `read_seqbegin()` in an `unsigned int`, which is 16 bits
  here, and passes it back to `read_seqretry()`, which compares 32 bits.

From sequence 65 536 on, every retry check fails. The tick interrupt calls
`clock_systime_ticks()`, which ends in `clock_get_sched_ticks()`, so it
spins forever with interrupts disabled. The system stops after 65 536
ticks: 54.6 minutes at 20 Hz, 11 minutes at 100 Hz, on real hardware as
well as in the simulator. The code came in with upstream commit
`29e514b276` (2026-01) and is still in master. Every 16-bit-`int` target
(AVR) is affected. The other readers of such a lock (`hrtimer.h`) already
use `uint32_t`.

## Decision

`uint32_t seq;` in `clock_get_sched_ticks()`: one line, one commit
(`sched/clock: keep the seqlock sequence in uint32_t`).

Also prepared for mainline, not sent:
`docs/upstream/0001-sched-clock-keep-the-seqlock-sequence-in-uint32_t.patch`
on apache/nuttx master (branch `upstream/clock-seqlock-16bit`).
checkpatch passes.

## Consequences

- NSH answers after any uptime; the check went up to 1 h 48 min.
- `scripts/test-step-10.sh` has a long-uptime check. NSH idles for 30 s
  of host time, beyond 65 536 ticks unpaced, then must answer `uptime`
  with more than 55 minutes. Without the fix it gets no answer; this was
  verified by reverting.
- While investigating, a separate race was found in the sim1802 fork: the
  console interrupt could be lost when a byte arrived while the queue was
  being drained. It was fixed in fork commit `f195be3` (`SIM_SHA`). It is
  not the cause of this hang, and was not seen to fail.
  `scripts/typing-test.py` types commands one character at a time as a
  regression check.

## How to revisit

When the upstream fix is merged, drop the local commit.
