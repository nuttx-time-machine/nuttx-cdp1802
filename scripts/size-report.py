#!/usr/bin/env python3
# scripts/size-report.py <nuttx.map> [--top N] [--csv FILE] [--markdown]
#
# Size breakdown of a NuttX link from its GNU ld map file (CONFIG_DEBUG_LINK_MAP,
# -Map).  Works even when the link failed because a region overflowed: the
# linker still writes the map with the full layout.
#
# Every input section is attributed to the library it came from (libsched.a,
# libc.a, libgcc.a, ...; plain object files are grouped as "objects") and to
# a kind: text (.text*), rodata (.rodata*), data (.data*), bss (.bss*,
# COMMON).  With -ffunction-sections/-fdata-sections each function and object
# is its own input section, so the largest input sections are the largest
# symbols.
#
# Used for the size budget (docs/size-budget.md) and the Step 04 feasibility
# report; the same script reads ARM and AVR maps for comparisons.

import argparse
import collections
import os
import re
import sys

KINDS = ("text", "rodata", "data", "bss")

# " .text.name  0x00001234  0x56 /path/lib.a(obj.o)"  (one line)
ONE = re.compile(r"^ (\.\S+|COMMON)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+(\S.*)$")
# " .text.a_very_long_name" followed by
# "                0x00001234       0x56 /path/lib.a(obj.o)"
NAME_ONLY = re.compile(r"^ (\.\S+|COMMON)\s*$")
CONT = re.compile(r"^\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+(\S.*)$")
# output section header: ".text  0x00000000  0x16225"
OUTSEC = re.compile(r"^(\.\S+)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)")


def kind_of(secname, outsec):
    s = secname
    if re.match(r"\.bank\d+\.text", s):     # code banking (ADR 0013)
        return "text"
    if s.startswith(".rodata") or s.startswith(".srodata"):
        return "rodata"
    if s.startswith(".text"):
        return "text"
    if s.startswith(".data") or s.startswith(".sdata") or s.startswith(".init_array"):
        return "data"
    if s.startswith(".bss") or s.startswith(".sbss") or s == "COMMON":
        return "bss"
    # fall back to the output section it was placed in
    return {".text": "text", ".data": "data", ".bss": "bss"}.get(outsec)


def origin(path):
    """('libsched.a', 'sched_foo.o') or ('objects', 'foo.o')."""
    m = re.match(r"(.*)\((.*)\)$", path.strip())
    if m:
        return os.path.basename(m.group(1)), m.group(2)
    return "objects", os.path.basename(path.strip())


def parse(mapfile):
    entries = []            # (kind, lib, obj, secname, size)
    outsec = None
    pending = None
    in_memmap = False
    with open(mapfile, errors="replace") as fp:
        for line in fp:
            line = line.rstrip("\n")
            if line.startswith("Linker script and memory map"):
                in_memmap = True
                continue
            if not in_memmap:
                continue
            if line.startswith("/DISCARD/"):
                outsec = "/DISCARD/"
                continue
            m = OUTSEC.match(line)
            if m and not line.startswith(" "):
                outsec = m.group(1)
                pending = None
                continue
            if outsec in (None, "/DISCARD/") or outsec.startswith(".debug") or \
               outsec.startswith(".stab") or outsec == ".comment":
                continue
            if pending is not None:
                c = CONT.match(line)
                pending_name = pending
                pending = None
                if c:
                    size = int(c.group(2), 16)
                    add(entries, pending_name, outsec, c.group(3), size)
                    continue
            m = ONE.match(line)
            if m:
                add(entries, m.group(1), outsec, m.group(4), int(m.group(3), 16))
                continue
            m = NAME_ONLY.match(line)
            if m:
                pending = m.group(1)
    return entries


def add(entries, secname, outsec, path, size):
    if size == 0 or path.startswith("load address") or path.startswith("0x"):
        return
    k = kind_of(secname, outsec)
    if k is None:
        return
    lib, obj = origin(path)
    entries.append((k, lib, obj, secname, size))


def symbol_of(secname):
    secname = re.sub(r"^\.bank\d+", "", secname)
    parts = secname.split(".", 2)
    return parts[2] if len(parts) > 2 else secname


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--csv")
    args = ap.parse_args()

    entries = parse(args.map)
    per_lib = collections.defaultdict(lambda: dict.fromkeys(KINDS, 0))
    totals = dict.fromkeys(KINDS, 0)
    for k, lib, obj, sec, size in entries:
        per_lib[lib][k] += size
        totals[k] += size

    rom = totals["text"] + totals["rodata"] + totals["data"]
    ram = totals["data"] + totals["bss"]
    print("%-18s %8s %8s %6s %6s %8s" % ("library", "text", "rodata", "data", "bss", "ROM"))
    for lib, v in sorted(per_lib.items(), key=lambda kv: -(kv[1]["text"] + kv[1]["rodata"])):
        print("%-18s %8d %8d %6d %6d %8d" % (lib, v["text"], v["rodata"], v["data"],
              v["bss"], v["text"] + v["rodata"] + v["data"]))
    print("%-18s %8d %8d %6d %6d %8d" % ("TOTAL", totals["text"], totals["rodata"],
          totals["data"], totals["bss"], rom))
    print("ROM (text+rodata+data) = %d bytes, RAM (data+bss, static) = %d bytes" % (rom, ram))
    banks = collections.Counter()
    for k, lib, obj, sec, size in entries:
        m = re.match(r"\.bank(\d+)\.text", sec)
        if m:
            banks[int(m.group(1))] += size
    if banks:
        print("banked: fixed ROM = %d bytes, banks = %d bytes (%s)" % (
            rom - sum(banks.values()), sum(banks.values()),
            ", ".join("bank %d: %d" % kv for kv in sorted(banks.items()))))

    print("\nlargest %d input sections (functions/objects):" % args.top)
    for k, lib, obj, sec, size in sorted(entries, key=lambda e: -e[4])[:args.top]:
        print("%7d  %-6s %-28s %s(%s)" % (size, k, symbol_of(sec)[:28], lib, obj))

    if args.csv:
        with open(args.csv, "w") as fp:
            fp.write("library,text,rodata,data,bss\n")
            for lib, v in sorted(per_lib.items()):
                fp.write("%s,%d,%d,%d,%d\n" % (lib, v["text"], v["rodata"], v["data"], v["bss"]))


if __name__ == "__main__":
    main()
