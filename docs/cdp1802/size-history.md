# Why NuttX grew since 2016, and what the CDP1802 can recover

Alan: "I think around 2016 NuttX used to fit in 32KB Flash, please
investigate which features or modifications increased its size and what
we can do to recover space to let it fit inside 48KB ROM."
Measured 2026-09-30.

## Method

NuttX 7.18 (2016-10-08) and the port's current tree (apache/nuttx of
2026-09-29 plus the port), each with its matching apps release. The
same board configurations, built with the same compilers (the host's
avr-gcc and arm-none-eabi-gcc). The only change to the 2016 tree: the
`-nostartfiles`/`-nodefaultlibs` link flags, which today's `ld` rejects.

Two targets:
- **AVR ATmega1284P** (`moteino-mega:nsh`): 16-bit `int`, like the
  CDP1802;
- **ARM Cortex-M3** (`stm32f103-minimum`): the "32 KB" claim.

Growth was attributed by comparing function sizes (`nm -S`), grouped by
subsystem, and dated with `git log -S` on the upstream history.

## Results

| Build (code + initialized data, bytes) | 2016 (7.18) | 2026 | Growth |
|---|---:|---:|---:|
| AVR `moteino-mega:nsh` | 48 977 | 73 128 | +49 % |
| ARM `stm32f103-minimum:nsh` | 38 787 | 52 360 | +35 % |
| ARM smallest NSH: 2016 `minnsh`; 2026 the `sim1802:nshflat` options | 13 008 | 31 588 | ×2.4 |
| CDP1802 smallest NSH (`sim1802:nshflat`, flat) | — | 65 857 | |

So NuttX did fit in 32 KB in 2016: the ARM `nsh` in 38.8 KB, and a
minimal NSH in 13 KB. That minimal NSH used `CONFIG_NFILE_DESCRIPTORS=0`:
no file system at all, with NSH talking to the console through low-level
streams. It also disabled `poll()` and signals.

The CDP1802 code is about 2.1 times the ARM code for the same
configuration. At the 2016 kernel's size, the CDP1802 NSH would be about
27 KB.

### Where the AVR growth is (`moteino-mega:nsh`, code only)

| Subsystem | 2016 | 2026 | Growth |
|---|---:|---:|---:|
| semaphores, mutexes, rwsem, atomics | 662 | 7 824 | +7 162 |
| file descriptors and VFS | 4 420 | 11 182 | +6 762 |
| serial driver | 2 816 | 6 782 | +3 966 |
| task creation, spawn, groups | 2 116 | 5 584 | +3 468 |
| memory manager | 2 846 | 5 110 | +2 264 |
| printf, streams | 1 960 | 4 196 | +2 236 |
| scheduler core | 2 028 | 3 842 | +1 814 |
| `poll()` (can no longer be disabled) | 0 | 1 500 | +1 500 |
| time, clock, watchdogs | 3 482 | 4 618 | +1 136 |
| assert, panic, syslog | 2 750 | 3 570 | +820 |
| NSH, signals, strings, other | | | −7 830 (the config parts differ) |
| **total** | 45 772 | 70 686 | +24 914 |

### When it happened (upstream commits)

| Date | Commit | Change |
|---|---|---|
| 2018-08 | `e2e0911bc4` | mutex wrappers over semaphores |
| 2019-02 | `a64869aa67` | "`CONFIG_NFILE_DESCRIPTORS=0` can no longer be used to disable the file system"; NSH's file-less console removed from apps |
| 2019-05 | `b49be4bb20` | `CONFIG_DISABLE_POLL` removed |
| 2021-03 | `e96c8b9283` | files allocated dynamically (growable fd list) |
| 2022-04 | `7f8bec7070` | `mm_map` list in every task group |
| 2022-10 | `1280a2a8f9` | the init task is started with `task_spawn` |
| 2023-08 | `6e7115ca09` | delayed-free list in the heap |
| 2023-11 | `42427e9e29` | task file setup goes through spawn file actions |
| 2024-08 | `befe29801f` | semaphores become atomic operations (fast and slow paths) |
| 2024-09 | `761ee81956` | `readv`/`writev` move into the kernel; all I/O becomes vectored |
| 2024-09 | `09a9611ae9` | the inode lock becomes a reader/writer semaphore |
| 2024-11 | `00010089b8` | the serial driver adapts to the iovec API |
| 2026-05 | `1b3af76bf3` | `long long` always in printf (undone locally by ADR 0025) |

