# 0025 — Common code: CONFIG_NO_POSIX_COMPLIANT and printf without long long

Status: Proposed — requested by Alan ("Modify NuttX printf to get rid of
long long, add a CONFIG_NO_POSIX_COMPLIANT…"). This is a common-code change
and needs Alan's review.
Date: 2026-09-30
Step: after step-10

## Context

The smallest flat NSH (`sim1802:nshflat`, ADR 0024) was 72.0 KB, 22.9 KB
over a 48 KiB ROM. After `SYSTEM_TIME32` (ADR 0011), the only 64-bit
arithmetic left in the image was printf's:
- `vsprintf` keeps every integer in `long long`;
- `__ultoa_invert()` divides in 64 bits for every digit;
- that pulls in the port's 64-bit division and libgcc's `__lshrdi3` and
  `__ashldi3`.

NuttX has no option to leave `long long` out of printf.

## Decision

1. **`CONFIG_NO_POSIX_COMPLIANT`**, in the top-level `Kconfig` next to
   `DEFAULT_SMALL`, default n. It gives up POSIX/C conformance to remove
   64-bit arithmetic from the OS:
   - it selects `SYSTEM_TIME32`: `time_t` and `clock_t` are 32 bits;
   - `FS_LARGEFILE` depends on it being off, so `off_t` is 32 bits;
   - `LIBC_LONG_LONG` depends on it being off.
2. **`CONFIG_LIBC_LONG_LONG`** in `libs/libc/stdio/Kconfig`, default y.
   When off:
   - `lib_ultoa_invert.h` defines the conversion types `ultoa_int_t` and
     `ultoa_uint_t` as `long`/`unsigned long` instead of `long long`;
   - `vsprintf` uses them for `%d/%i` and `%u/%o/%x/%p`, and
     `__ultoa_invert()` takes `ultoa_uint_t`;
   - "ll" and "j" arguments are still read with
     `va_arg(ap, long long)`, so the argument list stays in step, but
     only their low 32 bits are printed.

   It is a dependency, not a default. A default applies only to options
   not yet set, so switching `NO_POSIX_COMPLIANT` on in an existing
   configuration would have kept `long long` on; the thread test's
   `noposix` variant showed exactly that.
3. `long long` remains a C type. Code that uses it explicitly still does
   64-bit arithmetic. In `sim1802:nshflat` the remaining 64-bit code is
   all behind options that are off (`LIBC_MEMSET_64BIT`, `FDSAN`,
   `HRTIMER`).

## Consequences

- `sim1802:nshflat` flat: 72.0 KB → 65.9 KB (−6.2 KB). No 64-bit helper
  is linked any more; 16.7 KB over 48 KiB remain.
- With `LIBC_LONG_LONG` on, which is every configuration that does not
  set the option, the code is unchanged: the types are the same as
  before.
- Test: the Step 08 thread test prints every integer conversion at edge
  values, including `long long` above 32 bits followed by one more
  argument. It checks the full value with `long long` and the low
  32 bits without, and in both cases that the next argument is right.
  `scripts/test-step-08.sh` runs it in a third variant with
  `NO_POSIX_COMPLIANT`.
- **Upstream removed this option on purpose.** Commit `1b3af76bf3`
  (May 2026, "!libc/stream: remove CONFIG_LIBC_LONG_LONG and always
  support long long") removed it, and `c32b683085` dropped
  `CONFIG_HAVE_LONG_LONG`, to simplify the code. Restoring it goes against
  a recent upstream decision. It is kept here as a port-local change;
  proposing it upstream would need the size argument for 8-bit CPUs
  (6.2 KB on the CDP1802) and would likely meet resistance.
- The touched upstream files already fail nxstyle, so the step tests now
  run checkpatch on changed lines only (`docs/cdp1802/style.md`).

## How to revisit

If upstream gives printf a size option of its own, drop
`LIBC_LONG_LONG`.
