# 15. Size optimisation techniques

> First tag: `step-04-size-gate` (measurement, helper replacement, 32-bit
> time); `step-06b-banking` (code banking). Journals: `step-04.md`,
> `step-06b.md`.

Chapter 2 showed how to measure. This chapter covers what to do when the
kernel does not fit, from the cheapest fix to the most invasive. Measure
after every change, on a clean build (6.4).

## 15.1 Configuration first

Start from `CONFIG_DEFAULT_SMALL` and an existing tiny configuration.
Disable what the application does not use: mount points, pipes, signals,
POSIX timers, environment variables, `printf` floating point. Each item is
one Kconfig line and is fully reversible. Keep the minimal configuration in
the board, so that the size budget always measures the same thing.

## 15.2 Replace expensive generic helpers

The compiler's runtime library is written for correctness on every target,
not for size on yours. Look for its members in the map (the size report
lists `libgcc.a` separately). The arch library is linked before libgcc,
so a routine defined in the arch replaces libgcc's (6.2).

> **CDP1802 example:** three 64-bit division routines of about 11 KB each
> were replaced by one 4 KB implementation (ADR 0009). That saved 28.7 KB,
> the largest single saving in the port.

## 15.3 Types wider than the CPU

NuttX's default types are chosen for 32-bit CPUs. On an 8- or 16-bit CPU,
every 64-bit operation is a library call. At the pinned commit, `time_t`
and `clock_t` are always 64-bit. An opt-in 32-bit option is a small
common-code change (separate commit, ADR).

> **CDP1802 example:** `CONFIG_SYSTEM_TIME32` (ADR 0011) saved 13.2 KB of a
> 75 KB kernel, and its range limits are documented in the Kconfig help.

## 15.4 Compiler flags

Try `-Os`, `-O2` and your compiler's specific options, but only keep what
you have validated (2.1). A workaround for a compiler bug can cost more
than any optimisation gains.

> **CDP1802 example:** the only correct small-code setting costs 21 %
> (`-fno-split-wide-types`, ADR 0010, toolchain issue 0002). A compiler fix
> would recover about 5.4 KB of the minimal kernel.

## 15.5 Code banking

When code does not fit the address space at all, show part of a larger
ROM through a window, one bank at a time. NuttX has no banking support of
its own, so the port has to provide all of it:

1. **Hardware:** a window in the address space and a latch that selects the
   bank. Keep interrupt entry, the context switch, the banking code itself
   and all read-only data outside the window, in *fixed* ROM. Data stays
   fixed because a pointer to banked data would be read while another bank
   is selected.
2. **Far calls:** every call from outside a bank must select the bank and
   restore the caller's bank on return. If your ABI calls through a routine
   (as the 1802's NCRT does), or has a call instruction you can intercept
   with a stub, this can be transparent to the compiler. Otherwise you need
   compiler support for banked functions.
3. **Stubs, not symbols:** give every banked function a stub in fixed ROM
   under its *original name*, and rename the real function. Then calls from
   other regions, tail calls and function pointers all enter through the
   stub without any change to C code. Calls inside a bank should stay
   direct: rename them too, but only in objects of the same bank.
4. **A bank return stack per thread:** the return address and the
   caller's bank must be saved *outside* the C stack. Otherwise the callee
   would not find its stack arguments where the ABI puts them. The context
   switch saves and restores the current bank and this stack.
5. **Interrupts:** a far call must never be seen half done. Either make
   each step atomic, or (simpler) mask interrupts inside the trampoline.
   An interrupt handler may call banked code through the same stubs. The
   trampoline restores whatever bank was selected when it returns.
6. **Placement at link time:** a tool reads the objects' relocations and
   places whole objects. It keeps an object fixed when banking it would be
   unsafe, e.g. when it takes the address of its own static function (that
   pointer would bypass the stub). Let the linker check the result: GNU ld's
   `OVERLAY … NOCROSSREFS` rejects any direct reference between two banks.
7. **Test without the OS first:** a freestanding program with several
   banks, stack arguments, function pointers, tail calls and an interrupt
   routine that calls banked code. Run it under a fast timer interrupt and
   compare every result with the same computation done in fixed code.

> **CDP1802 example** (ADR 0013; `arch/cosmac/src/common/cosmac_farcall.S`,
> `tools/cosmac/cosmac_bank.py`, profile HWB):
> - A stub is 6 bytes (`sep 4; .hword __cosmac_farcall; .hword __bank_foo;
>   .byte bank`).
> - The trampolines run with IE = 0 for at most about 210 cycles.
> - A far call costs **398 machine cycles** more than a near one, about 8×.
> - `sim1802:boot` puts 34.5 KB in three banks and uses 20.0 KB of the
>   32 KiB fixed ROM. It reaches the idle loop in 17 % more cycles than the
>   flat build.
> - The freestanding test (`scripts/test-banking.sh`) ran with 34 553
>   interrupts at a 1 499-cycle period, spread over the whole loop including
>   the trampolines, with no error.

**Cost model.** Banking trades ROM for time. Keep hot code (memory
allocation, scheduler fast paths, interrupt dispatch) fixed or in the same
bank as its callers, and put large, rarely called code (formatted output,
file-system setup, shell commands) in banks. The placement report
(`nuttx.banks`) and the step's cycle counts tell you whether the rules work.

## Checklist

- [ ] The minimal configuration and its size are in the size budget, and
      every size change is measured on a clean build.
- [ ] You know the ten largest functions and why each is large.
- [ ] Every size workaround has an ADR and a way back.
- [ ] If you bank code: a freestanding banking test runs under interrupts;
      the placement report is part of the build output; the context switch
      saves the bank state.

## Common pitfalls

- Banking read-only data, or code that runs while the bank state changes.
- A function pointer to the banked copy instead of the stub (own-address
  rule, 15.5 item 6).
- An interrupt handler that calls C without resetting the registers your
  call mechanism depends on. On the 1802, R4/R5 may point into the middle
  of the NCRT routines when the interrupt arrives.
- Measuring banked and flat builds with different configurations.
