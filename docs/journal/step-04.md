# Step 04 — Size feasibility (GATE)

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## Part 0 — prerequisite: interrupt-safe stack-pointer updates (ADR 0007)

Not a Step 04 deliverable, but done first because it changes the code GCC
generates for every function, so the size measurements must use the final
compiler. Alan chose option 1 of toolchain issue 0001 ("patch GCC").

### What was done, in order

1. Found where GCC writes R2 (`cdp1802.cc`/`.md`): `addhi3`/`subhi3` with a
   constant (prologue/epilogue), `movhi` register→SP (epilogue SP ← FP),
   constant→SP and memory→SP. The `c` constraint ("any register except SP")
   means register+register adds never target SP.
2. Wrote C template helpers that emit safe orderings when the destination is
   SP, a dedicated epilogue insn `cdp1802_restore_sp_from_fp`, and matching
   length attributes. The loads from memory were first made a compile-time
   error ("not expected in C code").
3. **The rebuilt GCC failed to build libgcc:**
   `unwind-sjlj.c:308:1: error: cdp1802: loading the stack pointer from memory is not interrupt-safe`
   (SJLJ unwinder, `uw_install_context`). The assumption was wrong, so all
   three memory forms (plain, post-inc, post-dec) now use the safe ordering.
   While doing that, fixed my own bug: for the plain form the address *is*
   the register, so `XEXP (XEXP (src, 0), 0)` read garbage.
4. My `grep` over the build output hid the first failure (the script had
   correctly stopped and kept the old compiler installed: the generated code
   was still unsafe). The build exit status is now always checked explicitly.
5. The patch lives in `toolchain/patches/gcc/0001-…patch` (made with
   `git format-patch` in the GCC work tree). `build-toolchain.sh` resets the
   tree to the pinned SHA and applies all patches; the GCC stamp includes their
   hash. The libc stamp now includes the GCC stamp, because the libc was *not*
   rebuilt at first and still contained unsafe prologues.
6. Wrote `scripts/check-sp-safety.py`, a static checker that decodes the
   machine code of every function itself (NCRT `sep 4` + address, 1804
   prefix) and requires each composite R2 update to match a proven-safe
   sequence. Three bugs in the checker along the way:
   - it decoded from `objcopy -O binary` with the wrong base (first
     segment instead of first section, off by 0x74), giving nonsense
     "unsafe" hits and decode overruns. It now reads sections from the ELF;
   - it merged two back-to-back safe updates into one unknown pattern.
     It now covers writes greedily with patterns;
   - it needed an explicit `--allow SYMBOL` for code that provably runs with
     IE=0 (mikpe's `crt0` `_start` sets the first SP at boot).
7. Built the **unpatched** compiler into a scratch prefix to prove that the
   checker and the stress test detect the bug.

### Results

8. Docker re-verification then failed in an unrelated-looking place:
   `test-sim-fork.sh` printed `idle: 10 wakeups, \001rq_count +10`. It was
   not the compiler: the simulator's I/O controller has **one argument buffer
   shared by all devices**. `putchar` does `OUT 6` (byte) then `OUT 7`
   (command). The test ISR wrote its own `OUT 6` (IRQ mask 0x01) in between,
   so 0x01 was printed instead of `i`. The patched code shifted the timing,
   and the deterministic timer then hit that spot on every run. All test ISRs
   now save the buffer on entry (`DEC 2; INP 6`, or via R0 in the audit
   harness) and restore it on exit (`OUT 6`). This rule is now in the board
   document (§4) for the NuttX interrupt entry.
9. The interrupt counts first reported here (e.g. "62 830 interrupts") were
   wrong: the test's 16-bit counter wrapped. Found because period 331 reported
   exactly 331 interrupts over 43.8 M cycles. The counter is now 32-bit; all
   numbers below were re-measured.

```
$ scripts/check-sp-safety.py --allow _start build/sp-safety/stress-unpatched.elf | tail -1
sp-safety: FAIL (15 unsafe)
$ scripts/test-sp-safety.sh
ok: static check of hello, softfloat, abi (libgcc + libc included)
sp-safety: 50 functions, 29 composite R2 updates, 0 single-byte R2 writes
    14 x add 0<=V<256 (low byte first, carry 0)
     9 x add V>=256 or V<0 (high byte first, then low)
     2 x SP <- FP in epilogue (SP <= FP, low byte first)
     4 x SP <- register (one page below first)
sp-safety: OK
period=157 rounds=256 irqs=740604 errors=0
period=211 rounds=256 irqs=319774 errors=0
period=331 rounds=256 irqs=141438 errors=0
PASS: sp-safety
```

Same stress program built with the unpatched compiler:

```
period=157: killed by the 300 s timeout (exit 124)
period=211 rounds=256 irqs=319640 errors=63        (exit 1)
period=331 rounds=256 irqs=141381 errors=7         (exit 1)
```

This confirms that issue 0001 is real (the corruption shows up within a few
thousand cycles of this workload) and that the patch removes it.

### Hypotheses

- **H2** (R2 must always be a valid stack): now true for compiled code, with
  the patched compiler and a 256-byte (511 with VLA/alloca) guard band.

## Part 1 — size feasibility

Not started yet.
