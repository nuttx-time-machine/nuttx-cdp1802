# 5. The arch and board directories: every file and what consumes it

> First tag: `step-05-skeleton` (`nuttx` branch `cdp1802-port`). The files
> appeared at Step 04 as the minimum needed to link; Step 05 documents them.

This chapter walks through every file a new architecture needs, using the
CDP1802 files as the example. For each file: what it is for, what NuttX
expects from it, and where common code consumes it.

## 5.1 Registration (common files you touch)

| File | Change | Consumed by |
|------|--------|-------------|
| `arch/Kconfig` | `config ARCH_<ARCH>` (selects capabilities), `default "<arch>" if ARCH_<ARCH>` for `CONFIG_ARCH`, and `if ARCH_<ARCH> / source "arch/<arch>/Kconfig" / endif` | kconfig; `CONFIG_ARCH` names the directory used by the whole build (`tools/Config.mk`, `tools/Unix.mk`) |
| `boards/Kconfig` | `config ARCH_BOARD_<BOARD>` (depends on the chip), `default "<board>"` for `CONFIG_ARCH_BOARD`, `source` of the board Kconfig | kconfig; `CONFIG_ARCH_BOARD` + `CONFIG_ARCH` locate the board directory |

> **CDP1802 example:** `ARCH_COSMAC` selects `ARCH_TOOLCHAIN_GCC` (this is what
> enables `--gc-sections` via `DEBUG_OPT_UNUSED_SECTIONS`) and
> `ARCH_HAVE_CUSTOMOPT` (to measure other `-O` levels). **Pitfall met:** the
> `source` line was first inserted inside another architecture's
> `if ... endif` block. Nothing from the new Kconfig was then configured, and
> the board directory resolved to `/src`.

## 5.2 `arch/<arch>/Kconfig`

Chip choice, `config ARCH_CHIP` (string), and architecture options. Select the
generic capabilities your CPU needs from common Kconfig (`MM_SMALL` for
16-bit address spaces, `LIBC_ATOMIC_IRQ` when there are no atomic
instructions, `ARCH_HAVE_*`).

> **CDP1802 example:** `ARCH_CHIP_CDP1802` selects `MM_SMALL` and
> `LIBC_ATOMIC_IRQ` (as the 8-bit AVRs do). The irq-state choice
> `COSMAC_IRQSTATE_LSIE` (default) / `COSMAC_IRQSTATE_SWFLAG` is Alan's Step 02
> decision.

## 5.3 `arch/<arch>/include/` — public headers

The build links this directory as `include/arch/`, so common code includes
`<arch/xxx.h>`. `include/arch/chip` points at `arch/<arch>/include/<chip>/`
and `include/arch/board` at the board's `include/`.

| File | NuttX expects | Consumed by |
|------|---------------|-------------|
| `types.h` | `_int8_t` … `_uint64_t`, `_intmax_t`, `_size_t`/`_ssize_t`, `_wchar_t`, `_wint_t`, `irqstate_t`, and `__INT64_DEFINED` if 64-bit exists | `include/stdint.h`, `include/sys/types.h` (via `nuttx/compiler.h`) |
| `limits.h` | `CHAR_*`, `SCHAR_*`, `SHRT_*`, `INT_*`, `LONG_*`, `LLONG_*`, `PTR_*` | `include/limits.h` |
| `inttypes.h` | `PRIxN`/`SCNxN` for every width, matching `types.h` | `include/inttypes.h` |
| `irq.h` | `NR_IRQS`, `struct xcptcontext`, `up_irq_save/restore/enable`, `up_interrupt_context()`, `up_getsp()`, `up_current_regs()`, `up_getusrpc/up_getusrsp` | `include/nuttx/irq.h`, `include/nuttx/sched.h` (the TCB embeds `struct xcptcontext`), `sched/irq`, `sched/misc/assert.c` |
| `arch.h` | optional arch-private public definitions | `include/nuttx/arch.h` |
| `syscall.h` | system-call macros (protected/kernel builds only) | `include/syscall.h` |
| `<chip>/…` | chip definitions, e.g. `chip.h` | chip code, via `<arch/chip/...>` |

