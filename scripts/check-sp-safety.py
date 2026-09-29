#!/usr/bin/env python3
# scripts/check-sp-safety.py <elf> — static check that no instruction boundary
# in <elf> can leave the stack pointer R2 above the live stack top
# (toolchain issue 0001, ADR 0007).
#
# Every instruction that writes R2 atomically (INC/DEC 2, STXD, LDXA, LDA 2,
# IRX, OUT, RET, DIS, the 1804 register ops) is safe by construction.  The
# CDP1802 can only replace R2 by writing its two bytes separately (PLO 2 and
# PHI 2); every *composite* update, i.e. two or more such byte writes in one
# straight-line run, must match one of the sequences proven safe in ADR 0007.
# A single byte write on its own is a complete (atomic) update.
#
# The script decodes the machine code itself instead of parsing objdump, so
# that it can follow the NCRT convention (SEP 4 is followed by a 2-byte
# callee address) and only look inside function symbols (read-only data in
# .text is never mistaken for code).
#
# --allow SYMBOL (repeatable) exempts a function that provably runs with
# interrupts disabled, e.g. reset code that sets up the first stack before
# IE is ever set.  Every use must be justified where it is passed.
#
# Exit status: 0 if every composite update is safe, 1 otherwise.

import re
import subprocess
import sys

TARGET = "cdp1802-unknown-elf"

# ---------------------------------------------------------------- decoder
IMM = {0x7C: "adci", 0x7D: "sdbi", 0x7F: "smbi", 0xF8: "ldi", 0xF9: "ori",
       0xFA: "ani", 0xFB: "xri", 0xFC: "adi", 0xFD: "sdi", 0xFF: "smi"}
NIBBLE = {0x0: "ldn", 0x1: "inc", 0x2: "dec", 0x4: "lda", 0x5: "str",
          0x8: "glo", 0x9: "ghi", 0xA: "plo", 0xB: "phi", 0xD: "sep", 0xE: "sex"}
BRANCH_OPS = set(range(0x30, 0x40)) | {0xC0, 0xC1, 0xC2, 0xC3, 0xC8, 0xC9,
                                        0xCA, 0xCB}
SKIP_OPS = {0xC4, 0xC5, 0xC6, 0xC7, 0xCC, 0xCD, 0xCE, 0xCF}


def decode(code, pc):
    """Decode one instruction at code[pc]: (length, text, is_control)."""
    op = code[pc]
    hi, n = op >> 4, op & 0xF
    if op == 0x68:                          # CDP1804 prefix
        op2 = code[pc + 1] if pc + 1 < len(code) else 0
        h2, n2 = op2 >> 4, op2 & 0xF
        if h2 in (0x2, 0xC):                # DBNZ, RLDI: + 2 bytes
            return 4, "68%02x" % op2, h2 == 0x2
        if op2 in (0x3E, 0x3F):             # BCI, BXI: + 1 byte
            return 3, "68%02x" % op2, True
        return 2, "68%02x" % op2, h2 in (0x8, 0x9)   # SCAL/SRET transfer
    if op in IMM:
        return 2, "%s 0x%02x" % (IMM[op], code[pc + 1]), False
    if op in BRANCH_OPS:
        length = 2 if hi == 0x3 else 3
        return length, "br%02x" % op, True
    if op in SKIP_OPS:
        return 1, "skip%02x" % op, True
    if op == 0x00:
        return 1, "idl", False
    if hi == 0xD:
        if n == 4:                          # NCRT call: SEP 4; .hword callee
            return 3, "call", True
        return 1, "sep %d" % n, True
    if hi in NIBBLE:
        return 1, "%s %d" % (NIBBLE[hi], n), False
    return 1, "op%02x" % op, op in (0x70, 0x71)   # RET/DIS change P


# ---------------------------------------------------------------- patterns
# Safe composite updates (ADR 0007).  Tokens: literal text, or
#   "N"  any register number (all "N" in one pattern must be equal),
#   "X"  any immediate (all "X" in one pattern must be equal),
#   "*"  any immediate.
SAFE = {
    "add 0<=V<256 (low byte first, carry 0)":
        ["glo 2", "adi *", "plo 2", "ghi 2", "adci 0x00", "phi 2"],
    "add V>=256 or V<0 (high byte first, then low)":
        ["ghi 2", "adi *", "phi 2",
         "glo 2", "adi *", "plo 2", "ghi 2", "adci 0x00", "phi 2"],
    "SP <- FP in epilogue (SP <= FP, low byte first)":
        ["glo 15", "plo 2", "ghi 15", "phi 2"],
    "SP <- register (one page below first)":
        ["ghi N", "smi 0x01", "phi 2", "glo N", "plo 2", "ghi N", "phi 2"],
    "SP <- constant (one page below first)":
        ["ldi X", "smi 0x01", "phi 2", "ldi *", "plo 2", "ldi X", "phi 2"],
    "SP <- memory, plain or post-dec (one page below first)":
        ["lda N", "smi 0x01", "phi 2", "ldn N", "plo 2", "dec N", "ldn N",
         "phi 2"],
    "SP <- memory, post-inc (one page below first)":
        ["lda N", "smi 0x01", "phi 2", "lda N", "plo 2", "dec N", "dec N",
         "lda N", "phi 2"],
}


