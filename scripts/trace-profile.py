#!/usr/bin/env python3
# scripts/trace-profile.py <trace> [--start SYM] [--nth N]
#
# Profile one interrupt (or any region) from a sim1802 instruction trace
# (sim1802 -t, lines "@ symbol+offset (addr) op XX").  The region starts at
# the Nth execution of SYM+0 (default: cosmac_irq_entry, N=2 so that the
# first tick after boot is skipped) and ends when execution leaves the
# interrupt code: at the first instruction after the RET/DIS that resumes
# the interrupted thread.  Prints machine cycles per function (2 per
# instruction, 3 for long branches, long skips and NOP; RCA MPM-201A p. 8).
import argparse
import collections
import re

LINE = re.compile(r"^@ ([^+ ]+)(?:\+([0-9a-f]+))? \(([0-9a-f]{4})\) op ([0-9a-f]{2})")


def cycles(op):
    return 3 if 0xC0 <= op <= 0xCF else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--start", default="cosmac_irq_entry")
    ap.add_argument("--nth", type=int, default=2)
    ap.add_argument("--top", type=int, default=25)
    a = ap.parse_args()
    seen = 0
    active = False
    per = collections.Counter()
    count = collections.Counter()
    total = 0
    prev_op = None
    for line in open(a.trace, errors="replace"):
        m = LINE.match(line)
        if not m:
            continue
        sym, off, op = m.group(1), int(m.group(2) or "0", 16), int(m.group(4), 16)
        if not active:
            if sym == a.start and off == 0:
                seen += 1
                active = seen == a.nth
            if not active:
                continue
        elif prev_op in (0x70, 0x71) and prev_sym.startswith("cosmac_irq"):
            break  # the RET/DIS of the exit path resumed the thread
        per[sym] += cycles(op)
        count[sym] += 1
        total += cycles(op)
        prev_op, prev_sym = op, sym
    print("%-40s %8s %6s" % ("function", "cycles", "instr"))
    for sym, c in per.most_common(a.top):
        print("%-40s %8d %6d" % (sym, c, count[sym]))
    print("%-40s %8d %6d" % ("TOTAL (+1 interrupt response cycle)", total,
                              sum(count.values())))


if __name__ == "__main__":
    main()
