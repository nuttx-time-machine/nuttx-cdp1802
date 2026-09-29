# 0002 — Wrong code at -Os for nested calls with 64-bit values

Status: **open**, worked around (ADR 0010); draft report prepared (not sent)
Found: Step 04, 2026-09-29
Toolchain: `cdp1802-unknown-elf-gcc (GCC) 15.3.1 20260919`, mikpe/gcc `8b18811140ea`.
Present with and without the ADR 0007 patch (checked with an unpatched build).

## Reproducer (`toolchain/tests/issues/0002`)

```c
typedef unsigned long long u64;
#define NI __attribute__((noinline))

NI u64 f(u64 v, int n) { return n ? v + 100 : v; }          /* identity for n=0 */
NI u64 g(u64 x, u64 y, u64 *p) { return p ? 0 : x - y; }   /* x - y for p=0 */

NI u64 bad(u64 a, u64 b)
{
  return f(g(f(a, 0), f(b, 0), 0), 0);                     /* must be a - b */
}
```

`main.c` calls `bad(7, 2)` and prints the result.

```
$ cdp1802-elf-gcc -Os -o r.elf main.c repro.c && sim1802 r.elf
bad(7, 2) = 0:7, expected 0:5 -> WRONG
$ ... -O0 / -O1 / -O2                                        -> OK
$ ... -Os -fno-split-wide-types                              -> OK
```

**Expected:** 5. **Actual at -Os:** 7 (the first argument).

Bisection: the call must be nested at both levels. With only one inner
argument being a call result, or without the outer call, the code is correct
(`build/div64/bisect*.c` in the journal).

Flags tried at `-Os`: 35 `-fno-*` options; only `-fno-split-wide-types`
avoids it. `-fsplit-wide-types-early` and `-fno-split-wide-types-early` do
not.

## Impact

It broke the port's own signed 64-bit division (253/492 vectors). NuttX uses
64-bit values throughout time-keeping. The workaround costs 21 % code size
(ADR 0010). GCC's torture suite (1 687 execute tests) passes the same way at
`-Os` with and without the flag, so it does not cover this bug, and there is
no evidence yet that the flag avoids every instance. libgcc and mikpe's libc
are built at `-Os` without the flag.

## Draft report for mikpe (NOT SENT — Alan decides)

> Subject: cdp1802: wrong code at -Os for nested calls with 64-bit arguments
>
> Hi Mikael,
>
> with gcc15-cdp1802 @ 8b18811140ea, the attached 12-line program returns
> the first argument instead of a - b when compiled with -Os; it is correct
> at -O0, -O1 and -O2, and -Os -fno-split-wide-types also fixes it. It needs
> a call whose two 64-bit arguments are both results of calls, used as the
> argument of another call. It is not caught by gcc.c-torture/execute (same
> results at -Os with and without -fno-split-wide-types in my runs). I have
> not root-caused it; happy to test patches.
