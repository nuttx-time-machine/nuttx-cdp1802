# Step 04 — Size feasibility (GATE)

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## Part 0 — prerequisite: interrupt-safe stack-pointer updates (ADR 0007)

Not a Step 04 deliverable, but done first because it changes the code GCC
generates for every function, so the size measurements must use the final
compiler. Alan chose option 1 of toolchain issue 0001 ("patch GCC").

### What was done, in order

1. Found where GCC writes R2 (`cdp1802.cc`/`.md`): `addhi3`/`subhi3` with a
   constant (prologue/epilogue), `movhi` register→SP (epilogue SP ← FP),
   constant→SP and memory→SP. The `c` constraint ("any register except SP")
   means register+register adds never target SP.
2. Wrote C template helpers that emit safe orderings when the destination is
   SP, a dedicated epilogue insn `cdp1802_restore_sp_from_fp`, and matching
   length attributes. The loads from memory were first made a compile-time
   error ("not expected in C code").
3. **The rebuilt GCC failed to build libgcc:**
   `unwind-sjlj.c:308:1: error: cdp1802: loading the stack pointer from memory is not interrupt-safe`
   (SJLJ unwinder, `uw_install_context`). The assumption was wrong, so all
   three memory forms (plain, post-inc, post-dec) now use the safe ordering.
   While doing that, fixed my own bug: for the plain form the address *is*
   the register, so `XEXP (XEXP (src, 0), 0)` read garbage.
4. My `grep` over the build output hid the first failure (the script had
   correctly stopped and kept the old compiler installed: the generated code
   was still unsafe). The build exit status is now always checked explicitly.
5. The patch lives in `toolchain/patches/gcc/0001-…patch` (made with
   `git format-patch` in the GCC work tree). `build-toolchain.sh` resets the
   tree to the pinned SHA and applies all patches; the GCC stamp includes their
   hash. The libc stamp now includes the GCC stamp, because the libc was *not*
   rebuilt at first and still contained unsafe prologues.
