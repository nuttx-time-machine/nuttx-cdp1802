# Step 00 — Bootstrap

**Goal:** create the meta repository and its layout, add NuttX and apps as
submodules pinned to one commit, and write the README "how to read" section.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5), in Claude Code.

## What was done, in order

1. Read `CONTRACT.md` (v1.0). Alan placed it in `/home/alan/NUTTX_CDP1802/`,
   not in `~/nuttxspace/cdp1802/`, and asked for NuttX and apps to be freshly
   cloned from GitHub rather than taken from existing trees on the machine.
   `~/nuttxspace/` already contains many unrelated trees and patches, so the
   meta repo lives where the contract was placed → [amendment A1](../amendments.md).
2. Checked the host:
   ```
   $ nproc; free -g | head -2; df -h /home | tail -1
   16
   Mem:  62 total
   /dev/nvme0n1p4  732G  643G   53G  93% /home
   $ which erl rebar3        # nothing: Erlang is not installed
   $ sudo -n true
   sudo: a password is required
   ```
   There is no Erlang and no root access. The simulator (Erlang) therefore
   needs Erlang/OTP built from source into the toolchain prefix (handled in Step 01).
3. Read mikpe's toolchain intro gist (`70761a8b05a9e568d7ea819aa832dbdd`,
   "RCA CDP1802 toolchain: Intro"). Findings used later:
   - binutils is on branch `cdp1802` of `mikpe/binutils-gdb`, and GCC on
     `mikpe/gcc` branches `gcc14-cdp1802`/`gcc15-cdp1802`
     (`git ls-remote` also shows `gcc16-cdp1802` and `cdp1802`).
   - libc is a separate repo, `mikpe/cdp1802-elf-libc`, with a custom start-up and "NCRT" call/return routines.
   - The simulator has "a simple I/O controller with console, timer, and interrupt control".
4. `git init` the meta repo and created the §4 layout.
5. Added the submodules, cloned from GitHub:
   ```
   $ git submodule add https://github.com/apache/nuttx.git nuttx
   $ git submodule add https://github.com/apache/nuttx-apps.git apps
   nuttx c7080cbdfebaecf27c7325e7c7bfee9353b9eefa 2026-09-29 arch/arm/imxrt: Small cleanups for OCOTP headers
   apps  b66303e26aa537dd74d6abaeeeded81c151a7e35 2026-09-28 examples/tinygl: add TinyGL gears demo
   ```
   Created a local `cdp1802-port` branch in each submodule at those commits.
   There is no public fork yet → [amendment A2](../amendments.md).
6. Checked the naming proposal for clashes:
   ```
   $ grep -rni cosmac nuttx/ apps/ | wc -l
   0
   ```
   Wrote [ADR 0001](../adr/0001-naming.md) (`arch/cosmac`, chip `cdp1802`, board `sim1802`).
7. Pinned the toolchain sources (`toolchain/VERSIONS`) with `git ls-remote`.
   Annotated tags (OTP, rebar3) are pinned by their *peeled* commit SHA so that
   `git rev-parse HEAD` can verify them.
8. Wrote `README.md`, `docs/VERSIONS.md`, `docs/amendments.md`,
   `docs/size-budget.md`, the porting-guide index and `scripts/test-step-00.sh`.

## Test

```
$ scripts/test-step-00.sh
PASS: step 00
```

## Measurements

None (no NuttX image exists yet).

## Hypotheses

None addressed in this step.

## Open questions for Alan

- A1 (workspace path), A2 (fork location for `cdp1802-port`) and A3 (triplet
  spelling) are proposed amendments that need your decision. A2 affects
  reproducibility on other machines.
- `cdp1802-elf-libc` is GPL-3.0. It will be used only to validate the toolchain
  (Step 01) and will never be linked into NuttX. NuttX will need its own
  Apache-2.0 call/return runtime ("NCRT") and start-up code, written from the
  ABI description and not copied. This is flagged as a licensing point (§9).

## Time spent

About 0.5 h wall-clock (including the network clones).
