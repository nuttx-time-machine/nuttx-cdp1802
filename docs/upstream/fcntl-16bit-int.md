# Upstream patch: `include/fcntl.h` open flags on 16-bit `int`

**Status:** prepared, **not sent**. Alan submits it.
**Patch:** `0001-include-fcntl.h-keep-open-flags-within-a-16-bit-int.patch`
**Base:** apache/nuttx `master` at `6bec3b6f5b` (2026-09-30). The file is
unchanged there since the port's pinned base.
**Local branch:** `upstream/fcntl-16bit-int` in `nuttx/`, one commit on
`origin/master`.
**Decision record:** ADR 0021; journal step-10, problem #2.

## How to submit (for Alan)

```sh
cd nuttx
git push <your-fork> upstream/fcntl-16bit-int
# open a PR against apache/nuttx master with the description below
```

To refresh it after master moves:
`git rebase origin/master upstream/fcntl-16bit-int`, then re-run
`docs/upstream/compare-open-flags.sh origin/master`.

## PR description (draft)

### Summary

`O_DIRECTORY`, `O_NOFOLLOW`, `O_NOATIME`, `O_CLOEXEC`, `__O_SYNC`,
`O_PATH` and `__O_TMPFILE` are defined as `1U << 16` to `1U << 22`.

Where `int` is 16 bits (AVR, for example), these shifts exceed the width
of the type:
- GCC evaluates them to 0;
- the `-Wshift-count-overflow` warning is hidden, because `include/` is
  a system include directory;
- the `oflags` argument of `open()` is an `int`, so it could not carry
  bits 16 and higher anyway.

The consequences on such targets:
- `opendir()` opens directories without `O_DIRECTORY`, so opening a
  mount point fails. NSH's `ps` says "Could not open /proc (is procfs
  mounted?)".
- `O_CLOEXEC` and `O_NOFOLLOW` silently do nothing.

This patch changes the flags only when `UINT_MAX` is `0xffff`:
- `O_DIRECTORY`, `O_CLOEXEC` and `O_NOFOLLOW` use the unused bits 2, 3
  and 4;
- `O_NOATIME` and `__O_SYNC` are 0, so `O_SYNC` falls back to `O_DSYNC`;
- `O_PATH`, `__O_TMPFILE` and `O_TMPFILE` are not defined. Code that
  needs them then fails to build, instead of opening with the wrong
  flags. Nothing in nuttx or nuttx-apps uses them;
- `_O_MAXBIT` is 15.

### Impact

- **32- and 64-bit targets: no change.** Every `O_*` value is identical.
  This was checked by compiling all 28 constants with the old and the new
  header for x86_64, i386 and ARM (`docs/upstream/compare-open-flags.sh`).
  Linux compatibility of the flag values is unchanged.
- **16-bit-`int` targets (AVR):**
  - `opendir()` on mount points works;
  - `O_CLOEXEC` and `O_NOFOLLOW` take effect;
  - the values of these three flags differ from Linux's. FUSE uses only
    the access mode, and hostfs uses its own `NUTTX_O_*` constants, so
    neither is affected;
  - code using `O_PATH` or `O_TMPFILE` will no longer build. It could not
    work before either.
- The public header gains `#include <limits.h>`, which `<stdint.h>`
  already includes.

### Testing

- `compare-open-flags.sh origin/master` output:
  - x86_64, i386, arm: 28 constants, 0 differ;
  - avr (atmega1284p): upstream `O_DIRECTORY`/`O_NOFOLLOW`/`O_CLOEXEC` =
    0x0; patched 0x4/0x10/0x8.
- Built from `origin/master` with and without the patch:
  - `arduino-mega2560:nsh` (avr-gcc) builds with no warnings both ways;
  - `sim:nsh` (x86_64) builds both ways and runs `ls /dev` and `ps`.
  - `avr32dev1:nsh` fails to build both with and without the patch; the
    host lacks the AVR32 toolchain. AVR32 has a 32-bit `int` in any case.
- `tools/checkpatch.sh -g HEAD~1..HEAD`: all checks pass.
- On an out-of-tree CDP1802 port (16-bit `int`, big-endian), NSH's `ps`
  works with the patch and fails without it.
