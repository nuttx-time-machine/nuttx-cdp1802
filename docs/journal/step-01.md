# Step 01 — Toolchain

**Goal:** build binutils and GCC for the CDP1802 and the sim1802 simulator from
pinned sources, run a C hello and a soft-float test in the simulator, and
document the ABI (hypothesis H7) with evidence.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## What was done, in order

1. **Discovered the sources** (the contract says not to assume branch names).
   ```
   $ git ls-remote https://github.com/mikpe/binutils-gdb.git | grep 1802
   27ba481c4dcf...  refs/heads/cdp1802        (+ bu244..bu247-cdp1802)
   $ git ls-remote https://github.com/mikpe/gcc.git | grep 1802
   da1fefb3541c...  refs/heads/cdp1802
   b877e2958ea2...  refs/heads/gcc14-cdp1802
   8b18811140ea...  refs/heads/gcc15-cdp1802
   9e4d7d09ab0c...  refs/heads/gcc16-cdp1802
   ```
   The gist names gcc-14/15. `gcc15-cdp1802` was chosen (ADR 0002). libc
   (`mikpe/cdp1802-elf-libc`, GPL-3.0) and the simulator (`mikpe/sim1802`,
   Apache-2.0, Erlang) are on `master`. The sim1802 CI matrix tests OTP 27/28/29
   (`.github/workflows/test.yml`).
2. **buildcross checked:** it has no cdp1802 target (`grep -ci 1802` on
   `README.md` and `buildcross` returns 0). A manual build was chosen → ADR 0002.
3. **Wrote `toolchain/build-toolchain.sh`**: one stage each for OTP, rebar3,
   binutils, libc headers, GCC, libc and sim1802, with SHA-keyed stamps.
4. **First run** failed after OTP built:
   ```
   install: cannot create regular file '.../toolchain/install/bin/rebar3': No such file or directory
   ```
   Fix: `install -D`. (OTP + rebar3 took 2 min 22 s wall-clock.)
5. **Second run:** binutils OK. GCC failed in libgcc's gcov part:
   ```
   ../../../../gcc/libgcc/libgcov.h:502:56: error: 'intptr_t' undeclared ...
   make[3]: *** [Makefile:936: _gcov_merge_time_profile.o] Error 1
   ```
   mikpe's libc headers (installed in the sysroot so libgcc can build) have no
   `stdint.h`, and libgcov needs `intptr_t`. NuttX does not use gcov, so the
   fix is `--disable-gcov`, not patching anything. (Run time: 4 min 50 s.)
6. **Third run:** everything built (3 min 42 s):
   ```
   cdp1802-unknown-elf-gcc (GCC) 15.3.1 20260919
   GNU assembler (GNU Binutils) 2.47.50.20260919
   ```
   The first link then failed:
   ```
   ld: cannot find crt0.o: No such file or directory
   ld: cannot find -lc: No such file or directory
   ```
   `gcc -print-multi-lib` shows `.;`, `1802;@march=1802` and `1804;@march=1804`.
   Without `-march` the default multilib is `.`, but the libc Makefile installs
   into `sysroot/usr/lib/1802` and `/1804`. `config.gcc` accepts
   `--with-arch=1802|1804` for this target (`supported_defaults=arch`), so GCC
   was reconfigured with `--with-arch=1802`. The GCC stamp now includes a hash
   of the configure flags, so changing them triggers a rebuild.
7. **Fourth run** (GCC only, 3 min 19 s). `gcc -print-multi-directory` → `1802`.
   All programs link and run:
   ```
   --- hello
   hello, cdp1802
   --- softfloat
   f*1000   = 3375
   d*10000  = 109955
   e*2      = 200001
   f<d      = 1
   softfloat: PASS
   --- abi
   sizeof: short=2 int=2 long=4 llong=8 ptr=2 float=4 double=8
   abi: PASS
   ```
   Each run takes 0.13–0.17 s of wall-clock time. The simulator passes the
   program's exit status through (`return 3` → shell `$?` = 3).
8. **ABI study** (`toolchain/tests/abi.c`, `-Os -S -fno-inline`), written up in
   [`docs/cdp1802/abi.md`](../cdp1802/abi.md). Also read the compiler's own
   `cdp1802-abi.txt` and the relevant pages of RCA MPM-201A (downloaded from
   bitsavers: `components/rca/cosmac/MPM-201A_User_Manual_for_the_CDP1802_COSMAC_Microprocessor_1976.pdf`).
