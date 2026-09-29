# Architecture Decision Records

ADRs are numbered sequentially (`NNNN-title.md`) and never deleted. A superseded
ADR stays in place and is marked "Superseded by NNNN".

Every ADR uses this structure:

```
# NNNN — Title
Status: Proposed | Accepted | Superseded by NNNN
Date: YYYY-MM-DD
Step: step-NN

## Context
## Options considered
## Decision
## Consequences
## How to revisit
```

"Accepted" means Alan reviewed the ADR, or it was implicitly accepted when a
step tag that depends on it was not objected to. The agent writes new ADRs as
"Proposed (agent)".

| # | Title | Status |
|---|-------|--------|
| [0001](0001-naming.md) | Architecture, chip and board naming | Proposed (agent) |
| [0002](0002-toolchain-build.md) | Toolchain build method; mikpe libc for validation only | Proposed (agent); partially superseded by 0004 |
| [0003](0003-simulator-strategy.md) | Simulator strategy (timer, time base, console input) | Accepted (Alan) |
| [0004](0004-libc-independence.md) | NuttX uses only its own libc; libgcc built without target libc headers | Accepted |
| [0005](0005-sim1802-board.md) | sim1802 board: boots the raw ROM image like the real machine; SIM64 / HW32/32 profiles; devices | Accepted (Alan) |
| [0006](0006-register-convention.md) | Register convention: R0 free for DMA, R1 interrupt PC, R2 always a valid stack, R3 PC | Accepted (Alan) |
| [0007](0007-gcc-interrupt-safe-sp.md) | Patch GCC so that stack-pointer updates are interrupt-safe | Accepted (Alan) |
| [0008](0008-compiler-h-cdp1802.md) | Common code: 16-bit memory model for the CDP1802 in compiler.h | Proposed — needs Alan (common-code change) |
| [0009](0009-compact-64bit-division.md) | Compact 64-bit division helpers in arch/cosmac | Proposed (agent) |
| [0010](0010-gcc-workaround-flags.md) | Work around toolchain issue 0002 with -fno-split-wide-types | Proposed (agent) |
| [0011](0011-system-time32.md) | Common code: opt-in 32-bit system time (CONFIG_SYSTEM_TIME32) | Accepted (Alan, option C) |
| [0012](0012-profile-hw48.md) | Memory profile HW48/16 | Accepted (Alan) |
| [0013](0013-code-banking.md) | Code banking: fixed ROM + 16 KiB window, stubs, bank return stack | Approach accepted (option A); design proposed, implemented at step-06b |
| [0014](0014-startup-ncrt-memory.md) | Start-up: NCRT routines in the arch, idle stack after .bss, heap to the top of RAM | Proposed (agent) |
