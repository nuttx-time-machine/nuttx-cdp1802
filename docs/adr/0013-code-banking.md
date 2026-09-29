# 0013 — Code banking: fixed ROM + one 16 KiB bank window, stubs and a bank return stack

Status: Accepted as the approach (Alan chose option A at the Step 04 gate); this design is Proposed (agent)
Date: 2026-09-29
Step: step-06b (implementation)

## Context

NuttX does not fit a flat 64 KiB CDP1802 address space with correct code
(75 KB minimal, 122 KB with NSH). Real COSMAC systems extended memory with
bank switching. The CDP1802 has no hardware support for it, but every C call
already goes through the NCRT call routine (R4), which makes transparent far
calls possible. The design must not need compiler changes, must keep the C
ABI (arguments in R7–R10, further arguments on the stack at callee SP+3), and
must make function pointers work (file-operation tables, callbacks, task entry
points).

## Options considered

1. Put the bank number in the call sequence (3-byte callee reference).
   Needs a GCC change. Rejected.
2. **Per-function stubs in fixed ROM**, created by a build tool from the object
   files. Chosen.
3. Linker overlays (`OVERLAY`): GNU ld assigns addresses but does not generate
   inter-bank calls; still needs stubs. Used only as the placement mechanism.

## Decision

**Memory map (profile HWB):** fixed ROM 0x0000–0x7FFF (reset, NCRT, interrupt
entry and dispatch, context switch, far-call trampoline, stubs, **all
.rodata**, and all code not assigned to a bank); bank window 0x8000–0xBFFF
(banks 0..N-1, selected by a write-only I/O register); RAM 0xC000–0xFFFF.
Read-only data stays in fixed ROM because a pointer to banked data would be
dereferenced while another bank is mapped.

**Placement:** by object file (never splitting an object), by ordered rules
in the board (e.g. `libfs.a` → bank 1). A build tool reads the relocations of
every object:
- *call sites* (the 16-bit word after `SEP 4`) that reference a banked global
  function from another region are redirected to its stub;
- an object that takes the address of one of its **own** functions (a
  non-call relocation to a function start in the same object, e.g. a
  `file_operations` table next to its handlers) stays in fixed ROM, because
  that pointer would bypass the stub;
- everything else is checked and reported.
Banked objects get their global function symbols renamed (`foo` →
`foo$b`, `objcopy --redefine-sym`), so that calls inside the object stay
direct (same bank). The generated stub takes the original name `foo`, so
every other reference, including function pointers taken elsewhere, goes
through the stub.

**Stub** (11 bytes, fixed ROM, entered like any function, P=3, X=2):

```
foo:  ldi %hi(foo$b) ; phi 6 ; ldi %lo(foo$b) ; plo 6   ; R6 = target (caller-saved, free at a call)
      ldi BANK       ; lbr __cosmac_farcall              ; D = bank
```

**Trampoline** `__cosmac_farcall` (fixed ROM):
1. Push {caller's return address, previous bank} on the thread's **bank
   return stack** (BRS: a small array in `struct xcptcontext`, pointer in a
   global that the context switch updates). Overflow → PANIC.
2. Replace the return address on the C stack with `__cosmac_farret`, so the
   stack layout at callee entry is unchanged (arguments still at SP+3).
3. Select the bank: RAM shadow first, then the I/O write.
4. Enter the target by pushing it as a return address and executing `SEP 5`
   (the NCRT return routine pops it into R3). The stack is net unchanged.
`__cosmac_farret` (reached when the callee returns) pops the BRS entry,
restores the previous bank (shadow, then I/O), pushes the original return
address and executes `SEP 5`. Both routines preserve DF and R7–R10 (NCRT
rule: only D may be clobbered) and keep R2 valid at every instruction
(ADR 0006/0007).

**Context switch and interrupts:** the current bank and the BRS pointer are
per-thread state, saved and restored with the context. Interrupt handlers
start in fixed ROM; if they call banked code they go through stubs, which
restore the bank. Because the shadow is written before the I/O register and
every path restores both, an interrupt between the two writes leaves a
consistent state.

## Consequences

- Cross-bank calls cost the trampoline (roughly 40–60 instructions; measured
  in Step 06b) and 3 BRS bytes per nesting level per thread.
- About 11 bytes of fixed ROM per banked function that is referenced from
  outside its object.
- `setjmp`/`longjmp` across a far call would unbalance the BRS; the arch's
  setjmp must save/restore the BRS pointer (Step 06b/09).
- The simulator fork gets a bank-switched ROM window in `--rom` mode; the ROM
  image is the fixed part followed by the banks.
- Placement rules and the tool's report become part of the board. The size
  budget adds "fixed ROM used" and "banks used".

## How to revisit

If flat HW48/16 becomes feasible (compiler fix), banking can be switched off
per profile. If stubs cost too much fixed ROM, add placement rules that keep
callers and callees together.
