# 0014 — Start-up: NCRT routines in the arch, idle stack after .bss, heap to the top of RAM

Status: Proposed (agent)
Date: 2026-09-29
Step: step-06

## Context

mikpe's GCC calls functions with `sep 4; .hword callee` and returns with
`sep 5` (docs/cdp1802/abi.md §4). Something must provide the routines at
R4/R5 before the first C call. mikpe's C library has its own copy in its
crt0, but NuttX does not link that library (ADR 0004). The reset code also
has to place the idle stack and the heap in RAM.

## Options considered

1. Link mikpe's crt0/NCRT object. Rejected: it pulls in the mikpe libc start-up,
   and nothing guarantees that it keeps R2 valid at every instruction
   (ADR 0006/0007).
2. **Write the routines in `arch/cosmac/src/common/cosmac_ncrt.S`**, from
   the ABI description and the RCA subroutine technique (MPM-201A
   pp. 54–64). Each keeps its exiting `sep 3` just before its entry, so no
   register needs reloading. Chosen.

Memory layout options: (a) the idle stack at the top of RAM with the heap
below it, or (b) **the idle stack right after `.bss`, and the heap from
there to 0xFFFF** (as the ARM ports do with `g_idle_topstack`). Chosen (b):
the heap then starts at a link-time constant, and in the banked profile
(ADR 0013) the top of RAM stays free if the bank return stack needs it.

## Decision

- `cosmac_ncrt_call` (16 instructions + the exit `sep 3`) and
  `cosmac_ncrt_ret` (7 + exit). They clobber D, preserve DF, and leave R2 at or below the live
  stack top at every instruction boundary.
- `__start`: `DIS` first (IE = 1 after reset, MPM p. 72), R2 :=
  `_ebss + CONFIG_IDLETHREAD_STACKSIZE - 1`, PC := R3. Then the .data copy,
  the .bss clear, R4/R5 set up, `cdp1802_boardinitialize()` and
  `nx_start()`.
- `g_idle_topstack` = `_ebss + CONFIG_IDLETHREAD_STACKSIZE`. The heap runs
  from there to 0xFFFF (`COSMAC_RAM_LAST`).
- `up_saveusercontext()` records a zeroed context until Step 08, because
  `_assert()` calls it.

## Consequences

- Each call costs 17 instructions (the routine plus its exit `sep 3`)
  and each return 8, on top of the caller's `sep`. These are measured in
  Step 08/performance work, not optimised now.
- `COSMAC_RAM_LAST` is 0xFFFF for SIM64, HW32 and HW48 (RAM always ends
  the address space). The banked profile must revisit it if the bank return
  stack is placed at the top.

## How to revisit

If the call overhead dominates the performance measurements, consider the
CDP1804/5 `SCAL`/`SRET` instructions (`-march=1804` builds, DS1805
pp. 12–13) as a chip-level alternative (this needs compiler support).