def match(pattern, instrs):
    if len(pattern) != len(instrs):
        return False
    binding = {}
    for p, (_, text) in zip(pattern, instrs):
        pm, po = p.split(" ", 1) if " " in p else (p, None)
        tm, to = text.split(" ", 1) if " " in text else (text, None)
        if pm != tm:
            return False
        if po is None:
            continue
        if po == "*":
            continue
        if po in ("N", "X"):
            if binding.setdefault(po, to) != to:
                return False
            if po == "N" and to == "2":
                return False                # loading SP through itself
            continue
        if po != to:
            return False
    return True


def is_r2_byte_write(text):
    return text in ("plo 2", "phi 2")


# ---------------------------------------------------------------- ELF access
def run(tool, *args):
    return subprocess.run([f"{TARGET}-{tool}", *args], check=True,
                          capture_output=True, text=True).stdout


def functions(elf):
    """(name, addr, size) of every sized function symbol."""
    out = run("readelf", "-sW", elf)
    funcs = []
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 8 and f[3] == "FUNC" and f[6] != "UND":
            size = int(f[2], 0)
            if size:
                funcs.append((f[7], int(f[1], 16), size))
    return sorted(set(funcs), key=lambda x: x[1])


def sections(elf):
    """Contents of every ALLOC+PROGBITS section: [(vma, bytes)].  Read from
    the ELF file directly (ELF32, big-endian), so addresses are exact."""
    import struct
    with open(elf, "rb") as fp:
        d = fp.read()
    assert d[:4] == b"\x7fELF" and d[4] == 1 and d[5] == 2, "not ELF32 big-endian"
    shoff, = struct.unpack_from(">I", d, 0x20)
    shentsize, shnum = struct.unpack_from(">HH", d, 0x2E)
    out = []
    for k in range(shnum):
        (_n, typ, flags, addr, off, size) = struct.unpack_from(
            ">IIIIII", d, shoff + k * shentsize)
        if typ == 1 and flags & 0x2 and size:          # PROGBITS, SHF_ALLOC
            out.append((addr, d[off:off + size]))
    return out


def bytes_at(secs, addr, size):
    for vma, data in secs:
        if vma <= addr and addr + size <= vma + len(data):
            return data[addr - vma: addr - vma + size]
    raise SystemExit("check-sp-safety: 0x%04x+%d is not in any section" % (addr, size))


def check(elf, allow=()):
    funcs = [f for f in functions(elf) if f[0] not in allow]
    secs = sections(elf)
    problems, composites, singles = [], 0, 0
    global desync
    desync = []
    for name, addr, size in funcs:
        code = bytes_at(secs, addr, size) + b"\0\0\0"
        pc, instrs = 0, []
        while pc < size:
            length, text, control = decode(code, pc)
            instrs.append((addr + pc, text, control))
            pc += length
        if pc != size:
            desync.append("%s (0x%04x, %d bytes): decoding ends %d bytes past "
                          "the symbol size" % (name, addr, size, pc - size))
        # straight-line runs, split at control transfers
        run_ = []
        for ins in instrs + [(None, "end", True)]:
            if ins[2]:
                composites, singles = scan_run(name, run_, problems,
                                               composites, singles)
                run_ = []
            else:
                run_.append(ins[:2])
    return funcs, problems, composites, singles


STATS = {}


def first_write(pattern):
    return next(k for k, p in enumerate(pattern) if is_r2_byte_write(p))


def scan_run(name, run_, problems, composites, singles):
    """Cover the R2 byte writes of one straight-line run, left to right, with
    safe patterns.  A write that no pattern explains is a complete update on
    its own only if no other R2 byte write follows within 6 instructions;
    otherwise the pair may be torn and is reported."""
    writes = [i for i, (_, t) in enumerate(run_) if is_r2_byte_write(t)]
    k = 0
    while k < len(writes):
        w = writes[k]
        covered_to = None
        for pname, pat in SAFE.items():
            start = w - first_write(pat)
            end = start + len(pat)
            if start >= 0 and end <= len(run_) and match(pat, run_[start:end]):
                covered_to = end
                STATS[pname] = STATS.get(pname, 0) + 1
                break
        if covered_to is not None:
            composites += 1
            while k < len(writes) and writes[k] < covered_to:
                k += 1
            continue
        if k + 1 < len(writes) and writes[k + 1] - w <= 6:
            lo = max(0, w - 4)
            seq = "; ".join(t for _, t in run_[lo:writes[k + 1] + 1])
            problems.append("%s @0x%04x: %s" % (name, run_[w][0], seq))
        else:
            singles += 1
        k += 1
    return composites, singles


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("--allow", action="append", default=[], metavar="SYMBOL",
                    help="skip a function that runs with interrupts disabled")
    a = ap.parse_args()
    funcs, problems, composites, singles = check(a.elf, set(a.allow))
    for name in a.allow:
        print("sp-safety: not checked (runs with IE=0): %s" % name)
    print("sp-safety: %d functions, %d composite R2 updates, %d single-byte "
          "R2 writes" % (len(funcs), composites, singles))
    for pname in SAFE:
        if STATS.get(pname):
            print("  %4d x %s" % (STATS[pname], pname))
    for d in desync:
        print("note: " + d)
    for p in problems:
        print("UNSAFE: " + p)
    if problems:
        print("sp-safety: FAIL (%d unsafe)" % len(problems))
        sys.exit(1)
    print("sp-safety: OK")


if __name__ == "__main__":
    main()
