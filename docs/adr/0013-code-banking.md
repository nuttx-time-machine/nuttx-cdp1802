# 0013 — Code banking: fixed ROM + one 16 KiB bank window, stubs and a bank return stack

Status: Accepted as the approach (Alan chose option A at the Step 04 gate); design Proposed (agent), implemented at step-06b (see "As implemented")
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

- Cross-bank calls cost the trampoline (estimated 40–60 instructions; measured
  at Step 06b: 398 machine cycles more than a near call, see below) and
  3 BRS bytes per nesting level per thread.
- About 11 bytes of fixed ROM per banked function that is referenced from
  outside its object (6 bytes as implemented).
- `setjmp`/`longjmp` across a far call would unbalance the BRS; the arch's
  setjmp must save/restore the BRS pointer (Step 06b/09).
- The simulator fork gets a bank-switched ROM window in `--rom` mode; the ROM
  image is the fixed part followed by the banks.
- Placement rules and the tool's report become part of the board. The size
  budget adds "fixed ROM used" and "banks used".

## As implemented (step-06b)

The design above was followed, with these changes found while implementing:

1. **Stub = NCRT call with inline data, 6 bytes** instead of 11:
   `foo: sep 4 ; .hword __cosmac_farcall ; .hword __bank_foo ; .byte BANK`.
   The trampoline reads the target and bank through the stub's return
   address, and the slot of that return address is exactly where the target
   must go for the final `sep 5`. R6 is not needed to pass anything.
2. **The trampolines run with interrupts disabled** from `LSIE` to the final
   `RET`. The stack, the RAM shadow and the latch must change together, and
   the only free registers are D and R6. Disabling interrupts is simpler than
   a lock-free design, and it lets the trampolines share scratch bytes in
   `g_cosmac_bankstate`. The entry IE and DF are kept in one byte
   (`shlc` … `shr`), so DF is preserved even though the trampolines do
   arithmetic. Interrupts are masked for at most about 210 machine cycles.
3. **BRS state:** `g_cosmac_bankstate` = {BRS pointer, free entries, bank,
   scratch}. The first four bytes are per thread (saved by the context switch
   from Step 08). Overflow calls `cosmac_brs_overflow()` → PANIC. The default
   depth is 16 (`CONFIG_COSMAC_BRS_DEPTH`).
4. **Tool rules** (`tools/cosmac/cosmac_bank.py`):
   - A *call* is a 16-bit relocation after `sep 4` (0xD4) or after a long
     branch (0xC0–0xC3, 0xC9–0xCB: tail calls). The survey of all libraries
     found no helper with inline arguments after its call word, so the
     trampoline cannot break an inline-argument convention. The libgcc
     compare helpers are followed by a normal long branch.
   - An object stays fixed if it takes the address of one of its own
     functions, has code outside `.text*`, or defines a symbol defined
     elsewhere too.
   - Placement: explicit bank, `auto` (first-fit decreasing by the code the
     object keeps in a measuring link), or `fixed`.
   - The generated linker fragment uses `OVERLAY … NOCROSSREFS`, so a direct
     reference between two banks is a link error. Each bank is padded to
     16 KiB.
5. **Bank port:** `OUT 1` by default (`CONFIG_COSMAC_BANK_PORT`, 1–5). Ports
   6 and 7 belong to the sim1802 I/O controller.

**Measured** (step-06b, `docs/journal/step-06b.md`):

| | machine cycles |
|--|--:|
| loop of 1000 near calls (`fixed_inc`), per iteration | 72.7 |
| loop of 1000 far calls (`b_inc` in bank 1), per iteration | 470.7 |
| **extra cost of a far call + return** | **398** (the listing gives farcall 208 + farret 133 + one more NCRT call and return, 52) |
| interrupt routine making 2 far calls (test) | about 1 170 |
| `sim1802:boot` to the idle loop: SIM64 flat / HWB banked | 449 804 / 525 878 (+17 %) |

The estimate above (40–60 instructions) was too low: the trampolines
execute 102 and 65 instructions. The 1802 moves 16-bit values one byte
at a time, through D and one free register.

**Consequence found for Step 07:** an interrupt routine that calls C (and
therefore the stubs) must save R4/R5 and reload them with the NCRT entry
points. The interrupt may arrive while P=4 or P=5, with R4/R5 pointing
into the middle of the routine (see also abi.md §4). The banking test's
interrupt routine does this (`toolchain/tests/banking/isr_bank.S`).

## Revision at step-09: placement by function, stubs for every cross-bank reference

ostest overflowed the fixed ROM, because:
- objects that take the address of one of their own functions had to be
  fixed (24 of them);
- an object larger than a bank (`spinlock.c`, 35 KB) could not be placed.

The tool (`tools/cosmac/cosmac_bank.py`) now works as follows:

- **Placement unit = code section** (one function with
  `-ffunction-sections`). Objects are still placed whole when they fit and
  are split function by function when they do not.
- **Every reference is decided on its own.** Calls within a bank, or to
  fixed ROM, stay direct. Calls from another region, and every use of a
  banked function's *address*, go through a stub.
- References that must not use the name the object renames are
  **rewritten in the ELF file**: a new symbol-table entry, and the
  relocation pointed at it (`ElfObject.rewrite`). For a global function
  the new entry is a placeholder that `objcopy` renames back to the
  function's name, i.e. its normal stub, so pointers to it compare equal
  everywhere. A static function gets a generated stub
  (`__cosmac_ptr_N` → `__cosmac_fn_N`).
- Objects stay fixed only if they have code outside `.text*` or a symbol
  defined twice.
- The banking test (`toolchain/tests/banking`) covers it: a table of a
  static and a global function in bank 1, used from fixed code and from
  bank 0, and a pointer-equality check.

**Read-only data is still always fixed**, and it is now the limit:
ostest's strings take about 20 KB of the 32 KiB fixed ROM. The
architecture library, apart from its switching code, and the memory
manager moved to banks to make room (ADR 0016 keeps the tick path fixed).

## How to revisit

If flat HW48/16 becomes feasible (compiler fix), banking can be switched off
per profile. If stubs cost too much fixed ROM, add placement rules that keep
callers and callees together. If far calls dominate run time (Step 09
measurements), options are: placement rules that keep hot call chains in one
bank or fixed; a page-aligned per-thread BRS so that the pointer update is
one byte; or `-march=1804` register instructions in the trampolines
(`RLXA`/`RSXD`, CDP1804AC boards only).
