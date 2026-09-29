# 0011 — Common-code change: opt-in 32-bit system time (CONFIG_SYSTEM_TIME32)

Status: Accepted (Alan chose option C at the Step 04 gate, 2026-09-29)
Date: 2026-09-29
Step: step-04 follow-up

## Context

NuttX made `time_t`/`clock_t` unconditionally 64-bit in `c6654b1106`
(2026-05-03, "remove CONFIG_SYSTEM_TIME64 and always use 64-bit time", Xiang
Xiao), reasoning that the 32-bit range (~497 days) is too small and that
"practically every modern target already enables it". On the CDP1802 64-bit
time costs about 13 KB of the 75 KB minimal image (journal step-04, B2 → B8).

## Options considered

1. Revert `c6654b1106`: 187 files, conflicts in five timer drivers, and
   `CONFIG_SYSTEM_TIME64=y` lines in every board defconfig. Rejected.
2. An opt-in option that changes only the type definitions
   (`include/sys/types.h`) and `CLOCK_MAX` (`include/limits.h`), default off.
3. Stay with 64-bit time.

## Decision

Option 2: `config SYSTEM_TIME32` in `sched/Kconfig` (default `n`),
enabled in `sim1802:minimal`. `time_t` and `clock_t` become `int32_t`.

## Consequences

- 13.2 KB saved (75 181 → 61 978 bytes) with 0 new warnings in the minimal
  configuration; other configurations may expose code that assumes 64-bit
  time. Each such case gets recorded, and fixed only if it matters.
- Range: the tick counter overflows after 2^31 ticks (about 248 days at
  100 Hz); `time_t` overflows in 2038. Acceptable for the simulator board and
  small real COSMAC systems. The limits are stated in the Kconfig help.
- Default `n`: no effect on any other architecture or board.
- An upstream discussion item: upstream deliberately removed the knob, so this
  may stay a local change.

## How to revisit

If the compiler becomes efficient with 64-bit arithmetic, or the code fits
without it (banking, ADR 0013), try disabling the option and compare.
