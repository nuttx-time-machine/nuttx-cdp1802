# CDP1802 C ABI (mikpe GCC port) — as observed

Resolves hypothesis **H7**. Everything below is either quoted from the
compiler's own ABI note or observed in code this toolchain generated. The
section headers name the source.

- **[ABI-TXT]** `gcc/config/cdp1802/cdp1802-abi.txt` in `mikpe/gcc` at `8b18811140ea` (branch `gcc15-cdp1802`).
- **[OBS]** `toolchain/tests/abi.c`, compiled with
  `cdp1802-unknown-elf-gcc -Os -S -fno-inline` (GCC 15.3.1 20260919).
  `main()` in the same file checks every probe at run time in `sim1802`, and
  `scripts/test-step-01.sh` requires it to print `abi: PASS`.
- **[MPM]** RCA MPM-201A, *User Manual for the CDP1802 COSMAC Microprocessor*
  (1976, bitsavers). Page numbers are the printed ones; the PDF page is printed + 1.

## 1. Types [ABI-TXT, confirmed OBS]

| Type | Size | Notes |
|------|-----:|-------|
| `char` | 1 | **unsigned by default** (`char_is_unsigned()` returns 1) |
| `short` | 2 | |
| `int` | **2** | NuttX common code must tolerate `sizeof(int) == 2` |
| pointers | 2 | `uintptr_t` is 16-bit |
| `long` | 4 | |
| `long long` | 8 | via libgcc (`__muldi3` etc.) |
| `float` / `double` | 4 / 8 | IEEE, emulated by libgcc soft-fp |

Run-time output of `abi.elf`:

```
sizeof: short=2 int=2 long=4 llong=8 ptr=2 float=4 double=8
abi: PASS
```

All types are **1-byte aligned**. Multi-byte values are **big-endian** (the
ELF header says `Data: 2's complement, big endian`, `Machine: RCA CDP1802`).

> **NuttX impact:** `int` is 16-bit, so `INT_MAX` is 32767. That affects
> `clock_t`/tick arithmetic, `ssize_t` and any common code that stores
> milliseconds or byte counts in an `int`. Step 04/05 must audit this and
> record each assumption found (CONTRACT §5.10).

## 2. Registers [ABI-TXT, confirmed OBS]

| Reg | Role | Saved by | Evidence |
|-----|------|----------|----------|
| R0 | fixed: DMA pointer, PC after reset | — (never allocated) | ABI-TXT; [MPM p. 54: "R(0) Initial program counter ... Later, DMA pointer"] |
| R1 | fixed: interrupt handler PC | — | ABI-TXT; [MPM p. 40, p. 64] |
| R2 | fixed: SP | — | every prologue uses `stxd` with X=2 |
| R3 | fixed: PC (by convention) | — | |
| R4 | fixed: PC of the NCRT *call* routine | — | `sep 4; .hword callee` |
| R5 | fixed: PC of the NCRT *return* routine | — | every function ends `sep 5` |
| R6 | caller-saved; static chain; indirect call target | caller | `call_ptr` moves `fn` into R6 |
| R7–R10 | caller-saved; arguments and return values | caller | `add16`: a=R7, b=R8, result R7 |
| R11–R15 | callee-saved; R15 is the optional frame pointer | callee | `main` pushes R11, `add32` pushes R12, `mul64` pushes R12–R15 |
| D | 8-bit accumulator, clobbered by call/return | — | ABI-TXT |
| DF | carry; **preserved** across call/return | — | ABI-TXT |
| X | always 2 in compiled code | — | `add`/`adc` in `add16` read M(R(X)) = M(SP) |
| P | 3 in compiled code, 4/5 inside NCRT | — | |

**Invariant used by all generated code:** `X = 2` (the ALU memory operand
M(R(X)) is the scratch byte M(SP)). An interrupt handler or context switch
must restore X exactly.

## 3. Stack [ABI-TXT, confirmed OBS]

- The stack grows downwards. **SP points one byte *below* the last pushed byte**,
  because `STXD` stores and then decrements.
- **M(SP+0) is a scratch byte.** Compiled code writes to it freely (`str 2`
  before `add` in `add16`). The ABI says "Memory below SP ... is volatile.
  There is no red-zone."
- Callee-saved registers are pushed low byte first, then high byte
  (`glo 12; stxd; ghi 12; stxd`), so the high byte ends up at the lower address,
  which is big-endian in memory.
- Frames are allocated with a 16-bit add to SP (see `local_array`, 20 bytes):
  ```
  glo 2 ; adi 0xec ; plo 2 ; ghi 2 ; adci 0xff ; phi 2      ; SP -= 20
  ```
  or with repeated `dec 2` for small frames (`keep_live`, 4 bytes).

