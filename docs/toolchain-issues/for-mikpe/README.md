# Package for Mikael Pettersson (mikpe) — NOT SENT

Prepared by the agent at the Step 04 gate (Alan chose option B, "improve the
compiler with mikpe"). **Alan sends it.** Everything was checked against
mikpe/gcc `gcc15-cdp1802` @ `8b18811140ea` and the patch applies there.
Details and evidence: `docs/toolchain-issues/0001-*.md`, `0002-*.md`,
`0003-*.md` and ADR 0007.

## Suggested e-mail

> Subject: cdp1802 GCC: interrupt-safe SP updates (patch), -Os wrong code, -O1 hang
>
> Hi Mikael,
>
> thank you for the CDP1802 toolchain and sim1802. We are porting Apache
> NuttX (an RTOS) to the CDP1802 with them, and found three things you may
> want to know about. All against gcc15-cdp1802 @ 8b18811140ea.
>
> 1. **Stack-pointer updates are not interrupt-safe** (patch attached).
>    Frame allocation updates R2 low byte first
>    (`glo 2; adi; plo 2; ghi 2; adci; phi 2`), and loading SP from FP, a
>    register, a constant or memory writes the high byte first. For a few
>    instructions R2 can be up to 256 bytes *above* the live stack top. A
>    standard COSMAC interrupt handler (X=2, pushes through R2, as in RCA's
>    MPM-201A Fig. 76) then overwrites live frames. The attached patch emits
>    orderings in which every intermediate value is at or below the stack top
>    (proof in the patch description). With a handler firing every 211 machine
>    cycles, a stress test corrupts 63 bytes with the current compiler and
>    none with the patch (319 774 interrupts). It also covers libgcc's SJLJ
>    unwinder, which loads SP from memory. `issue1-repro.c` shows the
>    original sequence at -Os.
>
> 2. **Wrong code at -Os** (`issue2-repro.c` + `issue2-main.c`): `bad(7, 2)`
>    must return 5 and returns 7 at -Os; -O0/-O1/-O2 are correct, and so is
>    -Os -fno-split-wide-types. It needs a call whose two 64-bit arguments are
>    both call results, used as the argument of another call. It is not caught
>    by gcc.c-torture/execute (same results at -Os with and without the flag
>    in our runs). We use -fno-split-wide-types as a workaround for now, but it
>    costs about 21 % code size on NuttX.
>
> 3. **cc1 does not terminate at -O1** on `issue3-lib_getpwbufr.i` (a
>    preprocessed NuttX file, 792 lines); -Os and -O2 compile it in under a
>    second. It happens with and without the patch from item 1.
>
> Also possibly of interest: libgcc's `__divdi3`, `__udivdi3` and `__umoddi3`
> are about 11 KB each on this target (generic C `__udivmoddi4` inlined into
> each). A shared shift-subtract loop is about 4 KB for all four (we carry one
> in the NuttX port).
>
> Happy to test patches. Thanks again!

## Attachments (in `attachments/`)

| File | For |
|------|-----|
| `0001-cdp1802-make-stack-pointer-updates-interrupt-safe.patch` | item 1 |
| `issue1-repro.c` | item 1 (shows the unsafe sequence at -Os) |
| `issue2-repro.c`, `issue2-main.c` | item 2 |
| `issue3-lib_getpwbufr.i` | item 3 (Apache-2.0 NuttX source, preprocessed) |
