# 2. Before you start: toolchain requirements and measuring feasibility

> First tag: `step-01-toolchain` (toolchain), `step-04-size-gate` (the
> measurement). Data: `docs/journal/step-04.md`.

A NuttX port is a large investment: an arch layer, a board layer, interrupt
and context-switch code, and weeks of debugging. Two things can make it
pointless before you write the first `up_*` function: a toolchain that cannot
build NuttX correctly, and a kernel that does not fit the target. Both can be
checked in days, with very little arch code. Do that first.

## 2.1 What the toolchain must provide

NuttX's common code is portable C99 with a few GCC-style extensions. Your
compiler needs:

- **C99**, including `long long` and designated initialisers.
- **Attributes:** `__attribute__((noinline, noreturn, weak, section(...),
  aligned, packed))`. `include/nuttx/compiler.h` maps them per compiler;
  weak symbols are used for optional board hooks.
- **Sections** and a **linker with scripts** (`MEMORY`, `AT >` for a ROM copy
  of `.data`, `KEEP`, `ASSERT`) and, strongly recommended,
  `-ffunction-sections`/`-fdata-sections` with `--gc-sections`
  (`CONFIG_DEBUG_OPT_UNUSED_SECTIONS`, which depends on
  `ARCH_TOOLCHAIN_GNU`).
- **A runtime library** (libgcc or equivalent) for whatever the CPU cannot do
  in instructions: multiplication and division, 32/64-bit shifts, soft float.
  NuttX's `time_t` and `clock_t` are **64-bit** (unconditionally, at the
  pinned commit), so **64-bit multiplication and division are always
  needed**.
- **No C library of its own is needed.** NuttX links with `-nostdlib` and
  brings its own libc. Build the compiler's runtime library without target
  libc headers (`--without-headers --with-newlib` in GCC's configure), so it
  cannot depend on a foreign libc.
- **Atomics:** if the CPU has no atomic instructions, the compiler emits
  `__atomic_*` library calls. Select `LIBC_ATOMIC_IRQ` (atomics implemented by
  briefly disabling interrupts), as the 8-bit AVRs do.

> **CDP1802 example:** mikpe's GCC 15 port meets all of these. It needed two
> configure choices (`--with-arch=1802` so the default multilib matches the
> libc, `--disable-gcov`), and one patch to make stack-pointer updates
> interrupt-safe (ADR 0007). `int` is 16 bits: NuttX supports that, but the
> memory model must be selected in `compiler.h` (ADR 0008).

**Validate the compiler before trusting it.** A port magnifies every code
generation bug, because NuttX exercises paths that small test programs do not.
Run the compiler's own test suite if you can (GCC's `gcc.c-torture/execute`
runs fine in a simulator with a trivial runner), and write focused tests for
the helpers the kernel depends on.

> **CDP1802 example:** the torture suite passed about equally at every
> optimisation level. Yet the port's own 64-bit division helpers exposed a
> **wrong-code bug at `-Os`** that the suite does not catch (toolchain issue
> 0002: a 12-line reproducer returns the wrong value). They also exposed a
> compiler **hang at `-O1`** (issue 0003). The only correct small-code
> configuration costs 21 % more ROM. Budget time for this.

## 2.2 Measure before you port

You do not need a working port to know how big NuttX will be. You need just
enough arch code to **link**:

1. Create the arch and board directories with the headers NuttX includes
   (`types.h`, `limits.h`, `inttypes.h`, `irq.h`, `arch.h`, `syscall.h`),
   Kconfig entries, `Make.defs`/`Toolchain.defs` and a linker script.
2. A reset stub that references `nx_start`, so that `--gc-sections` keeps the
   kernel.
3. Configure a realistic *minimal* system: no shell, the scheduler,
   semaphores, watchdog timers, the heap, a minimal VFS with `/dev/console`,
   and `printf` from an init task (`hello_main`). Start from an existing tiny
   config (`arduino-mega2560:hello` is a good model) and `CONFIG_DEFAULT_SMALL`.
4. Build. The compiler will build all common code; the **linker lists every
   missing arch interface** (`undefined reference to up_...`). Provide each one
   as a `PANIC()` or empty stub. That list is your to-do list for the port.
5. Turn on the link map (`CONFIG_DEBUG_LINK_MAP`) and let the image be as big
   as it is: the map is written even when a memory region overflows.
6. Group the map by library and by function (`scripts/size-report.py`). With
   `-ffunction-sections`, every input section is one function.
7. Build **the same configuration** for a reference target (e.g. a Cortex-M3)
   and compare *common-code* libraries only (`libsched`, `libfs`, `libc`,
   `libmm`); arch, drivers and board differ by design.

> **CDP1802 example** (`scripts/measure-step-04.sh`):
>
> | | common code | whole ROM image |
> |--|--:|--:|
> | Cortex-M3 | 16.4 KB | 25.2 KB |
> | AVR ATmega2560 | 41.5 KB | 52.0 KB |
> | CDP1802 `-Os` (unsafe) | 55.0 KB | 62.0 KB |
> | CDP1802 `-Os` + workaround | 66.8 KB | 75.2 KB |
>
> The first link was 90.7 KB: 34 KB of it was libgcc's generic 64-bit
> division (three copies of about 11 KB). Replacing it with a compact
> implementation in the arch (ADR 0009) saved 28.7 KB. The verdict: the
> kernel needs 2.3× the 32 KB ROM of a typical COSMAC board, and does not
> leave enough RAM even in a flat 64 KB simulator. A 122 KB NSH is out of the
> question without code banking.

## 2.3 Reading the numbers

- **Code density** (common code relative to a Cortex-M3) is the single most
  useful figure. It predicts NSH, drivers and applications, not just the kernel.
- Look at the **top 20 functions**. Surprises there (like 64-bit division or
  time arithmetic) are usually either fixable or structural. Find out which
  before deciding.
- Measure **every option** you intend to use, on a clean build each time
  (NuttX's make does not rebuild objects when only compiler flags change).
- Record RAM too: static `.data`/`.bss` plus the heap, the idle and init
  stacks, and any interrupt-stack or guard requirements of your port.

## Checklist

- [ ] The compiler builds all of NuttX's common code without warnings for your
      configuration (fix the memory model if `sizeof(int) != 4`).
- [ ] The link fails only on missing `up_*` interfaces, and you have the list.
- [ ] You have a size breakdown by library and by function from the link map.
- [ ] You have the same breakdown for a reference architecture.
- [ ] You know the ROM and RAM of your target profiles and the verdict for each.
- [ ] You have run the compiler's test suite, or at least focused tests of the
      runtime helpers, at the optimisation level you will ship.

## Common pitfalls

- **Stale objects:** changing only `CFLAGS` and running `make` again measures
  the old code. Always `make distclean` between measurements.
- **Comparing whole images across architectures:** drivers and board code
  dominate small ARM images. Compare common-code libraries.
- **Reference configs that are not optimised:** a board's `nsh` defconfig may
  build with `-O0` and debug symbols. Check the resulting `.config`.
- **Trusting a passing test suite:** it proves only what it tests. A bug that
  your kernel triggers may not be in it.
- **Assuming a Kconfig switch exists:** NuttX evolves. At the pinned commit,
  64-bit time can no longer be configured away.
