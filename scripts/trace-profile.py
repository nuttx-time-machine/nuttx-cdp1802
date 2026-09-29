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
#
# Banked images (ADR 0013): every bank has the same addresses, so the
# simulator's symbol names are ambiguous in the window 0x8000-0xBFFF.  The
# sim1802 fork appends " [bN]" (the selected bank) to those trace lines;
# with --elf, such addresses are resolved against bank N's symbols.
#
# --whole: profile every instruction of the trace instead of one interrupt.
# --stop SYM: end the region at the next execution of SYM+0 instead.
import argparse
import bisect
import collections
import re
import subprocess
import sys

LINE = re.compile(
    r"^@ ([^+ ]+)(?:\+([0-9a-f]+))? \(([0-9a-f]{4})\) op ([0-9a-f]{2})"
    r"(?: \[b(\d+)\])?")


def bank_symbols(elf):
    """{bank: (sorted addresses, names)} for the .bankN sections of elf."""
    out = subprocess.run(["cdp1802-unknown-elf-readelf", "-SsW", elf],
                         check=True, capture_output=True, text=True).stdout
    secbank = {}
    for m in re.finditer(r"\[\s*(\d+)\] \.bank(\d+) ", out):
        secbank[m.group(1)] = int(m.group(2))
    syms = collections.defaultdict(list)
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 8 and f[3] in ("FUNC", "NOTYPE") and f[6] in secbank:
            syms[secbank[f[6]]].append((int(f[1], 16), f[7]))
    table = {}
    for bank, lst in syms.items():
        lst.sort()
        table[bank] = ([a for a, _ in lst], [n for _, n in lst])
    return table


def resolve(table, bank, addr, default):
    if bank is None or bank not in table:
        return default
    addrs, names = table[bank]
    i = bisect.bisect_right(addrs, addr) - 1
    return "%s[b%d]" % (names[i], bank) if i >= 0 else default


def cycles(op):
    return 3 if 0xC0 <= op <= 0xCF else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--start", default="cosmac_irq_entry")
    ap.add_argument("--nth", type=int, default=2)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--elf", help="image, to name banked code")
    ap.add_argument("--whole", action="store_true")
    ap.add_argument("--stop", help="end the region at the next SYM+0")
    a = ap.parse_args()
    table = bank_symbols(a.elf) if a.elf else {}
    seen = 0
    active = a.whole
    per = collections.Counter()
    count = collections.Counter()
    total = 0
    prev_op = None
    src = sys.stdin if a.trace == "-" else open(a.trace, errors="replace")
    for line in src:
        m = LINE.match(line)
        if not m:
            continue
        sym, off, op = m.group(1), int(m.group(2) or "0", 16), int(m.group(4), 16)
        if m.group(5) is not None:
            bank = int(m.group(5))
            sym = resolve(table, bank, int(m.group(3), 16), sym)
        if not active:
            if sym == a.start and off == 0:
                seen += 1
                active = seen == a.nth
            if not active:
                continue
        elif a.stop and sym == a.stop and off == 0:
            break
        elif (not a.whole and not a.stop and prev_op in (0x70, 0x71)
              and prev_sym.startswith("cosmac_irq")):
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
