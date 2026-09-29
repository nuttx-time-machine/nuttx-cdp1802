# 0003 — The compiler does not terminate at -O1 on a NuttX libc file

Status: **open**, avoided (the port builds at -Os); draft report prepared (not sent)
Found: Step 04, 2026-09-29
Toolchain: `cdp1802-unknown-elf-gcc (GCC) 15.3.1 20260919`, mikpe/gcc `8b18811140ea`, with and without the ADR 0007 patch.

## Reproducer (`toolchain/tests/issues/0003/lib_getpwbufr.i`)

NuttX's `libs/libc/pwd/lib_getpwbufr.c`, preprocessed for `sim1802:minimal`
(792 lines).

```
$ time cdp1802-elf-gcc -O1 -march=1802 -c -o /dev/null lib_getpwbufr.i
(killed after 20 minutes during the NuttX build; 120 s timeout in the retest)
$ cdp1802-elf-gcc -Os -march=1802 -c -o /dev/null lib_getpwbufr.i    # < 1 s
$ cdp1802-elf-gcc -O2 -march=1802 -c -o /dev/null lib_getpwbufr.i    # < 1 s
```

**Expected:** compilation finishes. **Actual:** `cc1` runs indefinitely at
100 % CPU. This is probably the LRA "reload loop" that mikpe's toolchain notes
describe; not verified.

The unpatched compiler (mikpe/gcc `8b18811140ea` without the ADR 0007
patch) hangs the same way: `timeout 120 … -O1` → exit 124 after 120 s. So
the bug is not caused by the port's patch.

## Impact

`-O1` cannot be used for NuttX; the port uses `-Os` (ADR 0010).

## Draft report for mikpe (NOT SENT — Alan decides)

> Subject: cdp1802: cc1 does not terminate at -O1 (attached .i)
>
> Hi Mikael, the attached preprocessed file (from Apache NuttX, 792 lines)
> compiles in under a second at -Os and -O2 but never finishes at -O1 with
> gcc15-cdp1802 @ 8b18811140ea (cdp1802-elf-gcc -O1 -march=1802 -c).
