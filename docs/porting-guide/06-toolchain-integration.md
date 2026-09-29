# 6. Toolchain integration: Toolchain.defs, Make.defs, flags and libgcc

> First tag: `step-04-size-gate` / `step-05-skeleton`.

## 6.1 `Toolchain.defs`

`arch/<arch>/src/<chip>/Toolchain.defs` defines, for the whole build:

| Variable | Meaning |
|----------|---------|
| `CROSSDEV` | tool prefix, e.g. `cdp1802-elf-` |
| `CC`, `CPP`, `LD`, `AR`, `NM`, `OBJCOPY`, `OBJDUMP`, `STRIP` | the tools |
| `ARCHCPUFLAGS` | CPU selection (`-march=...`) |
| `ARCHOPTIMIZATION` | `-O` level from `CONFIG_DEBUG_FULLOPT`/`CUSTOMOPT`, `-g` from `CONFIG_DEBUG_SYMBOLS`, `-ffunction-sections -fdata-sections` with `CONFIG_DEBUG_OPT_UNUSED_SECTIONS` |
| `ARCHCFLAGS` | warnings, `-fno-common`, workarounds |
| `LDFLAGS` | `-nostdlib`, `--gc-sections`, `-Map=` with `CONFIG_DEBUG_LINK_MAP` |
| `EXTRA_LIBS` | the compiler runtime library (`$(CC) -print-libgcc-file-name`) |

The board's `scripts/Make.defs` includes it and composes `CFLAGS`, `AFLAGS`
(`CFLAGS -D__ASSEMBLY__`) and `ARCHSCRIPT`.

> **CDP1802 example:**
> - `CROSSDEV ?= cdp1802-elf-` (amendment A3), `ARCHCPUFLAGS = -march=1802`
>   (`-march=1804` for the CDP1804AC register instructions: about 4 % smaller).
> - `-Os` for `DEBUG_FULLOPT`: size is the main risk. `-O2` is no smaller and
>   much slower to compile; `-O1` hangs the compiler (toolchain issue 0003).
> - `COSMAC_GCC_WORKAROUNDS ?= -fno-split-wide-types` (ADR 0010, toolchain
>   issue 0002): a named variable, so it can be removed in one place and
>   switched off for measurements (`make COSMAC_GCC_WORKAROUNDS=`).

## 6.2 The runtime library and helper routines

NuttX links with `-nostdlib`: no compiler C library, only libgcc
(`EXTRA_LIBS`). Everything else comes from NuttX's `libs/libc`.

- The **arch library is linked before libgcc**, so the arch can replace a
  libgcc routine simply by defining it. Use this when a generic C routine is
  unaffordable on your CPU.
- Build libgcc **without target libc headers**, so it cannot reference a
  foreign libc (ADR 0004).
- Know which libgcc members you link: the size report lists `libgcc.a`
  separately.

> **CDP1802 example:** libgcc's generic 64-bit division compiled to 11 KB
> per routine (`__divdi3`, `__udivdi3`, `__umoddi3`); NuttX's 64-bit time
> needs them. `arch/cosmac/src/common/cosmac_div64.c` (ADR 0009) replaces all
> four with about 4 KB, verified against 492 host-computed vectors. libgcc
> went from 34 KB to 2 KB of the image.

## 6.3 `compiler.h` and the memory model

`include/nuttx/compiler.h` selects features per compiler and target: the
memory model (`CONFIG_SMALL_MEMORY`, `CONFIG_LONG_IS_NOT_INT`,
`CONFIG_PTR_IS_NOT_INT`), attribute macros, `FAR`/`near` qualifiers. If your
`int` or pointers are not 32 bits, you probably need a branch there (a
common-code change: separate commit, ADR).

> **CDP1802 example:** a `__CDP1802__` branch (ADR 0008) removed the five
> `-Woverflow` warnings (32-bit `SIZE_MAX`/`SSIZE_MAX` truncated into the
> 16-bit `size_t`). Selecting `MM_SMALL` removed the other 14 (a 22-bit heap
> chunk shift in `mm/mm_heap/mm.h`).

## 6.4 Measuring and cleaning

NuttX's make does not rebuild objects when only flags change. Every
measurement in this port uses `scripts/build.sh`, which starts from
`make distclean`.

## Checklist

- [ ] `make V=1` shows your CPU flags, `-ffunction-sections` and `--gc-sections`.
- [ ] `nuttx.map` is produced (`CONFIG_DEBUG_LINK_MAP`).
- [ ] You know the size contribution of the compiler runtime library.
- [ ] Workarounds for toolchain bugs are named, isolated and documented.

## Common pitfalls

- Stale objects after changing flags (6.4).
- A libc-dependent libgcc (build it `--without-headers`).
- Trusting an optimisation level you have not tested (issues 0002, 0003).
