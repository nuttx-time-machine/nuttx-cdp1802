# Pinned NuttX sources

| Component | Upstream | Base commit (upstream master) | Date | Port branch |
|-----------|----------|-------------------------------|------|-------------|
| nuttx | https://github.com/apache/nuttx | `c7080cbdfebaecf27c7325e7c7bfee9353b9eefa` ("arch/arm/imxrt: Small cleanups for OCOTP headers") | 2026-09-29 | `cdp1802-port` |
| nuttx-apps | https://github.com/apache/nuttx-apps | `b66303e26aa537dd74d6abaeeeded81c151a7e35` ("examples/tinygl: add TinyGL gears demo") | 2026-09-28 | `cdp1802-port` |

Both repositories were freshly cloned from GitHub on 2026-09-29 (no local
mirror or pre-existing checkout was reused). The `cdp1802-port` branches start
at the base commits above. Port commits sit on top of them.

The *exact* NuttX/apps commit that belongs to each step is the submodule SHA
recorded in the meta-repo commit behind that step's tag (`git ls-tree <tag> nuttx apps`).

Rebasing onto a newer upstream is an explicit decision. It needs an ADR and a
new row in this table. Every interface list in the porting guide (for example
the `include/nuttx/arch.h` table) was read at the base commit above.

Toolchain pins are in [`toolchain/VERSIONS`](../toolchain/VERSIONS).
