# 0002 — How the toolchain is built, and what mikpe's libc is used for

Status: Proposed (agent); **partially superseded by [0004](0004-libc-independence.md)** (libgcc is now built without target libc headers)
Date: 2026-09-29
Step: step-01-toolchain

## Context

The contract requires mikpe's binutils/GCC and the sim1802 simulator, built
reproducibly (CONTRACT §5.7), by buildcross or a manual build chosen via ADR.
Facts found at Step 01:

- `buildcross` at `1af64499e35f` has no cdp1802 target. `grep -i 1802` over its
  `README.md` and `buildcross` script returns nothing.
- The simulator is an Erlang escript. The host has no Erlang, and the agent has
  no root access (`sudo -n true` → "a password is required").
- `mikpe/gcc` has branches `gcc14-cdp1802`, `gcc15-cdp1802`, `gcc16-cdp1802` and
  `cdp1802` (master). The gist names gcc-14/15 as the supported bases.
- `cdp1802-elf-libc` is **GPL-3.0** and contains the start-up code and the NCRT
  call/return routines.

## Options considered

1. **buildcross.** Not possible without writing a cdp1802 recipe into a GPL-3.0
   tool we don't own.
2. **Manual build, driven by our own script (`toolchain/build-toolchain.sh`)**,
   with every source fetched at a pinned SHA, including Erlang/OTP (built into
   the prefix) and rebar3.
3. **Distribution Erlang packages** (apt) instead of building OTP. Needs root, and
   the OTP version would depend on the distro. Kept only for the Docker image
   (which could use it) but not used, so that host and container match.

GCC branch: `gcc15-cdp1802` (latest *release* series named in the gist) versus
`cdp1802`/`gcc16-cdp1802` (development trunks, more churn).

## Decision

- Option 2. A single idempotent script with per-stage stamps. The same script
  runs inside `toolchain/Dockerfile`.
- GCC `gcc15-cdp1802`, configured with:
  - `--with-arch=1802`, so the default multilib is `1802`, where mikpe's libc
    Makefile installs `crt0.o`/`libc.a`. Without it the first link failed with
    `cannot find crt0.o` (journal step-01).
  - `--disable-gcov`. libgcov does not compile against mikpe's minimal libc
    headers (`intptr_t` undeclared in `libgcov.h`), and NuttX does not need it.
  - `--enable-languages=c`, `--disable-{shared,threads,nls,libssp,...}`.
- Erlang/OTP `OTP-28.5.0.7` (within the 27–29 range tested by sim1802 CI) and
  rebar3 `3.27.0` (the version sim1802's Makefile expects).
- **mikpe's libc is used only to link the Step 01 validation programs.** It
  is never linked into NuttX. NuttX gets its own Apache-2.0 start-up and
  NCRT routines, written from `cdp1802-abi.txt` (a permissively licensed
  document) and not from `crt0.S`.
- libgcc *is* linked into NuttX (GPL-3.0 with the GCC Runtime Library
  Exception, the same situation as every other GCC-built NuttX target).

## Consequences

- Build time on the development machine (16 cores): OTP ≈ 2.5 min, binutils +
  GCC + libc + sim ≈ 3.5–5 min (journal step-01).
- The install prefix is `toolchain/install/`, and the triplet is
  `cdp1802-unknown-elf` (amendment A3).
- NuttX needs NCRT routines in `arch/cosmac` (Step 06).

## How to revisit

Moving to `gcc16-cdp1802` or to a newer SHA means: update `toolchain/VERSIONS`,
rebuild, run all step tests, and record the size delta in the size budget. If
mikpe adds a buildcross recipe, switch to it with a new ADR that supersedes this one.