Most of these made NuttX faster, safer on SMP, or more POSIX-like, and
each costs a few hundred bytes to a few KB. None has an option to turn it
off, because 32-bit targets hardly notice.

## What these features cost in the CDP1802 image

Measured per function in the link map of `sim1802:nshflat` (flat,
64 430 bytes of code and read-only data):

| Feature (since) | Bytes |
|---|---:|
| atomic semaphores: slow paths, tick- and clock-wait, atomics (2024) | 2 839 |
| spawn file actions in task file setup, with the scheduler-parameter chain it pulls in (2023) | 2 474 |
| directories opened as files: `dir_*`, `asprintf` (O_DIRECTORY) | 2 148 |
| assert/panic path: `_assert`, `up_mdelay`, notifiers | 1 973 |
| vector I/O: `readv`/`writev`, uio (2024) | 1 942 |
| dynamic fd list: extend, copy, dupfile (2021) | 1 911 |
| heap delayed free (2023) | 1 032 |
| inode rwsem (2024) | 749 |
| `mm_map` (2022) | 279 |
| **sum** | **15 347** |

The already-applied reductions (serial driver, init spawn, signals,
`long long`) are covered in journal step-10 and ADRs 0024–0025.

## What we can do

`sim1802:nshflat` is 65 857 bytes; 48 KiB is 49 152. That is
**16 705 bytes** to recover, more with a margin.

### Tier 1: small-configuration options, one per feature

Each is a Kconfig option that restores a 2016-style implementation for
small, non-SMP configurations, with default behaviour unchanged. Each is
a common-code change that needs its own ADR and Alan's approval. Savings
are estimated from the table above.

| Change | Est. saving |
|---|---:|
| Semaphores: plain interrupt-disable implementation (no atomic fast/slow paths) when `!SMP` | ~2 000 |
| Task file setup: spawn file actions only when a spawn has actions (the plain path does not need the scheduler-parameter chain) | ~2 000 |
| `_assert` reduced to a message and `PANIC` without debug features | ~1 500 |
| Fixed-size fd table (no extend/copy) | ~1 500 |
| `opendir` support optional (no directories-as-files) | ~2 000 |
| Direct `read`/`write` for single buffers (no uio for the common case) | ~1 000 |
| Inode lock as a mutex when `!SMP` | ~700 |
| Heap delayed free off when `MM_FREE_DELAYCOUNT_MAX=0` | ~800 |
| `mm_map` only with `MM_MAP`/mmap | ~280 |
| **Tier 1 total** | **~11 800** |

That brings the image to about 54 KB, still about 5 KB over.

### Tier 2: a console without the file system (2016's `NFILE_DESCRIPTORS=0`)

Removed upstream in 2019. Bringing it back means kernel conditionals
around the whole VFS, and an NSH console on low-level streams (apps
change). The VFS in the image is 14.3 KB; a console-only replacement
might save about 10 KB. This is large, invasive and unlikely to be
accepted upstream.

### Tier 3: the compiler

- **Toolchain issue 0002.** The `-fno-split-wide-types` workaround costs
  about 5.4 KB (measured at Step 04). Fixing the GCC bug removes it. The
  report for mikpe is prepared, but not sent.
- **Code density** for field access and 32-bit arithmetic. No indexed
  addressing means 10 instructions per 16-bit field load. This shrinks
  everything, and is the largest lever, but it is backend work.

### Combinations that reach 48 KiB

- **Tier 1 + the issue 0002 fix:** about 65.9 − 11.8 − 5.4 = **48.7 KB**.
  Borderline: it needs a few more KB from further small items or from
  Tier 3 code density.
- **Tier 1 + Tier 2:** about 44 KB. It fits, but with large common-code
  divergence.
- **Tier 1 + issue 0002 + a modest code-density gain** (5–10 % from
  backend work): about 44–46 KB.

## Reproduce

2016 builds: git worktrees of `nuttx-7.18` from the nuttx and apps
repositories. Configure with `tools/configure.sh -a ../apps
moteino-mega/nsh` or `stm32f103-minimum/{nsh,minnsh}`, remove
`-nostartfiles`/`-nodefaultlibs` from the ARM Make.defs, then run `make`.

2026 builds: `scripts/build.sh moteino-mega:nsh` and
`scripts/build.sh stm32f103-minimum:nsh`. The smallest ARM NSH uses the
`sim1802:nshflat` options as a fragment (`BUILD_FRAGMENT`).