The types must **match the compiler's** exactly (`cc -dM -E - </dev/null`),
or format checking and `sizeof` assumptions go wrong.

> **CDP1802 example:** `char` is unsigned, `int` 16 bits, `long` 32 bits,
> pointers 16 bits. `int16_t` is `int` (not GCC's `short`, same size) so that
> the `PRI/SCN` macros copied from AVR match. **Pitfall met:** `int16_t` as
> `short` gave `-Wformat` warnings in `lib_uuid_from_string.c`. `irqstate_t`
> is `unsigned char` (the IE bit). The `struct xcptcontext` layout is
> provisional until Step 08.

## 5.4 `arch/<arch>/src/` — the build glue and code

| File | Purpose | Consumed by |
|------|---------|-------------|
| `Makefile` | builds `libarch.a` from `CHIP_*SRCS`/`CMN_*SRCS`, the head object, and links `nuttx` (`$(LD) --entry=__start ... --start-group ... --end-group`) | top-level `Makefile`/`tools/Unix.mk` |
| `<chip>/Make.defs` | `HEAD_ASRC` (reset code, linked first), `CMN_ASRCS/CSRCS` (from `common/`), `CHIP_ASRCS/CSRCS` | `arch/<arch>/src/Makefile` (via the `chip` link) |
| `<chip>/Toolchain.defs` | compiler, flags, tools, extra libraries | the board's `scripts/Make.defs` |
| `common/*.c`, `*.S` | the `up_*` implementations shared by all chips | `libarch.a` |

> **CDP1802 example** (at step-05): `cdp1802/cdp1802_head.S` (reset: `DIS`,
> PC := R3, call `nx_start`; the real start-up comes in Step 06),
> `common/cosmac_irqsave.S` (LSIE-based irq state),
> `common/cosmac_div64.c` (compact 64-bit division, ADR 0009),
> `common/cosmac_stubs.c` (`PANIC()` stubs for the 16 interfaces the linker
> asked for). There is no family subdirectory: `ARCH_SUBDIR = common`.

## 5.5 The board directory

| File | Purpose | Consumed by |
|------|---------|-------------|
| `Kconfig` | board options | kconfig (sourced from `boards/Kconfig`) |
| `configs/<name>/defconfig` | one configuration (`tools/configure.sh <board>:<name>`) | `tools/configure.sh` |
| `scripts/Make.defs` | includes `Toolchain.defs`, picks the linker script (`ARCHSCRIPT`), sets `CFLAGS`/`AFLAGS` | every `Makefile` via `$(TOPDIR)/Make.defs` |
| `scripts/*.ld` | the memory map | the link in `arch/<arch>/src/Makefile` |
| `include/board.h` | board constants and prototypes for the arch | arch/board code, via `<arch/board/board.h>` |
| `src/Makefile` + sources | `libboard.a` (`boards/Board.mk`) | the link |

> **CDP1802 example:** three linker scripts, one per memory profile
> (`sim64.ld`, `hw32.ld`, `hw48.ld`, ADRs 0005/0012), selected by a Kconfig
> choice in `scripts/Make.defs`. Every script keeps `.reset` first (the reset
> vector is 0x0000), copies `.data` from ROM, defines `__sim1802_rom_end`
> (the simulator's ROM size) and asserts that the image fits.

## Checklist

- [ ] `tools/configure.sh <board>:<config>` succeeds and `.config` shows your
      arch, chip and board symbols.
- [ ] `make` compiles common code with **no warnings**.
- [ ] The link fails only on missing `up_*` functions, then succeeds with stubs.
- [ ] `nxstyle` and `tools/checkpatch.sh -g` pass on the new files and commits.

## Common pitfalls

- Kconfig `source` in the wrong `if` block (see 5.1).
- Types that differ from the compiler's (`-Wformat` warnings are the symptom).
- Forgetting `ARCH_TOOLCHAIN_GCC`: no `--gc-sections`, much bigger images.
- A linker script without `KEEP` on the reset section: `--gc-sections`
  removes it.
