#!/usr/bin/env python3
# scripts/typing-test.py <nuttx.elf> [--commands N] [--seed S] [--sim SIM]
#
# Types NSH commands into sim1802 one character at a time, with random
# pauses (0-30 ms), as a person at a terminal would, and waits for each
# command's answer.  A console input interrupt lost in the simulator makes
# NSH stop answering: this fails with the number of the command that got
# no answer.  (Tests that pipe whole lines at once never hit that window.)
import argparse
import os
import random
import select
import subprocess
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("elf")
ap.add_argument("--commands", type=int, default=40)
ap.add_argument("--seed", type=int, default=1802)
a = ap.parse_args()
rnd = random.Random(a.seed)
here = os.path.dirname(os.path.abspath(__file__))
p = subprocess.Popen([os.path.join(here, "run.sh"), a.elf],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, env=dict(os.environ,
                                                        RUN_TIMEOUT="0"))
buf = b""


def wait_for(token, timeout):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        if token in buf:
            buf = buf[buf.index(token) + len(token):]
            return True
        r, _, _ = select.select([p.stdout], [], [], 0.2)
        if r:
            data = os.read(p.stdout.fileno(), 4096)
            if not data:
                return False
            buf += data
    return False


if not wait_for(b"nsh> ", 30):
    print("FAIL: no prompt")
    p.kill()
    sys.exit(1)
cmds = ["uptime", "help", "free", "ps"]
for i in range(a.commands):
    cmd = cmds[i % len(cmds)]
    for ch in cmd + "\n":
        p.stdin.write(ch.encode())
        p.stdin.flush()
        time.sleep(rnd.uniform(0, 0.03))
    if not wait_for(b"nsh> ", 20):
        print("FAIL: command %d (%s) got no answer" % (i + 1, cmd))
        p.kill()
        sys.exit(1)
p.stdin.write(b"poweroff\n")
p.stdin.flush()
p.wait(timeout=30)
print("ok: %d commands typed one character at a time, all answered"
      % a.commands)
