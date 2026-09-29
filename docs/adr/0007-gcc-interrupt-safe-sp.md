# 0007 — Patch GCC so that stack-pointer updates are interrupt-safe

Status: **Accepted** (Alan, 2026-09-29: option 1 of toolchain issue 0001)
Date: 2026-09-29
Step: prerequisite of step-07, done before step-04
Contract: §5.9 requires an ADR **and** Alan's approval to patch the toolchain; both are given here.

## Context

ADR 0006 (register convention) requires R2 to be a valid stack for the
interrupt routine at every instruction boundary. mikpe's GCC updates R2 one
byte at a time, and some sequences leave it up to 256 bytes *above* the live
stack top for a few instructions (toolchain issue 0001). The options were:
patch GCC, rewrite its assembly output at build time, or wait for mikpe.
Alan chose to patch GCC.

## Decision

Carry one patch, `toolchain/patches/gcc/0001-cdp1802-make-stack-pointer-updates-interrupt-safe.patch`
(on mikpe/gcc `gcc15-cdp1802` @ `8b18811140ea`, 3 files, about 180 lines),
applied by `build-toolchain.sh` and included in the GCC stage stamp. Every
write to R2 either is a single instruction or uses one of these sequences, in
which each intermediate value is at or below the live stack top:

| Update | Sequence | Lowest intermediate value |
|--------|----------|---------------------------|
| SP += V, 0 ≤ V < 256 | `glo 2; adi L; plo 2; ghi 2; adci 0; phi 2` (unchanged) | final − 256 |
| SP += V otherwise (all frame allocations) | `ghi 2; adi H; phi 2`, then `glo 2; adi L; plo 2; ghi 2; adci 0; phi 2` | final − 256 |
| SP ← FP in the epilogue (SP ≤ FP) | new insn `cdp1802_restore_sp_from_fp`: `glo 15; plo 2; ghi 15; phi 2` | old − 255 |
| SP ← register, constant or memory (direction unknown: VLA/alloca, non-local exits such as libgcc's SJLJ unwinder) | `(ghi r / ldi H / lda p); smi 1; phi 2`, then low byte, then high byte | new − 511 |

Pushes, pops and INC/DEC of R2 are single instructions. The epilogue's pops
leave R2 pointing *at* a live byte, and the standard ISR's initial `DEC 2`
handles that (MPM Fig. 76).

**Verification** (all automated in `scripts/test-sp-safety.sh`):

- `scripts/check-sp-safety.py` decodes every function of a linked image and
  requires every composite R2 update to be one of the sequences above. It
  passes on the validation programs, including libgcc's soft-float and mikpe's
  libc (rebuilt with the patched compiler), and it rejects the same programs
  built with the unpatched compiler (15 unsafe sequences).
- The interrupt stress test (standard R2-stack ISR every 157/211/331
  machine cycles, 20-byte, 300-byte and variable frames, 256 stack
  alignments, 256 rounds):

  | | period 157 | period 211 | period 331 |
  |--|--|--|--|
  | unpatched GCC | **hang** (killed after 300 s) | **63 corrupted bytes** | **7 corrupted bytes** |
  | patched GCC | 740 604 interrupts, 0 errors | 319 774 interrupts, 0 errors | 141 438 interrupts, 0 errors |

## Consequences

- **Stack guard band.** An interrupt can arrive while R2 is up to 256 bytes
  (prologue/epilogue) or 511 bytes (VLA/alloca/non-local exit) below the
  stack top, and its pushes land there. Every stack therefore needs that much
  free space below its deepest point, plus the ISR's own frame. NuttX code
  for this port should avoid VLAs and alloca (256-byte band), and Step 07/08
  must size stacks and the interrupt entry accordingly (e.g. switch to a
  dedicated interrupt stack right after saving T, D and DF).
- No stack may live in page 0x00 (0x0000–0x00FF), where "one page below"
  wraps. Both sim1802 profiles keep stacks at the top of RAM.
- Frame allocation costs 4 bytes and 3 instructions more when the frame is
  larger than 7 bytes (the `ghi/adi/phi` prefix). The Step 04 size
  measurements include it.
- `--without-headers --with-newlib` and all other GCC settings are unchanged.
  The patch is kept small so that it can be offered to mikpe (draft in issue
  0001, **not sent**).
- The checker is part of the toolchain tests now, and it will run on every
  NuttX image from Step 05 on.

## How to revisit

If mikpe fixes the issue upstream, drop the patch, move `GCC_SHA`, and keep
the checker. If the guard band turns out to be too expensive in HW32/32
(Step 08), consider an interrupt entry that switches stacks after 3 bytes, or
a compiler option that disables interrupts around SP updates instead.
