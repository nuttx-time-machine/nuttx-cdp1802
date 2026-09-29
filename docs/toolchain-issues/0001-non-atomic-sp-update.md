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

## Consequence for the port (revised 2026-09-29, ADR 0006)

~~Workaround: an interrupt entry that saves through R0 instead of R2.~~
**Withdrawn.** Alan requires the established COSMAC convention: R0 stays
free for DMA, R1 is the interrupt PC, and R2 must be a valid stack for the
interrupt routine at all times (ADR 0006). Real machines (COMX-35, Pecom,
Elf II) do use DMA through R0 (`real-machines.md`). So the problem must be
solved where it arises: **no instruction boundary may leave R2 above the live
stack top.**

GCC writes R2 in these places (`gcc/config/cdp1802/cdp1802.cc`, `.md` at
`8b18811140ea`):

| Source | Emitted | Safe? |
|--------|---------|-------|
| `addhi3` / `subhi3` on SP with 1–7 | `dec 2` / `inc 2` repeated (`cdp1802_template_incdec`) | yes: each step is atomic and monotonic |
| `addhi3` on SP with a larger constant (prologue/epilogue, `cdp1802_emit_addhi3_postreload`) | `glo 2; adi lo; plo 2; ghi 2; adci hi; phi 2` | **no** for allocation: the intermediate value is up to 256 bytes *above* the old SP |
| `movhi` SP ← frame pointer (epilogue when `frame_pointer_needed`) | `ghi fp; phi 2; glo fp; plo 2` | **no**: the intermediate `(new_hi, old_lo)` can be above the new SP |
| alloca / variable-length arrays | SP arithmetic with a register | not yet examined; NuttX can avoid them |

A safe ordering exists with no extra register:

- adding a constant `V = hi·256 + lo` to SP: `ghi 2; adi hi; phi 2`, then
  `glo 2; adi lo; plo 2; ghi 2; adci 0; phi 2`. Every intermediate value is
  ≤ the final one, i.e. at or below the new stack top;
- moving a register into SP: write the byte that makes the intermediate value
  the *smaller* of old/new first, which needs a comparison. Alternatively
  first set SP to a value known to be below both (e.g. `ghi fp; smi 1;
  phi 2` gives `(fp_hi−1, old_lo)` < fp; then `glo fp; plo 2; ghi fp; phi 2`)
  at the cost of three instructions.

Options (decision needed before Step 07; Steps 04–06 do not enable interrupts):

1. **Patch GCC** (the two templates above), plus a verifier that scans every
   linked NuttX image for R2 writes and rejects unknown patterns. Needs an ADR
   and Alan's approval (CONTRACT §5.9). Offer the patch to mikpe.
2. **Rewrite the generated assembly** at build time (compile to `.s`, a filter
   script replaces the unsafe sequences with the safe ones, then assemble),
   plus the same verifier. GCC stays untouched, but the workaround lives in
   the build (NuttX `Toolchain.defs`) and libgcc must be rebuilt through it
   or shown to be free of unsafe sequences.
3. **Send the report and wait for mikpe.**

The verifier is useful in every case, and it also documents the property in
CI.

Caveat for both safe orderings: they rely on unsigned 16-bit order, so they
assume no stack lives in the lowest 256-byte page (0x0000–0x00FF), where
"one page lower" would wrap to the top of memory. Both sim1802 profiles keep
stacks at the top of RAM (≥ 0x8000 in HW32/32); the linker script can assert
it.

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
