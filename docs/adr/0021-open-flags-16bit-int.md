# 0021 — Common code: open() flags must fit in a 16-bit int

Status: Proposed (agent). This is a common-code change and needs Alan's
review.
Date: 2026-09-29
Step: step-10

## Context

In NSH, `ps` printed its header and then
`nsh: ps: Could not open /proc (is procfs mounted?)`, although `free` read
`/proc/meminfo` from the same mount. `ps` calls `opendir("/proc")`, and
`opendir()` calls `open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)`.

`include/fcntl.h` defines the flags as unsigned shifts:
`O_DIRECTORY (1U << 16)`, `O_NOFOLLOW (1U << 17)`, `O_NOATIME (1U << 18)`,
`O_CLOEXEC (1U << 19)`, `__O_SYNC (1U << 20)`, `O_PATH (1U << 21)` and
`__O_TMPFILE (1U << 22)`. Where `int` is 16 bits, these shifts are
undefined behaviour, and the CDP1802 GCC folds each one to 0. We checked
this by compiling `return 1U << 16;`, which gives `ldi 0` for both bytes
and a `-Wshift-count-overflow` warning. NuttX passes `include/` with
`-isystem`, so the warning does not appear when these macros are used
elsewhere.

With 16-bit `int`:
- `opendir()` opened the mount point as a file instead of as a directory,
  so procfs answered ENOENT;
- `O_CLOEXEC`, `O_NOFOLLOW` and the other flags listed above silently did
  nothing.

Even if the constants were widened, `open()`'s `int oflags` parameter and
`struct file`'s `int f_oflags` field cannot hold bit 16 or higher. Making
them `long` or `int32_t` would change the POSIX signature and the whole
VFS.

Bits 2, 3 and 4 of the flag word are unused: bits 0–1 are the access mode,
and bits 5–15 hold `O_TEXT` through `O_LARGEFILE`. We searched the kernel,
libc and apps: nothing uses `O_PATH` or `O_TMPFILE`, and `O_NOATIME` is
used only as a hint in v9fs.

## Decision

`include/fcntl.h`, for `UINT_MAX <= 0xffff` only:
- `O_DIRECTORY` is bit 2, `O_CLOEXEC` is bit 3, `O_NOFOLLOW` is bit 4;
- `O_NOATIME` and `__O_SYNC` are 0, so `O_SYNC` falls back to `O_DSYNC`;
- `O_PATH`, `__O_TMPFILE` and `O_TMPFILE` are not defined, so code that
  needs them fails to compile instead of silently misbehaving;
- `_O_MAXBIT` is 15.

The header now includes `<limits.h>`. Where `int` is wider than 16 bits,
nothing changes: the same definitions are kept, and only their layout
moved under `#if`. The change is one commit of its own.

## Consequences

- `opendir()` works, so `ps` works on the CDP1802, and `O_CLOEXEC` and
  `O_NOFOLLOW` now take effect (journal step-10).
- On 16-bit-`int` targets the flag values differ from Linux's for these
  three flags. The header's comment says values are aligned with Linux
  "where possible". FUSE only relies on the access mode, and hostfs uses
  its own `NUTTX_O_*` constants, so neither is affected.
- AVR has 16-bit `int` too, and had the same silent failures. That is an
  upstream report candidate (Step 11).

## How to revisit

If NuttX ever widens `oflags` to a 32-bit type, drop the 16-bit branch.
