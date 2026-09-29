#!/usr/bin/env python3
# scripts/merge-config.py <.config> <fragment> — set every symbol that the
# fragment mentions ("CONFIG_X=..." or "# CONFIG_X is not set") in .config,
# replacing an existing line for that symbol or appending a new one.  Run
# "make olddefconfig" afterwards to resolve dependencies.
import re
import sys

cfg, frag = sys.argv[1], sys.argv[2]
sym = re.compile(r"^(?:# )?(CONFIG_\w+)(?:=| is not set)")
want = {}
for line in open(frag):
    m = sym.match(line.strip())
    if m:
        want[m.group(1)] = line.strip()
out, seen = [], set()
for line in open(cfg):
    m = sym.match(line.strip())
    if m and m.group(1) in want:
        out.append(want[m.group(1)] + "\n")
        seen.add(m.group(1))
    else:
        out.append(line)
out += [v + "\n" for k, v in want.items() if k not in seen]
open(cfg, "w").writelines(out)
