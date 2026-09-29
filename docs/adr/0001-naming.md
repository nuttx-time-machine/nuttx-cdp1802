# 0001 — Architecture, chip and board naming

Status: Proposed (agent)
Date: 2026-09-29
Step: step-00-bootstrap

## Context

NuttX sorts ports into three layers (`arch/<arch>/src/<chip>/`,
`boards/<arch>/<chip>/<board>/`). The chosen names show up in directory names,
Kconfig symbols (`CONFIG_ARCH_<ARCH>`, `CONFIG_ARCH_CHIP_<CHIP>`,
`CONFIG_ARCH_BOARD_<BOARD>`), include paths (`<arch/chip/...>`) and
`tools/configure.sh <board>:<config>`. Renaming later touches all of them,
so this is the first decision to make.

The target family is RCA COSMAC: CDP1802, plus the CDP1804/1805/1806, which
the contract says add SCAL/SRET and an on-chip counter/timer (hypotheses H1/H4,
not verified at this step). The first board is not real hardware. It is the virtual machine
defined by mikpe's `sim1802` I/O controller.

Precedents at the pinned NuttX commit (`ls nuttx/arch`): `arm`, `avr`, `z80`,
`renesas`, `hc`, `mips`, `misoc`. Architecture directories are named after the
*family*. The chip directory then names the member, e.g. `arch/z80/src/ez80`,
`arch/z80/src/z180`, `arch/avr/src/atmega`.

## Options considered

1. **`arch/cosmac` + chip `cdp1802` + board `sim1802`** (the contract's recommendation).
   Uses the family name like `z80`/`avr`. It leaves room for a `cdp1805` chip
   directory that reuses the arch code and adds the timer.
2. **`arch/cdp1802` everywhere.** Shorter, but the architecture would carry the
   name of one member. A later 1805 chip would sit under a directory named after
   a different part.
3. **`arch/rca`** (vendor name, like `renesas`). A vendor name says nothing about
   the instruction set, and `arch/renesas` shows the downside: one directory
   holds unrelated ISAs (`ls nuttx/arch/renesas/src` shows `sh1`, `m16c`, `rx65n`).
   Rejected.

## Decision

Option 1:

| Layer | Path | Kconfig |
|-------|------|---------|
| Architecture | `arch/cosmac/` | `CONFIG_ARCH_COSMAC`, `CONFIG_ARCH="cosmac"` |
| Chip | `arch/cosmac/src/cdp1802/` | `CONFIG_ARCH_CHIP_CDP1802`, `CONFIG_ARCH_CHIP="cdp1802"` |
| Board | `boards/cosmac/cdp1802/sim1802/` | `CONFIG_ARCH_BOARD_SIM1802`, `CONFIG_ARCH_BOARD="sim1802"` |

A possible later 1805/1806 chip directory is `arch/cosmac/src/cdp1805/`,
selected by `CONFIG_ARCH_CHIP_CDP1805`.

## Consequences

- The Kconfig symbol `ARCH_COSMAC` must not clash with anything. At the pinned
  commit, `grep -rni cosmac nuttx/` returns nothing (checked at Step 00, see journal).
- The board name `sim1802` could be confused with NuttX's `arch/sim` (the host
  simulator). Documentation always says "the sim1802 virtual board" to avoid
  ambiguity.

## How to revisit

Before Step 05 creates any files, a rename costs nothing. After Step 05 it is a
mechanical rename (directories + Kconfig symbols) that needs a new ADR
superseding this one.
