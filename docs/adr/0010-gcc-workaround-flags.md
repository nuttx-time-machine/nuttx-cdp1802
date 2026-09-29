# 0010 — Work around toolchain issue 0002 with -fno-split-wide-types

Status: Proposed (agent)
Date: 2026-09-29
Step: step-04
NuttX commit: `02e3f7f0e9` "arch/cosmac: work around a CDP1802 GCC -Os wrong-code bug"

## Context

Toolchain issue 0002: mikpe's GCC generates wrong code at `-Os` for some
nested calls passing 64-bit values (a 12-line reproducer; 253 of 492
division vectors wrong). Of 35 `-fno-*` options tried, only
`-fno-split-wide-types` avoids it. `-O2` is also correct for the reproducer,
but it is no smaller, and `-O1` hangs the compiler (issue 0003).

## Options considered

1. `-Os -fno-split-wide-types`: correct for every known case; +21 % code
   (62 016 → 75 181 bytes).
2. `-O2`: correct for the reproducer; 75 197 bytes, and a slower compile.
3. `-Os` without workaround: smallest, but known to generate wrong code.
4. Patch GCC: needs root-causing first and Alan's approval.

## Decision

Option 1, through a clearly named variable in `Toolchain.defs`:
`COSMAC_GCC_WORKAROUNDS ?= -fno-split-wide-types`. Overriding it
(`make COSMAC_GCC_WORKAROUNDS=`) reproduces the unsafe build for
measurements.

## Consequences

- Correctness first: the default build is 75 KB, which decides the Step 04
  gate.
- The GCC torture suite does not detect issue 0002 at all, so there is **no
  proof that the flag avoids every instance**. This risk is reported at the
  Step 04 gate.
- libgcc and mikpe's libc are still built without the flag (by the GCC
  build). NuttX links only a few small libgcc members; the risk is recorded
  in issue 0002.

## How to revisit

When mikpe fixes issue 0002, remove the flag and re-measure. The Step 04
test notices this: it reports when the reproducer stops failing.
