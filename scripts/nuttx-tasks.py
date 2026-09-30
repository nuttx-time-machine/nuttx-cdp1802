#!/usr/bin/env python3
# scripts/nuttx-tasks.py <nuttx.elf> <memory dump> [--nuttx DIR]
#
# Post-mortem task list from a sim1802 memory image (sim1802 --dump FILE):
# walks NuttX's PID hash and prints, for every thread, its state, priority,
# preemption lock count, what it waits on (resolved to a symbol) and the
# PC in its saved register frame (resolved in the thread's own bank).
#
# The struct tcb_s offsets depend on the configuration, so they are
# computed by compiling a small probe against the NuttX tree, which must be
# configured with the same configuration as the image (tools/configure.sh
# and "make context"; scripts/build.sh leaves the tree in that state).
import argparse
import bisect
import os
import re
import struct
import subprocess
import tempfile

TARGET = "cdp1802-unknown-elf"
FIELDS = ["pid", "task_state", "sched_priority", "lockcount", "waitobj",
          "xcp.regs", "xcp.bankstate"]
PROBE = """#include <nuttx/config.h>
#include <stddef.h>
#include <nuttx/sched.h>
const unsigned int g_off[] = { %s, sizeof(tstate_t) };
"""
STATES = ["INVALID", "PENDING", "READYTORUN", "RUNNING", "INACTIVE",
          "WAIT_SEM", "WAIT_SIG"]


def offsets(nuttx):
    fields = [f for f in FIELDS
              if f != "xcp.bankstate" or banking(nuttx)]
    src = PROBE % ", ".join("offsetof(struct tcb_s, %s)" % f for f in fields)
    with tempfile.TemporaryDirectory() as d:
        c, o = os.path.join(d, "p.c"), os.path.join(d, "p.o")
        open(c, "w").write(src)
        inc = os.path.join(nuttx, "include")
        subprocess.run([TARGET + "-gcc", "-Os", "-march=1802", "-isystem", inc,
                        "-D__NuttX__", "-D__KERNEL__", "-c", "-o", o, c],
                       check=True)
        dump = subprocess.run([TARGET + "-objdump", "-s", "-j", ".rodata", o],
                              check=True, capture_output=True,
                              text=True).stdout
    data = bytes.fromhex("".join(
        "".join(l.split()[1:5]) for l in dump.splitlines()
        if re.match(r"^ [0-9a-f]{4} ", l)))
    vals = struct.unpack(">%dH" % (len(fields) + 1), data[:2 * (len(fields) + 1)])
    off = dict(zip(fields, vals))
    off["state_size"] = vals[-1]
    return off


def banking(nuttx):
    try:
        return "CONFIG_COSMAC_BANKING=y" in open(os.path.join(nuttx, ".config")).read()
    except OSError:
        return False


def symbols(elf):
    out = subprocess.run([TARGET + "-readelf", "-SsW", elf], check=True,
                         capture_output=True, text=True).stdout
    secbank = {m.group(1): int(m.group(2))
               for m in re.finditer(r"\[\s*(\d+)\] \.bank(\d+) ", out)}
    glob, fixed, banks = {}, [], {}
    for line in out.splitlines():
        if not re.match(r"^\s*\d+:\s+[0-9a-f]{8}\s", line):
            continue  # not a symbol table row
        f = line.split()
        if len(f) < 8:
            continue
        addr = int(f[1], 16)
        glob.setdefault(f[7], addr)
        if not f[6].isdigit():
            continue  # absolute or undefined
        if f[3] in ("FUNC", "NOTYPE", "OBJECT"):
            if f[6] in secbank:
                banks.setdefault(secbank[f[6]], []).append((addr, f[7]))
            elif addr < 0x8000 or addr >= 0xC000:
                fixed.append((addr, f[7]))
    fixed.sort()
    for v in banks.values():
        v.sort()
    return glob, fixed, banks


def resolve(addr, bank, fixed, banks):
    table = banks.get(bank, []) if 0x8000 <= addr < 0xC000 else fixed
    i = bisect.bisect_right([a for a, _ in table], addr) - 1
    return "%s+%x" % (table[i][1], addr - table[i][0]) if i >= 0 else "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("dump")
    ap.add_argument("--nuttx", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "nuttx"))
    a = ap.parse_args()
    mem = open(a.dump, "rb").read()
    off = offsets(a.nuttx)
    glob, fixed, banks = symbols(a.elf)

    def word(x):
        return (mem[x] << 8) | mem[x + 1]

    pidhash, n = word(glob["g_pidhash"]), word(glob["g_npidhash"])
    for i in range(n):
        t = word(pidhash + 2 * i)
        if not t:
            continue
        s = off["task_state"] + off["state_size"] - 1
        state = mem[t + s]
        regs = word(t + off["xcp.regs"])
        bank = mem[t + off["xcp.bankstate"] + 3] if "xcp.bankstate" in off else 0
        pc = word(regs + 25) if regs else 0
        waitobj = word(t + off["waitobj"])
        heap = glob.get("_ebss", 0x10000) <= waitobj
        print("pid %-3d %-10s prio %-3d lock %d  wait %04x %-28s pc %s" % (
            word(t + off["pid"]),
            STATES[state] if state < len(STATES) else str(state),
            mem[t + off["sched_priority"]],
            word(t + off["lockcount"]),
            waitobj, "(heap)" if heap else
            "(%s)" % resolve(waitobj, 0, fixed, banks) if waitobj else "",
            resolve(pc, bank, fixed, banks) if regs else "-"))


if __name__ == "__main__":
    main()
