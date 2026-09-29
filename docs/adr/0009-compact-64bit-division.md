# 0009 — Provide compact 64-bit division helpers in arch/cosmac

Status: Proposed (agent)
Date: 2026-09-29
Step: step-04
NuttX commit: `c1de4627e5` "arch/cosmac: add compact 64-bit division helpers"

## Context

`time_t` and `clock_t` are unconditionally `int64_t` in NuttX at the pinned
commit, so the kernel divides 64-bit values. libgcc's `__divdi3`, `__udivdi3`
and `__umoddi3` (GCC's generic C `__udivmoddi4`, inlined into each)
compile to 10 926, 10 543 and 10 876 bytes on the CDP1802: 34 KB of the
first 91 KB image.

## Options considered

1. Keep libgcc's routines. Unaffordable.
2. Patch libgcc in the toolchain. That needs an ADR plus Alan's approval, and
   it would take effect only after a toolchain rebuild.
3. Provide replacements in `arch/cosmac` (Apache-2.0, our code). The arch
   library precedes libgcc on the link line, so its definitions win.
4. Hand-written assembly. Smallest, but harder to verify. Possible later.

## Decision

Option 3: `arch/cosmac/src/common/cosmac_div64.c`. One shared bit-at-a-time
loop (`udivmod64`), one shared negation helper, and a fast path through
libgcc's hand-written 32-bit `__udivsi3`/`__umodsi3` when both operands fit
in 32 bits. Verified against 492 host-computed vectors
(`toolchain/tests/div64`, `scripts/test-step-04.sh`).

## Consequences

- libgcc's contribution drops from 34 347 to 1 900 bytes; the image from
  90 714 to 62 016 bytes (-Os, before the ADR 0010 workaround).
- Full 64-bit divisions take 64 loop iterations and are slow. The cycle
  cost is measured in Step 07/08.
- The helpers are the case that exposed toolchain issue 0002.

## How to revisit

If libgcc gains a compact implementation, drop the file. If division shows
up in timing measurements, rewrite `udivmod64` in assembly.
