# NuttX on the RCA CDP1802 (COSMAC)

This repository ports [Apache NuttX](https://nuttx.apache.org) to the RCA
CDP1802, the 1976 8-bit COSMAC microprocessor. It uses Mikael Pettersson's
GCC/binutils port and runs in the `sim1802` simulator.

It has two goals of equal weight (see [`CONTRACT.md`](CONTRACT.md)):

1. **A working port**: NuttX boots in the simulator, preempts threads and passes a reduced `ostest`.
2. **A course**: the git history and `docs/` teach how to port NuttX to *any* new CPU, with the CDP1802 as the worked example.

## Status

| Step | Tag | What it delivers | State |
|------|-----|------------------|-------|
| 00 | `step-00-bootstrap` | Meta repo, layout, pinned NuttX/apps | done |
| 01 | `step-01-toolchain` | Toolchain built from pinned SHAs, hello + soft-float in the simulator, ABI documented | done |
| 02 | `step-02-sim-audit` | Simulator capability audit (**GATE**) | report done — **waiting for decision** |
| 03 | `step-03-board` | Virtual board definition, sim1802 fork | done — **ADR 0005 awaiting acceptance** |
| 04 | — | Size feasibility (**GATE**) | — |
| 05 | — | Architecture skeleton links | — |
| 06 | — | Boot banner from `nx_start()` | — |
| 07 | — | Interrupts and system timer | — |
| 08 | — | Context switching | — |
| 09 | — | Serial driver and `ostest` | — |
| 10 | — | NSH or infeasibility report (**GATE**) | — |
| 11 | — | CI, final docs, upstream-readiness report | — |

## Reproduce

```sh
git clone --recurse-submodules <this repo> cdp1802 && cd cdp1802
toolchain/build-toolchain.sh          # ~30-60 min: Erlang/OTP, binutils, GCC, libc, sim1802
. scripts/env.sh
scripts/test-step-01.sh               # or any scripts/test-step-NN.sh
git checkout step-NN-<name> && git submodule update   # go to any step
```

Once NuttX builds (Step 05 onward), these commands are added:
`scripts/build.sh <board:config>` and `scripts/run.sh <elf>`.

> **Note:** see [amendment A2](docs/amendments.md). Until the `cdp1802-port`
> branches are pushed to public forks, the submodule commits exist only on the
> machine where the port is developed.

## How to read this repository as a course

Read each step in this order, then check out its tag:

1. **The journal entry** `docs/journal/step-NN.md`: what was attempted, what failed, with real command output.
2. **The ADRs** created in that step (`docs/adr/`): *why* each choice was made, and which alternatives were rejected.
3. **The code**: `git checkout step-NN-<name>`, then `git -C nuttx log --oneline` shows the port commits of that step. Each commit message explains the reason for the change.
4. **The porting-guide chapter** that the step feeds (`docs/porting-guide/`): the generic lesson, with the CDP1802 as boxed examples.
5. **Run the step test** `scripts/test-step-NN.sh` to see it work.

Suggested path through the material:

| Phase | Steps | Read |
|-------|-------|------|
| Know your tools | 00–01 | guide ch. 1, 3; `docs/cdp1802/primer.md`, `abi.md` |
| Know your target | 02–03 | guide ch. 4; `docs/cdp1802/board-sim1802.md` |
| Will it fit? | 04 | guide ch. 2, 15; `docs/size-budget.md` |
| Skeleton to boot | 05–06 | guide ch. 5–8 |
| Make it an OS | 07–08 | guide ch. 9–12; `docs/cdp1802/interrupts.md`, `context.md` |
| Prove it | 09–10 | guide ch. 13–14 |
| Ship it | 11 | guide ch. 16; `docs/upstream-readiness.md` |

## Layout

```
CONTRACT.md            the work contract (never edited; see docs/amendments.md)
nuttx/  apps/          submodules, branch cdp1802-port
toolchain/             VERSIONS (pinned SHAs), build-toolchain.sh, Dockerfile
scripts/               env.sh, build.sh, run.sh, test-step-NN.sh
docs/porting-guide/    the generic porting guide
docs/cdp1802/          CPU primer, ABI, board, context, interrupts, performance
docs/adr/              architecture decision records
docs/journal/          one entry per step
docs/toolchain-issues/ minimal reproducers for toolchain bugs
docs/size-budget.md    size table per step
docs/VERSIONS.md       pinned NuttX/apps commits
```
