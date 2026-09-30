# 0022 — NSH on the HWB profile: procfs, bank return stack depth, overflow handling

Status: Proposed (agent). Step 10 is a GATE; Alan decides.
Date: 2026-09-29
Step: step-10

## Context

The contract asks for an interactive NSH with `help`, `ps`, `free` and
`uptime`, or an analysis of why it does not fit. The code sizes decide
which it is:
- **SIM64** has no banking, and NuttX with NSH is about 126 KB of code, so
  it cannot fit in 64 KiB. This follows from Step 04's measurements and
  the Step 10 build below.
- **HWB** (ADR 0013, amendment A5) has 32 KiB of fixed ROM plus 16 KiB
  banks, and with the placement tool v2 everything except the switching
  and tick paths is banked.

Among the commands, `ps` and `free` read procfs (`/proc/<pid>/…` and
`/proc/meminfo`). `uptime` uses `sysinfo()`.

The first `ps` run crashed the CPU (a deadlock trap: IDL with IE=0 in RAM).
The cause was a far call that overflowed the thread's bank return stack
(BRS; depth 16). `cosmac_brs_overflow()` then called `_alert()`, which is
banked, so the overflow handler's own far call overflowed again. The
recursion ran the stack below RAM, through `.bss`. A dump taken with the
TCBs still intact showed the NSH thread at 18 nested far calls.

## Decision

1. A configuration `sim1802:nsh` on HWB with 16 banks, `DEFAULT_SMALL`,
   and only the four required commands plus `poweroff` (so tests can
   stop), `?`/`help` and `quit`. It uses the serial console with
   readline, procfs with process and meminfo entries, a 1536-byte NSH
   stack and 12-character task names.
2. The board mounts procfs at `/proc` in `board_late_initialize()` when
   `CONFIG_FS_PROCFS` is set, which is the usual board bringup pattern.
3. `CONFIG_COSMAC_BRS_DEPTH=24` in this configuration: 18 measured plus
   margin, at 3 bytes of TCB RAM per entry. The Kconfig default stays 16,
   which ostest needs.
4. `cosmac_brs_overflow()` switches to the static exit BRS (the one
   `up_exit()` uses) before reporting, so an overflow ends in a PANIC.
   With `BOARD_RESET_ON_ASSERT` that is exit status 3, instead of memory
   corruption.
5. `scripts/nuttx-tasks.py` reports each thread's BRS high-water mark from
   a memory dump. This is how the depth was measured, and how any new
   configuration can size its depth.

## Consequences

- NSH works on HWB. In machine cycles, from `scripts/test-step-10.sh`: boot
  to prompt 2.5 M, `help` 1.5 M, `ps` 9.6 M, `free` 4.5 M, `uptime` 1.9 M.
  At the nominal 4 MHz (500 000 cycles/s) that is 5 s, 3 s, 19 s, 9 s and
  4 s. It is interactive, but slow.
- Fixed ROM is 10.8 KB of 32 KiB, and 7.8 banks (126 KB) are used. RAM:
  the heap has 14.4 KB, of which 3.6 KB is used at the prompt.
- Every thread's TCB is 24 bytes larger than with the default depth.
- The BRS depth is a per-configuration sizing parameter, like a stack
  size. The overflow is now fail-stop, but it is still detected only at
  run time.

## How to revisit

A static call-graph analysis over the placement tool's reference table
could compute the worst-case far-call depth at link time, as stack-usage
tools do for stacks.