9. **Found an interrupt-safety problem** in the generated code: 16-bit SP
   adjustments are two 8-bit writes, low byte first →
   [`toolchain-issues/0001`](../toolchain-issues/0001-non-atomic-sp-update.md).
   Reproduced with a 6-line function.
10. **Found that H3 is wrong** while reading the instruction table: the 1802 has
    `LSIE` (opcode `CC`, "long skip if IE=1"), [MPM p. 38 and the
    instruction summary on p. 99/103]. So IE *can* be tested.
11. Wrote `scripts/run.sh`, `scripts/test-step-01.sh`, `toolchain/Dockerfile`, ADR 0002.
12. **Docker check.** `docker build -f toolchain/Dockerfile -t nuttx-cdp1802-toolchain:step01 .`
    succeeded in 9 min 40 s, running the same script on Ubuntu 24.04 with
    PREFIX=/opt/cdp1802. `scripts/test-step-01.sh` inside the container prints
    `PASS: step 01`. Host vs container `hello.elf`: **the loadable image is
    byte-identical** (`objcopy -O binary`, sha256 `f065dfdd2768d3ca…` for both).
    The ELF files differ only in DWARF strings, i.e. the libgcc build directory
    (`/home/alan/.../build-gcc/...` vs `/tmp/tc/build-gcc/...` in
    `.debug_line_str`). Possible later fix: build the target libraries with
    `-ffile-prefix-map`. Not done now, because it does not affect what runs.

## Test

```
$ scripts/test-step-01.sh
cdp1802-unknown-elf-gcc (GCC) 15.3.1 20260919
ok: hello
ok: softfloat
ok: abi
ok: exit status
ok: ABI facts
PASS: step 01
```

## Measurements

`cdp1802-unknown-elf-size` (these are validation programs linked with mikpe's
libc, not NuttX):

```
   text    data     bss     dec     hex filename
    938       6      12     956     3bc ret3.elf
    995       6      15    1016     3f8 hello.elf
  12792       6      16   12814    320e abi.elf
  47517      34      16   47567    b9cf softfloat.elf
```

Largest symbols in `softfloat.elf` (`nm -S --size-sort -t d`):

```
00006501 00015198 T __adddf3
00023386 00012012 T __muldf3
00039643 00004821 T _vprintf
00002123 00004037 T __mulsf3
00021699 00001687 T __ltdf2 (= __ledf2)
```

## Hypotheses

| # | Result | Evidence |
|---|--------|----------|
| H1 | **Confirmed** (registers). The 1804 SCAL/SRET part is *confirmed in the simulator source only* (`OP_SCAL 16#80`, `OP_SRET 16#90` in `sim1802_core.erl`); no 1804 datasheet has been read yet. | MPM p. 9 ("sixteen general-purpose 16-bit scratch-pad registers"), Fig. 2 |
| H2 | Interrupt action **confirmed**: X,P→T; 1→P; 2→X; 0→IE [MPM p. 40, Fig. 61]. "R2 must always be a valid SP" is **refuted for GCC code**: SP updates are not atomic (issue 0001). This changes the Step 07 plan: the ISR must not push on R2 first. | abi.md §3, issue 0001 |
| H3 | **Refuted.** IE can be *tested* with `LSIE` (CC) [MPM p. 38, p. 99]. `up_irq_save()` can read IE with `LSIE` instead of keeping a software shadow. DIS/RET are still needed to *change* IE, because they are the only instructions that write it. | MPM p. 38, 41, 65–66 |
| H4 | Not addressed (Step 02). | |
| H5 | Not addressed (Step 08). | |
| H6 | **Early supporting evidence.** A printf + double soft-float test is 47.5 KB; double soft-float alone is about 30 KB. | size table above |
| H7 | **Resolved**: see `docs/cdp1802/abi.md`. SP = R2; fixed R0–R5; caller-saved R6–R10; callee-saved R11–R15; args/returns in R7–R10; NCRT call/return via R4/R5; D clobbered, DF preserved by call/return. | abi.md |

## Open questions for Alan

- **H2/H3 changes the Step 07 plan** (a §9 stop condition). The proposed
  interrupt entry uses R0 (unused without DMA) as a private save pointer and
  `LSIE` to read IE. It will be written up as an ADR in Step 07; this is an
  early heads-up. It is covered again in the Step 02 gate report.
- **Toolchain issue 0001:** do you want the draft report sent to mikpe (by you)?
- The licensing point from Step 00 stands: NuttX gets its own NCRT and start-up
  code; mikpe's GPL libc is used for validation only (ADR 0002).

## Time spent

About 1.5 h wall-clock, of which about 15 min was compile time.
