# 0004 — NuttX uses only its own libc; libgcc is built without target libc headers

Status: Accepted (follows Alan's direction of 2026-09-29: "NuttX has its own
libc that normally doesn't depend on external libc")
Date: 2026-09-29
Step: step-02 follow-up (before step-03)
Partially supersedes: [0002](0002-toolchain-build.md) (how libgcc is built)

## Context

Alan asked whether newlib could replace mikpe's GPL-3.0 `cdp1802-elf-libc`,
and pointed out that NuttX has its own libc. Facts checked at the pinned commits:

- **NuttX links no external libc.** GNU-toolchain ports link with `-nostdlib`
  (`arch/arm/src/common/Toolchain.defs:413`, `arch/avr/src/avr/Toolchain.defs:159`)
  and use NuttX's own C library (`libs/libc/`, Apache-2.0) plus libgcc.
- **newlib has no CDP1802 port.** `newlib/configure.host` on sourceware master
  (981 lines) has no `1802` entry. mikpe's newlib fork has target branches
  for m32r, m68k, rl78, visium, xstormy16, iq2000, mn10300, mcore and moxie,
  but none for cdp1802 (`git ls-remote`).
- **libgcc had been built against mikpe's headers.** ADR 0002's script
  installed those headers into the sysroot before building GCC. As a result
  `libgcc.a(_eprintf.o)` referenced `__libc_stderr`, a symbol private to
  mikpe's libc (its `stdio.h` defines `stderr` that way). The libgcc linked
  into NuttX therefore carried a dependency on that libc's ABI.

## Options considered

1. **Port newlib** (crt0, libgloss syscalls, setjmp, soft-float config).
   Weeks of work for something NuttX does not use, and newlib's stdio is large
   (H6). Rejected.
2. **Keep libgcc as it was.** It works (NuttX never pulls `_eprintf.o`), but the
   dependency is hidden and would surprise an upstream reviewer. Rejected.
3. **Build GCC with `--without-headers --with-newlib`**, which makes libgcc build
   with `inhibit_libc` and no target headers at all. mikpe's libc is installed
   *after* GCC, only for the toolchain validation programs.

## Decision

Option 3. In a scratch build, then in `toolchain/build-toolchain.sh`:

- `inhibit_libc = true` in `build-gcc/gcc/Makefile`;
- libgcc's only external references are standard C symbols that NuttX's libc
  provides: `abort free malloc memcpy memset strlen` (from `emutls.o`,
  `unwind-dw2-fde.o` and the `-ftrapv` helpers);
- the same member list as before (`ar t` diff is empty);
- `softfloat.elf` and `abi.elf` have byte-identical loadable images, and
  `test-step-01.sh`/`test-step-02.sh` pass.

`--with-newlib` is only GCC's "no target libc headers yet" switch; no newlib code is fetched or used.

## Consequences

- NuttX binaries contain only Apache-2.0 NuttX code plus libgcc (GPL-3.0 with
  the GCC Runtime Library Exception), the same as every other GCC-built
  NuttX target.
- mikpe's libc remains a *build-time test dependency* of the toolchain
  (Step 01 validation and the simulator audit). It is fetched from its
  upstream and never copied into this repository or linked into NuttX.
- NuttX must provide start-up code and the NCRT call/return routines itself
  (Step 06), as already planned.

## How to revisit

Once NuttX boots (Step 06+), the Step 01/02 validation programs could run on
NuttX instead of mikpe's libc, which would drop the libc from the toolchain
build entirely. Record that with a new ADR if it is done.
