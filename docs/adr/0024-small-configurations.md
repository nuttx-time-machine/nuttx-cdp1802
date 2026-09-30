# 0024 — Small configurations: minimal console driver, board-started NSH

Status: Proposed (agent)
Date: 2026-09-30
Step: after step-10 (Alan: "try to use CONFIG_DISABLE_ALL_SIGNALS … fit
inside 48KB")

## Context

Alan wants to know whether a flat 48/16 system can run NSH. Two items in
the smallest NSH had nothing to do with what NSH needs:
- NuttX's serial driver, with its dependencies, is about 16 KB on the
  CDP1802, although the simulator console needs no buffering, termios or
  flow control;
- the init task is started with `task_spawn()`, which links about 5 KB of
  spawn-attribute and scheduler-parameter code.

## Decision

- `CONFIG_SIM1802_CONSOLE`: a board driver for `/dev/console`, about
  400 bytes.
  - Writes go straight to the PUTCHAR command.
  - A read takes what input is there. With none, it enables the console
    input interrupt and sleeps on a semaphore that the interrupt posts,
    and the handler disables the interrupt again. At end of input, a read
    returns 0.
  - Input is echoed, because NSH's readline leaves echo to the terminal.

  The arch calls the board's `cosmac_serialinit()` when the board selects
  `CONFIG_COSMAC_BOARD_CONSOLE`.
- `CONFIG_SIM1802_START_NSH`: with `CONFIG_INIT_NONE`,
  `board_late_initialize()` starts `nsh_main()` with `task_create()`.
- `sim1802:nshflat` combines them into the smallest NSH. Its defconfig
  uses the banked profile, where it runs;
  `scripts/measure-flat-nsh.sh` also links it flat for HW48/16.

## Consequences

- The flat NSH shrinks from 93.5 KB to 72.0 KB: the console saves
  16.2 KB, the board start and other changes 5.3 KB. It still does not
  fit 48 KiB (journal step-10, "Flat NSH, second attempt").
- The minimal console has no line discipline: backspace is echoed as-is,
  and there are no termios or `poll()`. The serial driver remains the
  normal choice.
- A board that starts NSH itself is not the NuttX convention (the init
  task is). It is an option, off by default.

## How to revisit

If NuttX's serial driver or `task_spawn()` gain options that make them
small, drop these.
