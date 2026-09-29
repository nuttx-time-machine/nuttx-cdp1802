# Step 06b — Code banking (amendment A5, ADR 0013)

**Goal (amendment A5):**
- a bank window in the sim1802 fork;
- the placement/stub tool;
- the far-call trampoline and bank return stack;
- the HWB profile (32 KiB fixed ROM + 16 KiB window at 0x8000 + 16 KiB RAM).

**Exit:** the Step 06 banner boots from a banked ROM image. A stress test
of cross-bank calls under interrupts passes.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## What was done, in order

1. **Relocation survey** of every object in the Step 06 libraries (a small
   ELF reader, later the core of the tool). What a function reference
   looks like in the code the compiler generates:
   - 8 158 calls `sep 4; .hword f`;
   - 277 tail calls `lbr f`;
   - intra-function long branches against section symbols;
   - 305 `%hi/%lo` address loads of functions;
   - data words against section symbols (tables of static functions).
   No helper takes inline arguments after its call word. The libgcc compare
   helpers (`__cmphi_*`) return a flag, and a normal long branch follows
   them. So a trampoline that rewrites the return address breaks no
   convention. The indirect-call helper `__call_reg` pushes R6 and does
   `sep 5`, so function pointers to stubs work.
2. **Simulator:** `--banks N [--bank-port P]` (fork commit `bc30f84`; eunit
   `banks_test`). The latch powers up random, as on hardware.
3. **Trampoline** (`arch/cosmac/src/common/cosmac_farcall.S`). The stub
   calls it through NCRT with inline {target, bank}, which makes a stub
   6 bytes instead of the 11 in ADR 0013's first design. It runs with IE = 0
   from `LSIE` to the final `RET`, and IE and DF are kept in one byte. See
   ADR 0013 "As implemented".
4. **Freestanding test** (`toolchain/tests/banking`,
   `scripts/test-banking.sh`):
   - three banks; recursion through all banks, 12 far calls deep;
   - 7-argument calls (stack arguments), function pointers into any bank;
   - a tail call into another bank;
   - an interrupt routine that calls banked C code, which makes another
     far call.
   Every result is compared with the same computation in fixed code.
5. **Tool** (`tools/cosmac/cosmac_bank.py`): placement rules, `auto`
   packing, renaming with `objcopy`, stubs, `OVERLAY … NOCROSSREFS`
   fragment, report. It passes checkpatch (black, flake8, isort; new
   `scripts/setup-checkers.sh`).
6. **NuttX integration:** a two-pass link in `arch/cosmac/src/Makefile`
   (measuring link, then placement, then the real link). Also the
   `BOARD_SIM1802_PROFILE_HWB` profile, `hwb.ld`, `banks.txt` and
   `sim1802:hwboot`.

## Problems met

| Symptom | Cause | Fix |
|---------|-------|-----|
| First interrupt test hung (cycle limit) | Timer period 97 cycles, but the test ISR (two far calls) takes about 1 170 cycles: interrupts starved the main loop, which is livelock, not corruption. The same program without interrupts passed 200 rounds with no error. | Periods 1 499 / 1 999 / 3 001 |
| (design review) test ISR calling C | An interrupt may arrive while P=4/5, and then R4/R5 point into the middle of NCRT. Already noted in abi.md §4 for context saving. | The test ISR saves R4/R5 and reloads the entry points. **Step 07 must do the same.** |
| `ld: cannot open linker script file banks.ld` | `INCLUDE` searches the `-L` directories given *before* `-T` | `-L` first |
| Bank image offsets wrong in principle | `objcopy -O binary` fills gaps with 0 | `--gap-fill 0xff` in `run.sh` and `build.sh`; the fixed part is padded by a `.rompad` section |
| checkpatch: `main` too complex (flake8 C901) | tool written as one function | split into read / assign / write / report |
| Empty last bank missing from `nuttx.bin` | A bank with no input sections becomes NOBITS | none needed: the simulator reads missing banks as 0xFF, like unprogrammed EPROM |

## Test

```
$ scripts/test-step-06b.sh
ok: layout (banks in the window, stubs in fixed ROM, same-bank call direct)
seed=1 period=1499: banking rounds=200 irqs=34553 errors=0
seed=1 period=1999: banking rounds=200 irqs=13738 errors=0
seed=1 period=3001: banking rounds=200 irqs=6224 errors=0
seed=7 period=1999: banking rounds=200 irqs=13738 errors=0
seed=42 period=1999: banking rounds=200 irqs=13738 errors=0
ok: far call + return costs 398 machine cycles more than a near one (470694 vs 72694 cycles for 1000 calls)
ok: bank return stack overflow detected (depth 20 > 16)
ok: banking test
ok: sim1802:hwboot builds (3 banks used, nuttx.bin 81920 bytes)
ok: banked image boots to the idle loop from ROM (3 RAM seeds)
ok: SIM64 configurations, nxstyle, checkpatch (test-step-06.sh)
PASS: step 06b
```

`sim1802:hwboot`, from the raw ROM image with `--banks 4` (the image holds
3 banks; the fourth reads 0xFF):

```
Entry
No init thread
CPU0: Beginning Idle Loop
```

## Measurements

| | SIM64 flat (`sim1802:boot`) | HWB banked (`sim1802:hwboot`) |
|--|--:|--:|
| code + rodata + data init | 53 629 | 20 032 fixed + 34 481 in banks = 54 513 |
| of which far-call stubs kept | — | 92 × 6 = 552 |
| banks used (16 KiB each) | — | 16 124 / 16 126 / 2 231 bytes |
| objects kept fixed by the safety rules | — | 9 (all "take the address of their own function": e.g. `nx_start.o`, `fs_files.o`, `lib_memoutstream.o`) |
| machine cycles to the idle loop | 449 804 | 525 878 (+17 %) |
| far call + return, extra cost | — | 398 cycles (≈ 8× a near call) |

The extra 884 bytes of the banked build are the stubs (552), the
trampolines and the start-up call.

## Notes

- `libarch` and `libmm` are fixed by rule (hot and/or banking-critical);
  everything else is `auto`.
- The context switch (Step 08) must save and restore the first four bytes
  of `g_cosmac_bankstate` per thread, and give each new thread its own bank
  return stack.
- Real hardware is out of scope (contract §10). `board-sim1802.md` §3.1
  describes the latch scheme as an untested description.

## Time spent

About 5 h.
