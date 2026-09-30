#!/usr/bin/env python3
# scripts/check-threads.py <output> -- verify the output of sim1802:threads
# (boards/cosmac/cdp1802/sim1802/src/sim1802_threadtest.c, Step 08).
import re
import sys

out = open(sys.argv[1]).read()
lines = [l for l in out.splitlines() if l.startswith("threads:")]
fails = []


def need(cond, what):
    if not cond:
        fails.append(what)


# 1. Preemption: the counters of two equal-priority RR tasks take turns
samples = [tuple(map(int, m.groups()))
           for m in re.finditer(r"threads: rr A=(\d+) B=(\d+)", out)]
need(len(samples) == 12, "12 rr samples")
turns, last = 0, None
for (a0, b0), (a1, b1) in zip(samples, samples[1:]):
    who = "A" if a1 > a0 and b1 == b0 else "B" if b1 > b0 and a1 == a0 else None
    if who and who != last:
        turns += last is not None
        last = who
need(samples and samples[-1][0] > 0 and samples[-1][1] > 0, "both RR tasks ran")
need(turns >= 3, "RR tasks took turns at least 3 times (got %d)" % turns)

# 2. Semaphore ping-pong in strict order
sem = [l for l in lines if " sem " in l]
want = ["threads: sem %s %d" % (w, i) for i in range(1, 5) for w in ("ping", "pong")]
need(sem == want, "sem ping/pong order")

# 3. usleep(200 ms): never early (10 ticks + 1), and late only by the CPU
#    time of the call itself: about 26 000 machine cycles (2.6 ticks at
#    50 Hz) of setup and wake-up on the banked build (journal step-08)
sl = [int(m.group(1)) for m in re.finditer(r"usleep\(200 ms\): (\d+) ticks", out)]
need(len(sl) == 3 and all(11 <= t <= 16 for t in sl), "usleep 11..16 ticks: %s" % sl)

# 4. Signals
for s in ("signal 10 handled", "blocked task: sem_wait() EINTR",
          "signal 12 handled", "running task stopped by its signal"):
    need("threads: " + s in out, s)
storm = re.search(r"signal storm: (\d+) signals, (\d+) errors", out)
need(storm and int(storm.group(1)) >= 100 and storm.group(2) == "0",
     "signal storm: >= 100 signals, 0 errors")

# 5. Context switches, task exit, end
need(re.search(r"200 sched_yield\(\) round trips: \d+ cycles", out), "yield")
need("threads: done" in out, "done")
need("FAIL" not in out and "assert" not in out.lower(), "no failure/assertion")

if fails:
    print("\n".join("FAIL: " + f for f in fails))
    sys.exit(1)
print("rr turns=%d, usleep ticks=%s, storm signals=%s" % (turns, sl, storm.group(1)))