6. Wrote `scripts/check-sp-safety.py`, a static checker that decodes the
   machine code of every function itself (NCRT `sep 4` + address, 1804
   prefix) and requires each composite R2 update to match a proven-safe
   sequence. Three bugs in the checker along the way:
   - it decoded from `objcopy -O binary` with the wrong base (first
     segment instead of first section, off by 0x74), giving nonsense
     "unsafe" hits and decode overruns. It now reads sections from the ELF;
   - it merged two back-to-back safe updates into one unknown pattern.
     It now covers writes greedily with patterns;
   - it needed an explicit `--allow SYMBOL` for code that provably runs with
     IE=0 (mikpe's `crt0` `_start` sets the first SP at boot).
7. Built the **unpatched** compiler into a scratch prefix to prove that the
   checker and the stress test detect the bug.

### Results

8. Docker re-verification then failed in an unrelated-looking place:
   `test-sim-fork.sh` printed `idle: 10 wakeups, \001rq_count +10`. It was
   not the compiler: the simulator's I/O controller has **one argument buffer
   shared by all devices**. `putchar` does `OUT 6` (byte) then `OUT 7`
   (command). The test ISR wrote its own `OUT 6` (IRQ mask 0x01) in between,
   so 0x01 was printed instead of `i`. The patched code shifted the timing,
   and the deterministic timer then hit that spot on every run. All test ISRs
   now save the buffer on entry (`DEC 2; INP 6`, or via R0 in the audit
   harness) and restore it on exit (`OUT 6`). This rule is now in the board
   document (§4) for the NuttX interrupt entry.
9. The interrupt counts first reported here (e.g. "62 830 interrupts") were
   wrong: the test's 16-bit counter wrapped. Found because period 331 reported
   exactly 331 interrupts over 43.8 M cycles. The counter is now 32-bit; all
   numbers below were re-measured.

```
$ scripts/check-sp-safety.py --allow _start build/sp-safety/stress-unpatched.elf | tail -1
sp-safety: FAIL (15 unsafe)
$ scripts/test-sp-safety.sh
ok: static check of hello, softfloat, abi (libgcc + libc included)
sp-safety: 50 functions, 29 composite R2 updates, 0 single-byte R2 writes
    14 x add 0<=V<256 (low byte first, carry 0)
     9 x add V>=256 or V<0 (high byte first, then low)
     2 x SP <- FP in epilogue (SP <= FP, low byte first)
     4 x SP <- register (one page below first)
sp-safety: OK
period=157 rounds=256 irqs=740604 errors=0
period=211 rounds=256 irqs=319774 errors=0
period=331 rounds=256 irqs=141438 errors=0
PASS: sp-safety
```

Same stress program built with the unpatched compiler:

```
period=157: killed by the 300 s timeout (exit 124)
period=211 rounds=256 irqs=319640 errors=63        (exit 1)
period=331 rounds=256 irqs=141381 errors=7         (exit 1)
```

This confirms that issue 0001 is real (the corruption shows up within a few
thousand cycles of this workload) and that the patch removes it.

### Hypotheses

- **H2** (R2 must always be a valid stack): now true for compiled code, with
  the patched compiler and a 256-byte (511 with VLA/alloca) guard band.

## Part 1 — size feasibility

### What was done, in order

1. **Arch stub** (`nuttx`, branch `cdp1802-port`): `arch/cosmac` (Kconfig,
   `types.h`, `limits.h`, `inttypes.h`, `irq.h`, `arch.h`, `syscall.h`, Make
   glue, `Toolchain.defs`), the reset stub `cdp1802_head.S` (calls
   `nx_start` only), `cosmac_irqsave.S` (the tested LSIE code) and
   `cosmac_stubs.c`. Board `boards/cosmac/cdp1802/sim1802` with both linker
   scripts (grown from the Step 03 prototypes) and the `minimal` defconfig
   (modelled on `arduino-mega2560:hello`: no NSH, `hello_main`,
   `CONFIG_DEFAULT_SMALL`, console through syslog/`up_putc`).
2. **Kconfig problems on the way**:
   - `source "arch/cosmac/Kconfig"` ended up inside `if ARCH_AVR` (my edit), so
     nothing from it was configured and the board directory resolved to
     `/src` (`No directory at .../nuttx//src`). Fixed.
   - `CONFIG_DEBUG_OPT_UNUSED_SECTIONS` (`--gc-sections`) was not offered:
     it depends on `ARCH_TOOLCHAIN_GNU`, so the arch now selects
     `ARCH_TOOLCHAIN_GCC`. Later also `ARCH_HAVE_CUSTOMOPT`, needed to measure
     other optimisation levels.
3. **First compile: all of NuttX's common code compiled** with mikpe's GCC.
   There were 21 warnings (14 × `-Wshift-count-overflow`, 5 × `-Woverflow`,
   2 × `-Wformat`), all consequences of `sizeof(int) == 2`:
   `mm/mm_heap/mm.h:115` (shift count ≥ width), `lib_gets.c`,
   `lib_rawmemchr.c` and three `wchar` files (SIZE_MAX/SSIZE_MAX as 32-bit
   values), and a format mismatch in `uuid/lib_uuid_from_string.c` caused by
   my own `types.h` (int16_t = short).
   - The first two groups are not bugs: NuttX selects its 16-bit model in
     `include/nuttx/compiler.h` per compiler (`__m32c__`, `__AVR__`,
     `__mc68hc1x__`). Added a `__CDP1802__` branch → **one common-code change,
     ADR 0008**. The arch also selects `MM_SMALL` and `LIBC_ATOMIC_IRQ`, like
     the 8-bit AVRs.
   - `int16_t` is now `int`, as on AVR.
   - Result: **0 warnings**.
4. **First link: no missing symbols except the expected ones.** The linker
   listed 16 `up_*`/board interfaces (now `PANIC()`/empty stubs) and the
   4-byte `__atomic_*` library calls (solved by `LIBC_ATOMIC_IRQ`).
5. **First complete link: `.text` = 0x16225 = 90 660 bytes** (region `rom`
   overflowed by 57 948 bytes). The map is still written;
   `scripts/size-report.py` groups it by library and by function.
   **libgcc was 34 347 bytes**, almost all of it `__divdi3` (10 926),
   `__umoddi3` (10 876) and `__udivdi3` (10 543), pulled in by 64-bit time
   arithmetic.
6. Found that **`time_t` and `clock_t` are unconditionally `int64_t`** in
   NuttX at the pinned commit (`include/sys/types.h:248-249`; the
   `SYSTEM_TIME64` option no longer exists). 64-bit arithmetic is structural.
7. Wrote `cosmac_div64.c` (ADR 0009): one shared bit-at-a-time loop plus a
   32-bit fast path. First build 3 463 bytes. Then:
   - it did not compile outside NuttX (`NULL` without `<stddef.h>`: fixed);
   - the correctness test against libgcc did not fit in 64 KiB (libgcc's
     division itself is the problem), so reference vectors are computed on
     the host (`toolchain/tests/div64/gen_vectors.py`, 492 vectors);
   - **253 of 492 signed results were wrong.**
8. **Toolchain issue 0002: wrong code at -Os.** Bisected from the division
   helpers down to a 12-line program (`toolchain/tests/issues/0002`): it
   returns `a` instead of `a - b` at `-Os` and is correct at `-O0/-O1/-O2`,
   with or without the ADR 0007 patch. Of 35 `-fno-*` flags tried,
   **`-fno-split-wide-types`** alone avoids it; `-fsplit-wide-types-early`
   does not. With the flag, 0 of 492 division vectors fail. Adopted as
   `COSMAC_GCC_WORKAROUNDS` in `Toolchain.defs` (ADR 0010).
9. **GCC torture suite** (1 687 `gcc.c-torture/execute` programs, own
   parallel runner `scripts/torture.sh`; DejaGnu is not installed and cannot
   be without root): `-Os`, `-Os -fno-split-wide-types`, `-O1` and `-O2`
   give practically the same results (1 473–1 477 PASS; 29 programs fail at
   every level, probably tests that do not apply to 16-bit int, which DejaGnu
   would skip). **The suite does not catch issue 0002**, so it cannot show
   that the flag avoids every instance of the bug. This is an open risk.
10. **Toolchain issue 0003: `-O1` never finishes** compiling
    `libs/libc/pwd/lib_getpwbufr.c` (killed after 20 min; `-Os`/`-O2`: < 1 s).
    The preprocessed reproducer is in `toolchain/tests/issues/0003`. `-O1` is
    therefore not measured.
11. **Stale-object pitfall.** An incremental rebuild after changing only
    `COSMAC_GCC_WORKAROUNDS` reported unchanged library sizes: NuttX's make
    does not track flags. `scripts/build.sh` now always starts with `make
    distclean`. All numbers below come from clean builds. Two more mistakes:
    - editing `build.sh` while a background run was executing it made that
      run's `-O1` result invalid (discarded);
    - a `pkill -f` pattern matched my own shell.
12. **Comparison builds** with the same configuration shape (script
    `scripts/measure-step-04.sh`): `nucleo-f072rb` (Cortex-M0),
    `stm32f103-minimum` (Cortex-M3), `arduino-mega2560` (AVR, `-Os`), using the
    host's `arm-none-eabi-gcc` 13.2.1 and `avr-gcc`. The M0 board's `nsh`
    config needed `FS_PROCFS` off (its bring-up mounts procfs even with
    `DISABLE_MOUNTPOINT`) and `DEBUG_FULLOPT` (it was `-O0`, which first gave
    a meaningless 18 KB scheduler).
13. **NSH projection**: `sim1802` built with exactly the NSH option set of
    `stm32f103-minimum:nsh` (copied through a config fragment, because
    `kconfig-tweak` cannot pass empty strings).
14. **32-bit time experiment** (throw-away branch, not committed):
    `time_t`/`clock_t` as `int32_t` in `include/sys/types.h`. It compiled
    without warnings.

### Measurements

ROM = `.text` + `.rodata` + `.data` (the ROM image); RAM = static `.data` +
`.bss` (without heap and stacks). All `-Os` unless stated.

| # | Build | ROM bytes | vs HW32/32 (32 768) |
|---|-------|----------:|--------------------|
| B0 | CDP1802, libgcc's 64-bit division (first link) | 90 714 | 2.77× |
| B1 | CDP1802, compact division, **no** workaround (wrong code possible) | 62 016 | 1.89× |
| **B2** | **CDP1802, compact division + `-fno-split-wide-types` (default)** | **75 181** | **2.29×** |
| B3 | CDP1802 `-O2` (no workaround; issue 0002 reproducer is correct at -O2) | 75 197 | 2.29× |
| B4 | CDP1802 `-O1` | — (compiler hang, issue 0003) | — |
| B5 | CDP1804 instruction set (`-march=1804`), no workaround | 59 568 | 1.82× |
| B6 | CDP1804, with workaround | 72 563 | 2.21× |
| B7 | B1 + `CONFIG_DISABLE_ALL_SIGNALS` | 60 132 | 1.84× |
| B8 | B2 with 32-bit `time_t`/`clock_t` (experiment) | 61 978 | 1.89× |
| B9 | B1 with 32-bit `time_t`/`clock_t` (experiment) | 56 587 | 1.73× |
| N1 | CDP1802 **NSH** (feature set of stm32f103-minimum:nsh), no workaround | **122 208** | 3.73× |
| — | Cortex-M3 NSH, same NSH options | 51 259 | |

Static RAM is 556 bytes in B2 (heap and stacks come on top).

**Common code, by subsystem** (the fair comparison; arch/drivers/board
differ by design):

| Build | libsched | libfs | libc | libmm | common total | libgcc | arch+drivers+board | ROM total |
|---|---|---|---|---|---|---|---|---|
| CDP1802 -Os | 25,697 | 12,788 | 12,671 | 3,860 | **55,016** | 1,900 | 5,069 | 62,016 |
| CDP1802 -Os + workaround | 33,651 | 13,068 | 16,215 | 3,880 | **66,814** | 1,900 | 6,436 | 75,181 |
| CDP1802 -O2 | 28,401 | 16,164 | 18,744 | 4,615 | **67,924** | 1,900 | 5,342 | 75,197 |
| CDP1804 -Os | 24,853 | 11,989 | 12,271 | 3,722 | **52,835** | 1,848 | 4,854 | 59,568 |
| AVR ATmega2560 -Os | 17,574 | 9,928 | 11,231 | 2,719 | **41,452** | 1,056 | 9,144 | 51,981 |
| Cortex-M0 STM32F072 -Os | 8,346 | 4,302 | 3,619 | 1,201 | **17,468** | 2,052 | 9,450 | 29,001 |
| Cortex-M3 STM32F103 -Os | 7,784 | 4,234 | 3,167 | 1,195 | **16,380** | 904 | 7,924 | 25,239 |

- CDP1802 -Os: common code = 3.36 x Cortex-M3
- CDP1802 -Os + workaround: common code = 4.08 x Cortex-M3
- CDP1802 -O2: common code = 4.15 x Cortex-M3
- CDP1804 -Os: common code = 3.23 x Cortex-M3
- AVR ATmega2560 -Os: common code = 2.53 x Cortex-M3
- Cortex-M0 STM32F072 -Os: common code = 1.07 x Cortex-M3
- Cortex-M3 STM32F103 -Os: common code = 1.00 x Cortex-M3


**Top 20 symbols of the default build B2** (`build/step04-minimal/size.txt`):

```
   7461  vsprintf_internal      libc      (printf core, incl. long long)
   5793  clock_systime_timespec libsched  (64-bit time; 1 654 without the workaround)
   5452  clock_basetime         libsched  (64-bit time; 3 480 without the workaround)
   3188  udivmod64              libarch   (compact 64-bit division, ADR 0009)
   1950  clock_initialize       libsched
   1894  clock_calendar2utc     libc
   1386  nxsem_wait_slow        libsched
   1238  inode_search_setup     libfs
   1114  nxtask_setup_scheduler libsched
    999  nxsched_set_priority   libsched
    964  __divdi3               libarch
    957  mm_delayfree           libmm
    955  mm_malloc              libmm
    900  __ultoa_invert         libc
    892  inode_search           libfs
    859  nxsem_post_slow        libsched
    790  fdlist_copy            libfs
    765  nxtask_setup_stackargs libsched
    752  nx_start               libsched
    752  task_spawn             libsched
```

Time-keeping alone (`clock_*`, `calendar2utc`, the division) is about 19 KB
of the 75 KB.

### Kconfig and build options that reduce size (measured)

| Change | Saving | Usable? |
|--------|-------:|---------|
| Replace libgcc's 64-bit division (ADR 0009) | 28.7 KB (B0 → B1) | yes, done |
| Drop the `-fno-split-wide-types` workaround | 13.2 KB (B2 → B1) | **no**: issue 0002 generates wrong code |
| 32-bit `time_t`/`clock_t` | 13.2 KB with workaround, 5.4 KB without | only with a common-code change (upstream moved to 64-bit on purpose) |
| CDP1804 instruction set | 2.4–2.6 KB (~4 %) | only on CDP1804/5/6 hardware (the sim supports the register ops used) |
| `CONFIG_DISABLE_ALL_SIGNALS` | 1.9 KB | no: signals are needed by ostest and NSH |
| Already applied by `CONFIG_DEFAULT_SMALL` and the defconfig: no pthreads, POSIX timers, message queues, environment, mount points, file streams, waitpid, task names, stdio buffers, unget buffer, floating point and numbered arguments in printf | — | yes |

Not measured, but plausible single-digit KB savings: a smaller printf
(`vsprintf_internal` is 7.5 KB), fewer file descriptors per block, and fewer
syslog features. None of them closes a 2× gap.

### Hypotheses

- **H6 (code size is the main feasibility risk): confirmed, strongly.** For
  the same C code, the CDP1802 needs 3.4× (4.1× with the workaround) the ROM
  of a Cortex-M3, and 1.3× (1.6×) that of an AVR.
- H7 and the ABI are unchanged; `sizeof(int) == 2` needed only the
  `compiler.h` branch (NuttX already supports 16-bit int).

## GATE report — go / no-go

**Does the kernel fit?**

- **HW32/32 (32 KiB ROM): NO.** The minimal kernel needs 75 KB with correct
  code, 2.3× the ROM. Even with every measured reduction combined (CDP1804,
  32-bit time, no signals, and accepting the compiler bug) it would be about
  50–55 KB, still 1.6–1.7× too big.
- **SIM64 (64 KiB address space, ROM + RAM): NO in practice.**
  - With the workaround (correct code) the image does not fit in 64 KiB at all.
  - Without it (62 KB, but code that may be wrong) about 3.5 KB would remain
    for RAM, while static data, heap, the idle and init stacks and the
    256-byte interrupt guard band need more than that.
  - With 32-bit time and no workaround (56.6 KB) about 9 KB of RAM would be
    left: enough for `hello`, not for `ostest`.
- **NSH: NO.** About 122 KB (no workaround), twice the address space.

**Why:** code density (3.4–4.1× Cortex-M3 for identical C: no base+offset
addressing, 8-bit ALU, every call through NCRT), NuttX's mandatory 64-bit
time, and a toolchain whose correct-code configuration costs another 21 %.

**Options** (Alan decides; nothing below has been started):

| | Option | What it gives | Cost / risk |
|--|--------|---------------|-------------|
| A | **Code banking**: extend the sim fork with a banked ROM window (switched by an OUT port); the NCRT call routine already sees every call and can switch banks for far calls; linker scripts place subsystems in banks | NuttX of any size, NSH included; exercises a real COSMAC technique | Large: far calls, bank-aware function pointers (task entry points, callbacks), linker work; slower calls; the HW32/32 feasibility answer stays "no" |
| B | **Improve the compiler** with mikpe: fix issue 0002 (saves 13 KB), 0003, denser struct/pointer code, 1804 codegen | Everything gets smaller and safer | Depends on mikpe; not in our control; gains unknown |
| C | **Local 32-bit time + trimming** (common-code change, ADR, not upstreamable) | ~57–62 KB: `hello` runs in SIM64 | Diverges from upstream NuttX; still no ostest/NSH headroom; does not fix HW32/32 |
| D | **Pin an older, smaller NuttX release** (contract amendment) | Probably smaller (older kernels had 32-bit time options) | Needs measuring; loses upstream-readiness (Step 11) |
| E | **Stop the port here** and publish the feasibility study as the result | The porting-guide chapter "measure before you port" with real data | The working-port deliverable is not achieved |

**Recommendation:** A + B.
- **B first**, because it is cheap for us: send the drafted reports (issues
  0001–0003) and the ADR 0007 patch to mikpe. Issue 0002 alone costs 13 KB,
  and a compiler that can silently generate wrong code at -Os is a risk for
  the whole port, however large the ROM.
- **A as the way to a running system:** develop in SIM64 with a banked-ROM
  extension, keep all arch/board code banking-agnostic where possible, and
  report honestly that a flat 32 KiB ROM cannot hold NuttX on the CDP1802.

C is a fallback if Alan prefers a quick "hello" demonstration in SIM64.

### Decisions requested from Alan

1. Which option (A–E), or a combination.
2. May the drafted bug reports for mikpe (issues 0001, 0002, 0003) be sent
   (by you)?
3. Accept ADR 0008 (`compiler.h` branch, a common-code change), ADR 0009
   (compact division) and ADR 0010 (the workaround flag)?

## Time spent

About 4 h wall-clock, including roughly 1.5 h of builds (the `-O2` build and
the torture runs dominate).

## Gate outcome (Alan, 2026-09-29)

"Went all these options: A to C. Also consider the option 16KB RAM and 48KB
ROM to alleviate the pressure."

| Item | Done |
|------|------|
| **C** — 32-bit time | Opt-in `CONFIG_SYSTEM_TIME32` (a common-code change, ADR 0011). Upstream removed `SYSTEM_TIME64` in `c6654b1106` (2026-05-03); reverting that commit touches 187 files with conflicts, so the option only restores the types (`sys/types.h`) and `CLOCK_MAX` (`limits.h`). The `sim1802:minimal` defconfig enables it. Clean build, 0 warnings: **61 978 bytes** (workaround on). |
| **HW48/16** | New profile (ADR 0012): 48 KiB ROM at 0, 16 KiB RAM at 0xC000. Minimal build with 32-bit time: **overflow by 12 828 bytes** (61 978 > 49 152). Without the issue 0002 workaround it would be about 7.4 KB over; with the CDP1804 ISA as well, about 5 KB. A fixed compiler could make flat 48 KiB feasible. |
| **B** — compiler | Ready-to-send package for mikpe in `docs/toolchain-issues/for-mikpe/` (e-mail text, the ADR 0007 patch, three reproducers). The patch was checked with `git apply --check` against a clean `8b18811140ea`. **Not sent: Alan sends it.** |
| **A** — code banking | Designed (ADR 0013): fixed ROM 32 KiB + a 16 KiB bank window at 0x8000 + 16 KiB RAM, i.e. the 48/16 split with the upper 16 KiB banked. Implementation needs the Step 06 runtime; see amendment A5 for the new order. |

ADRs 0008–0010 stay "Proposed": Alan's reply chose the options but did not
mention them.
