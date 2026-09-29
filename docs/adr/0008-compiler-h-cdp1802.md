# 0008 — Common-code change: select the 16-bit memory model for the CDP1802 in compiler.h

Status: Proposed (agent) — common-code change, needs Alan's acceptance (CONTRACT §5.10)
Date: 2026-09-29
Step: step-04
NuttX commit: `f3ab8a0244` "include/nuttx/compiler.h: select the 16-bit memory model for the CDP1802"

## Context

NuttX chooses its memory model per compiler in `include/nuttx/compiler.h`:
`CONFIG_SMALL_MEMORY` (16-bit `SIZE_MAX`/`SSIZE_MAX`), `CONFIG_LONG_IS_NOT_INT`
and `CONFIG_PTR_IS_NOT_INT`, with branches for `__m32c__`, `__AVR__`,
`__mc68hc1x__` and others. Without a CDP1802 branch the generic "32-bit"
defaults apply, and common code truncates 32-bit constants into the 16-bit
`size_t`. Measured: 5 `-Woverflow` warnings (`lib_gets.c`, `lib_rawmemchr.c`,
`lib_mbsnrtowcs.c`, `lib_mbsrtowcs.c`, `lib_wcsrtombs.c`).

## Options considered

1. Add a `#elif defined(__CDP1802__)` branch (17 lines, the same pattern as
   m32c/68HC1x).
2. Define these symbols from `arch/cosmac` instead. That is not possible:
   `compiler.h` is included before any arch header and would `#undef` them.
3. Leave the warnings. That hides real truncation of `SIZE_MAX`.

## Decision

Option 1, in its own commit. `__CDP1802__` is predefined by mikpe's GCC
(`cdp1802-elf-gcc -dM -E`).

## Consequences

- 0 warnings in the whole common-code build.
- It is the port's only common-code change so far, and an obvious upstream
  candidate (same shape as the existing branches).

## How to revisit

If NuttX moves the memory-model selection into Kconfig, move the setting to
`arch/cosmac/Kconfig`.
