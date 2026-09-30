#!/usr/bin/env python3
# scripts/trace-callgraph.py <trace|-> --elf IMAGE [--start SYM] [--nth N]
#                            [--stop SYM] [--top N]
#
# Inclusive profile from a sim1802 instruction trace (sim1802 -t): cycles
# spent in each function *including* everything it calls, which
# trace-profile.py (self cycles only) cannot show.  The call stack is
# rebuilt from the trace:
# - a "sep 4" executed outside the call/return glue is a call; the first
#   instruction after the glue (cosmac_ncrt_call, __cosmac_farcall, ...)
#   is the callee, pushed on the stack (a banking stub and the banked body
#   it calls are two frames);
# - a "sep 5" outside the glue is a return, and so is the RET/DIS that
#   ends the interrupt exit path; the stack is popped down to the function
#   that execution lands in;
# - a jump to another function's first instruction (a sibling call) is
#   pushed like a call and popped by the same rule;
# - cosmac_irq_entry pushes "[interrupt]", so interrupts are charged to
#   themselves and to whatever they interrupted.
# If execution lands in a function that is not on the stack (a context
# switch), the stack restarts there.  Cycle counts per instruction are as
# in trace-profile.py.
import argparse
import collections
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location(
    "tp", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "trace-profile.py"))
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

GLUE = ("cosmac_ncrt_call", "cosmac_ncrt_call_exit", "cosmac_ncrt_ret",
        "cosmac_ncrt_ret_exit", "__cosmac_farcall", "__cosmac_farret",
        "__call_reg")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--elf", required=True)
    ap.add_argument("--start", help="begin at the Nth execution of SYM+0")
    ap.add_argument("--nth", type=int, default=1)
    ap.add_argument("--stop", help="end at the next execution of SYM+0")
    ap.add_argument("--top", type=int, default=40)
    a = ap.parse_args()
    table = tp.bank_symbols(a.elf)
    src = sys.stdin if a.trace == "-" else open(a.trace, errors="replace")

    incl = collections.Counter()
    self_ = collections.Counter()
    calls = collections.Counter()
    stack = []
    pending = None          # "call" or "ret"
    active = a.start is None
    seen = 0
    total = 0
    for line in src:
        m = tp.LINE.match(line)
        if not m:
            continue
        sym, off = m.group(1), int(m.group(2) or "0", 16)
        op = int(m.group(4), 16)
        if m.group(5) is not None:
            sym = tp.resolve(table, int(m.group(5)), int(m.group(3), 16), sym)
        if not active:
            if sym == a.start and off == 0:
                seen += 1
                active = seen == a.nth
            if not active:
                continue
            stack = [sym]
        elif a.stop and sym == a.stop and off == 0:
            break
        glue = sym in GLUE
        if sym == "cosmac_irq_entry" and off == 0:
            stack.append("[interrupt]")
            calls["[interrupt]"] += 1
        elif not glue and pending == "call":
            stack.append(sym)
            calls[sym] += 1
            pending = None
        elif not glue and pending == "ret":
            if sym in stack:
                while stack[-1] != sym:
                    stack.pop()
            else:
                stack = [sym]
            pending = None
        elif not glue and stack and sym != stack[-1] and off == 0:
            stack.append(sym)          # sibling call or fall-through
            calls[sym] += 1
        c = tp.cycles(op)
        total += c
        for f in set(stack):
            incl[f] += c
        self_[sym] += c
        if not glue:
            if op == 0xD4:
                pending = "call"
            elif op == 0xD5:
                pending = "ret"
        if op in (0x70, 0x71) and sym.startswith("cosmac_irq"):
            pending = "ret"
    print("%-40s %10s %6s %10s %7s" % ("function", "inclusive", "%", "self",
                                       "calls"))
    for f, c in incl.most_common(a.top):
        print("%-40s %10d %5.1f%% %10d %7d" % (f, c, 100.0 * c / total,
                                              self_[f], calls[f]))
    print("%-40s %10d" % ("TOTAL", total))
    print()
    print("%-40s %10s %6s" % ("self (top)", "cycles", "%"))
    for f, c in self_.most_common(a.top // 2):
        print("%-40s %10d %5.1f%%" % (f, c, 100.0 * c / total))


if __name__ == "__main__":
    main()
