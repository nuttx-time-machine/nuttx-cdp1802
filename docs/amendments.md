# Contract amendments

`CONTRACT.md` is never edited. This file records changes to it. Each entry
has a status: **Proposed** (waiting for Alan), **Accepted** or **Rejected**.

## A1 — Workspace location (**Accepted** by Alan, 2026-09-29)

- **Contract:** `~/nuttxspace/cdp1802/`.
- **Actual:** `/home/alan/NUTTX_CDP1802/`, the directory where Alan placed `CONTRACT.md` and started the agent.
- **Why:** `~/nuttxspace/` already holds many unrelated NuttX trees and patches. Alan asked for NuttX and apps to be freshly cloned from GitHub instead of reusing anything on the machine. A separate directory avoids any accidental mixing. Nothing in the repo depends on the absolute path; all scripts resolve paths relative to the repo root.

## A2 — Submodule remotes point at upstream, not at forks (**Accepted** by Alan, 2026-09-29)

- **Contract:** `nuttx/` and `apps/` are submodules of *forks*, on branch `cdp1802-port`.
- **Actual:** `.gitmodules` points at `https://github.com/apache/nuttx.git` and `https://github.com/apache/nuttx-apps.git`. The `cdp1802-port` branches exist only in the local submodule clones.
- **Why:** creating public forks and pushing to them is an outward-facing action. The agent does not take it without Alan's approval (§10: no contacting third parties or publishing).
- **Consequence (important):** until the branches are pushed somewhere, a *fresh* clone of the meta repo cannot fetch the port commits, which breaks §5.7 reproducibility for other machines. On this machine everything reproduces.
- **To resolve:** Alan creates the forks (e.g. `github.com/acassis/nuttx`) and pushes `cdp1802-port`. The agent then runs `git submodule set-url` in one commit.

## A3 — Toolchain triplet spelling (**Accepted with change** by Alan, 2026-09-29)

- **Contract:** mentions `cdp1802-elf` / `cdp1802-elf-size`.
- **Actual:** tools are installed as `cdp1802-unknown-elf-*`. That is the canonical triplet `config.sub` produces for `cdp1802-elf`. mikpe's libc Makefile, the sim1802 install name (`cdp1802-unknown-elf-sim`) and its DejaGnu board all use it.
- **Why:** it matches upstream conventions, so mikpe's libc and simulator work without patching.
- **Alan's decision:** provide `cdp1802-elf-*` names. `build-toolchain.sh` now
  creates a `cdp1802-elf-<tool>` symlink for every `cdp1802-unknown-elf-<tool>`.
  The GCC driver resolves its install path through the symlink. A hello
  built with `cdp1802-elf-gcc` has a byte-identical image to one built with
  `cdp1802-unknown-elf-gcc`. NuttX's `Toolchain.defs` will use the
  `cdp1802-elf-` prefix (Step 05). The canonical triplet stays
  `cdp1802-unknown-elf`, because mikpe's libc and the simulator's DejaGnu
  board expect it.

## A4 — Simulator fork location (Accepted by Alan, 2026-09-29)

- Alan approved forking sim1802 (ADR 0003) and asked for a local git
  repository that he will publish on GitHub later. The fork is the
  `simulator/` submodule, with branch `cdp1802-nuttx` based on mikpe/sim1802
  `3b28ed21695b`.
- Until it is published, `.gitmodules` points at mikpe's repository, which
  does not contain the fork commits, and `toolchain/VERSIONS` builds the
  simulator from the submodule working tree (`SIM_SRC=simulator`).
- To publish: push `cdp1802-nuttx` to the new repository, then
  `git submodule set-url simulator <url>` and commit. Nothing else changes.

## A5 — Revised plan after the Step 04 gate (Accepted by Alan, 2026-09-29: options A, B, C and a 48/16 profile)

The minimal kernel does not fit HW32/32 (journal step-04). Alan chose:
code banking (A), compiler improvements with mikpe (B) and local 32-bit time
plus trimming (C), and asked to consider a 48 KiB ROM / 16 KiB RAM split.
The step plan changes as follows:

| Step | Contract | Revised |
|------|----------|---------|
| 05 | skeleton links an ELF | unchanged; links in the **SIM64** profile (with `SYSTEM_TIME32`: 62 KB ROM, 3.5 KB RAM) |
| 06 | boot banner | unchanged, in SIM64 |
| **06b** (new) | — | **Code banking**: sim1802 fork bank window, placement/stub tool, far-call trampoline and bank return stack, profile HWB (32 KiB fixed ROM + 16 KiB window + 16 KiB RAM). Exit: the Step 06 banner boots from a banked ROM image, plus a stress test of cross-bank calls with interrupts. |
| 07–10 | as in the contract | on the **HWB** profile |

The contract's feasibility profile HW32/32 is kept in the size budget as the
reference answer ("does not fit"). HW48/16 (flat) and HWB are added.