> **⚠ Interrupt hazard (not an ABI violation, but it matters for NuttX):** the
> 16-bit SP update above is two separate 8-bit writes. Between `plo 2` and
> `phi 2`, R2 holds a *torn* value. When the low-byte add borrows, R2 is
> transiently **256 bytes above** the correct value, i.e. inside live caller
> frames. An interrupt that pushes on R2 at that moment would corrupt them.
> The linked `abi.elf` has 22 such `plo 2`/`phi 2` pairs, and `softfloat.elf`
> 39/50 (`objdump -d | grep`). Hypothesis **H2** ("R2 must always be a valid
> stack pointer") therefore does **not** hold for GCC-generated code. See
> [`toolchain-issues/0001`](../toolchain-issues/0001-non-atomic-sp-update.md).
> The Step 07 interrupt entry must not push on R2 before switching to a known
> stack.

## 4. Call and return: NCRT [ABI-TXT, confirmed OBS]

The 1802 has no CALL/RET instruction. [MPM pp. 54–64, "Subroutine
Techniques"] describes software techniques instead; p. 64 lists RCA's
CALL/RETPGM routines, which use R6 as the link register ("SCRT"). mikpe's ABI uses a variant, the **New Call and Return
Technique (NCRT)**: R4 and R5 permanently point to two small routines, entered
with `SEP`.

Direct call (3 bytes at the call site):

```
    sep  4              ; P := 4, the call routine runs
    .hword callee       ; big-endian address, read by the routine
                        ; execution resumes here after the return
```

Indirect call (`call_ptr`): the target goes into R6 (static chain), then
`sep 4; .hword __call_reg`. `__call_reg` (libgcc `lib1funcs.S`) pushes R6 and
executes the return sequence, which "returns" into the target.

Return: `sep 5`.

What the call routine must do (ABI-TXT): set X=2, push the return address
(big-endian, i.e. high byte at the lower address), load the callee address
into R3, then `SEP 3`. The return routine sets X=2, pops the return address
into R3, then `SEP 3`. Both may clobber **D** but must preserve **DF**.

> **NuttX impact:** the NCRT routines live in mikpe's `crt0.S`, which is
> GPL-3.0 (`cdp1802-elf-libc`). NuttX must provide its own implementation
> (Apache-2.0), written from the ABI-TXT description above and **not** copied
> from `crt0.S`. It must initialise R4/R5 before the first C call. libgcc
> (GPL with the GCC Runtime Library Exception) already assumes R4/R5; its
> helpers end with `sep 5` (`RET` macro in `lib1funcs.S`).
>
> Every thread has its own R3 (PC) and R2 (SP), but R4/R5 hold the *same*
> values in all threads. They still have to be saved in the context, because
> an interrupt can arrive while P=4 or P=5 (inside the NCRT routine). T then
> records P=4/5, and R4/R5 hold a mid-routine PC.

## 5. Arguments and return values [ABI-TXT, confirmed OBS]

- The first **4 words** go in **R7, R8, R9, R10**, in order.
- A 32-bit value takes two consecutive registers, **high word first**:
  `add32(long a, long b)` has a = R7:R8 and b = R9:R10, and returns R7:R8.
- Arguments that do not fit go on the stack at increasing addresses, starting
  at *caller's* SP+1 at the call. In the callee, after NCRT pushed the 2-byte
  return address, the first stack argument is at **SP+3**. `sum6` (6 ints):
  a–d in R7–R10, e at SP+3, f at SP+5 on entry (the code reads SP+5/SP+7
  after pushing R12).
- A value never straddles registers and stack: `mkbig(long x, long y)` with a
  hidden pointer puts ptr=R7, x=R8:R9 and **y entirely on the stack**, even
  though R10 is free.
- **Variadic** arguments go entirely on the stack (ABI-TXT).
- **Return values** use R7–R10. D is never used, because NCRT clobbers it.
  - `struct pair {int a, b;}` (4 bytes) comes back in R7, R8. `mkpair(a,b)`
    compiles to a bare `sep 5`, since the arguments are already in place.
  - `struct big` (9 bytes) is returned via a **hidden pointer in R7**. The
    callee stores through R7.
  - `long long` is returned in R7–R10 (`mul64`).

## 6. Code generation characteristics that affect NuttX

- **No base+offset addressing** ([MPM], instruction set). Each field access
  copies SP or the struct pointer into a temporary, applies `inc`/`adi` and
  then `lda`/`ldn`. Pointers to structures are expensive, which NuttX uses
  everywhere (TCBs, lists). This is also mikpe's own remark in the toolchain gist.
- **Code size is large.** From `cdp1802-unknown-elf-size` at Step 01:

  | Program | text | data | bss |
  |---------|-----:|-----:|----:|
  | `return 3` + crt0 + libc init | 938 | 6 | 12 |
  | hello (`puts`) | 995 | 6 | 15 |
  | abi probes + `printf` | 12 792 | 6 | 16 |
  | soft-float test (float + double + printf) | **47 517** | 34 | 16 |

  The biggest symbols in `softfloat.elf`: `__adddf3` 15 198 B,
  `__muldf3` 12 012 B, `_vprintf` 4 821 B, `__mulsf3` 4 037 B. **Double-precision
  floating point costs about 30 KB**, so NuttX must be configured without FP
  in libc (`printf` `%f`, `strtod`, …). This is early evidence for **H6**.
- The linker's default script starts `.text` at **0x0100** (`ld --verbose`:
  `SEGMENT_START("text-segment", 0x100)`). The first LOAD segment of
  `hello.elf` is at VirtAddr 0x100. NuttX will use its own linker script (Step 05).

## 7. Object format [ABI-TXT, confirmed]

ELF32, big-endian, `e_machine = 0x1802` (unofficial), static linking only,
no PIC, no TLS. Multilibs: `.` (default), `1802` (`-march=1802`), `1804`
(`-march=1804`), from `gcc -print-multi-lib`. The toolchain is configured
with `--with-arch=1802` (ADR 0002), so the default build uses the `1802`
multilib.

## 8. Open points

- DF preservation across NCRT is stated in ABI-TXT, but no Step 01 probe
  checked it directly. The Step 08 context-switch tests will cover it.
- Frame-pointer (R15) use has not been observed at `-Os`. Check again at
  `-O0`/`-fno-omit-frame-pointer` if the debugger needs it.
