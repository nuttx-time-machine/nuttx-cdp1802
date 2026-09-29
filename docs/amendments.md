# Contract amendments

`CONTRACT.md` is never edited. This file records changes to it. Each entry
has a status: **Proposed** (waiting for Alan), **Accepted** or **Rejected**.

## A1 — Workspace location (Proposed, 2026-09-29)

- **Contract:** `~/nuttxspace/cdp1802/`.
- **Actual:** `/home/alan/NUTTX_CDP1802/`, the directory where Alan placed `CONTRACT.md` and started the agent.
- **Why:** `~/nuttxspace/` already holds many unrelated NuttX trees and patches. Alan asked for NuttX and apps to be freshly cloned from GitHub instead of reusing anything on the machine. A separate directory avoids any accidental mixing. Nothing in the repo depends on the absolute path; all scripts resolve paths relative to the repo root.

## A2 — Submodule remotes point at upstream, not at forks (Proposed, 2026-09-29)

- **Contract:** `nuttx/` and `apps/` are submodules of *forks*, on branch `cdp1802-port`.
- **Actual:** `.gitmodules` points at `https://github.com/apache/nuttx.git` and `https://github.com/apache/nuttx-apps.git`. The `cdp1802-port` branches exist only in the local submodule clones.
- **Why:** creating public forks and pushing to them is an outward-facing action. The agent does not take it without Alan's approval (§10: no contacting third parties or publishing).
- **Consequence (important):** until the branches are pushed somewhere, a *fresh* clone of the meta repo cannot fetch the port commits, which breaks §5.7 reproducibility for other machines. On this machine everything reproduces.
- **To resolve:** Alan creates the forks (e.g. `github.com/acassis/nuttx`) and pushes `cdp1802-port`. The agent then runs `git submodule set-url` in one commit.

## A3 — Toolchain triplet spelling (Proposed, 2026-09-29)

- **Contract:** mentions `cdp1802-elf` / `cdp1802-elf-size`.
- **Actual:** tools are installed as `cdp1802-unknown-elf-*`. That is the canonical triplet `config.sub` produces for `cdp1802-elf`. mikpe's libc Makefile, the sim1802 install name (`cdp1802-unknown-elf-sim`) and its DejaGnu board all use it.
- **Why:** it matches upstream conventions, so mikpe's libc and simulator work without patching.
