# 0001 — Stack-pointer adjustments are not interrupt-safe

Status: **open**, draft report prepared (not sent)
Found: Step 01, 2026-09-29
Toolchain: `cdp1802-unknown-elf-gcc (GCC) 15.3.1 20260919`, mikpe/gcc `8b18811140ea`

## Summary

For frame sizes that don't fit a few `dec 2`/`inc 2` instructions, GCC adjusts
SP (R2) with two separate 8-bit writes, low byte first:

```
glo 2 ; adi 0xec ; plo 2 ; ghi 2 ; adci 0xff ; phi 2      ; SP -= 20
```

Between `plo 2` and `phi 2`, R2 holds a mix of the new low byte and the old high
byte. When the low-byte add borrows during an allocation, that intermediate
value is **SP_old + 0x100 − n**, i.e. about 256 bytes *above* the live stack
top, inside the caller's frames. On the CDP1802 an interrupt forces X=2 and
the handler conventionally stores to M(R2) ([MPM-201A p. 64–65, Fig. 76]). An
interrupt at that instruction boundary therefore overwrites live data.

This is **not a wrong-code bug** under the documented ABI: `cdp1802-abi.txt`
does not promise that R2 is valid at every instruction boundary. It does
matter for any interrupt-driven system (an RTOS such as NuttX).

## Minimal reproducer

`repro.c`:

```c
int f(int n)
{
  volatile char buf[20];
  buf[n] = 1;
  return buf[0];
}
```

Command:

```
cdp1802-unknown-elf-gcc -Os -S -o - repro.c
```

**Expected** (interrupt-safe): R2 is never left pointing *above* the live stack
top while the adjustment is in progress.

**Actual:** the prologue contains `plo 2` … `phi 2` with an intermediate value
that can exceed the old SP when the low byte borrows.

Occurrences in linked Step 01 test programs (counted with `objdump -d | grep`):
`abi.elf` 22 × `plo 2` / 22 × `phi 2`; `softfloat.elf` 39 / 50. Most are in
libgcc soft-fp and in mikpe's libc.

## Workaround in the port (planned, Step 07, ADR to be written)

The interrupt entry does not store anything through R2 until it has switched
to a known-good stack. R0 is reserved by the ABI ("fixed, DMA") and the
compiler never allocates it. The sim1802 board has no DMA, so the ISR can use
R0 as its own save pointer (`SEX 0`) into a static save area. It saves the
interrupted R2 *as is* and restores it *as is*, so the torn value is resumed
exactly and the interrupted code completes its two-step update normally.

### Does it work on real hardware without modification? (Alan's condition, 2026-09-29)

**Yes, on any board that does not use DMA. No hardware change is needed.**

- The workaround uses only CPU facilities present in every CDP1802: R1 as the
  interrupt PC, `SEX 0`, `SAV`, `STXD`, `RET` [MPM pp. 40–41, 64–66].
- Compiled code never touches R0. GCC lists R0 in `FIXED_REGISTERS`
  (`cdp1802.h`: `1, 1, 1, 1, /* r0 r1 SP PC */`). All 63 apparent R0
  "uses" in `objdump -d softfloat.elf` are false positives: 61 are the
  `.hword` callee address after `sep 4`, and 2 are inline command bytes in
  mikpe's libc `putchar` (`sex 3; out 7; .byte 0xe0`), which NuttX does not link.
- R0 is the PC only after reset [MPM p. 54]. NuttX's start-up code switches
  to R3 as PC (`SEP 3`) before enabling interrupts, as mikpe's `crt0.S` does
  for the same reason.

**Where it does not work:** boards that use DMA. The DMA-IN/DMA-OUT
cycles use R0 as the memory pointer and increment it
[MPM p. 9 "built-in memory pointer register"; p. 54 "Later, DMA pointer"],
and DMA can occur between any two instructions, including inside the ISR. So
R0 cannot also hold the ISR's save pointer. A typical example is a board
whose display controller fetches pixels by DMA, such as a CDP1861-based
design. (This comes from general knowledge of the COSMAC VIP and has not yet
been verified from the CDP1861 datasheet.)

For DMA boards, the port will keep the classic R2-based entry
[MPM Fig. 76] behind a Kconfig choice (e.g. `CONFIG_COSMAC_ISR_SAVE_R2`).
That entry is only safe with a toolchain whose SP updates are
interrupt-safe (the compiler change suggested below). The choice and its
precondition go into the Step 07 ADR. The sim1802 board has no DMA, so it
uses the R0 entry.

## Draft report for mikpe (NOT SENT — for Alan to decide)

> Subject: cdp1802: 16-bit SP adjustment leaves R2 transiently above the stack top
>
> Hi Mikael,
>
> while porting an RTOS to your cdp1802-elf toolchain (gcc15-cdp1802 @
> 8b18811140ea), I noticed that frame allocation of more than a few bytes
> updates R2 low byte first (`glo 2; adi; plo 2; ghi 2; adci; phi 2`). When the
> low byte borrows, R2 transiently points 256 bytes above the real stack top.
> An interrupt taken there (X=2, handler stores through R2) corrupts the
> caller's frame. A small example: `int f(int n){volatile char b[20]; b[n]=1; return b[0];}`
> at -Os.
>
> A possible fix: write the high byte first when SP decreases, and the low
> byte first when it increases (or compute into a temporary and copy in that
> order). Then every intermediate R2 value is at or below the live stack top.
> Is that something you'd consider, e.g. behind an option such as
> `-minterrupt-safe-sp`?
>
> Thanks for the toolchain!
