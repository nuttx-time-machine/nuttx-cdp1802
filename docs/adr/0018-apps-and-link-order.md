# 0018 — Changes outside arch/board: ostest on 16-bit int, libgcc after the libraries

Status: Proposed (agent)
Date: 2026-09-29
Step: step-09

## Context

Building `apps/testing/ostest` for the CDP1802 produced compiler warnings
that are real bugs on any target where `int` is 16 bits:

- `usleep(200 * 1000)` is 3 392 µs, not 200 ms;
- `usleep(500 * 1000)` is negative;
- the `tv_nsec` range check compared against 16 960 instead of 10⁹;
- `%d` was used for a `long`;
- pointers were cast to and from `wdparm_t` (`uint32_t`) without
  `uintptr_t`.

Separately, the port's link placed libgcc inside the library group. A
routine that the architecture replaces (`__udivdi3`, ADR 0009) then came
from libgcc whenever its first reference appeared in a library scanned
after `libarch` (ostest's spinlock test): 10.5 KB of fixed ROM.

## Decision

1. One apps commit ("testing/ostest: fix time constants and casts for
   16-bit int targets"):
   - long constants (`200 * 1000L`, `1000L * 1000 * 1000`);
   - `%ld` for the `long`;
   - `(wdparm_t)(uintptr_t)` casts and `(wdparm_t)0`.

   There is no behaviour change on 32-bit targets. checkpatch still
   reports style issues in these files, but on unchanged, pre-existing
   lines (the nxstyle findings before and after the commit are
   identical).
2. `arch/cosmac/src/Makefile`: `$(EXTRA_LIBS)` (libgcc) after
   `--end-group`. This is the port's own file, so it is not a common-code
   change, but it changes link semantics and is recorded here.

## Consequences

- ostest builds without warnings on the CDP1802.
- libgcc only supplies what no NuttX library defines. If a libgcc member
  ever needs a NuttX symbol that nothing else pulled in, the link fails
  loudly; it does not silently choose.

## How to revisit

The apps commit is a candidate for upstream (Step 11 report), since AVR
has 16-bit `int` too.
