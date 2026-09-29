# Step 06 — Reset, start-up and boot to the idle loop

**Goal (contract):** reset code, `.data`/`.bss` initialisation, the NCRT
call/return routines, early console output, and the first `up_*` interfaces
that `nx_start()` needs. **Exit:** NuttX prints its boot messages and reaches
the idle loop, booting the raw ROM image in the simulator.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).
Profile: SIM64 (amendment A5).

## What was done, in order

1. **NCRT routines** (`arch/cosmac/src/common/cosmac_ncrt.S`, ADR 0014),
   written from the ABI (docs/cdp1802/abi.md §4) and MPM-201A pp. 54–64.
   Each routine's exit `sep 3` sits just before its entry, so R4/R5 need
   no reload.
2. **Reset code** (`cdp1802_head.S`): `DIS` first, because IE = 1 at reset
   [MPM p. 72]. Then R2 = top of the idle stack − 1, PC moves to R3, `.data`
   is copied from `_eronly`, `.bss` cleared, R4/R5 loaded, and
   `cdp1802_boardinitialize()` and `nx_start()` called.
3. **Interfaces** that replace the Step 04 stubs: `up_allocate_heap`,
   `up_initial_state` (idle thread only), `up_stack_frame`,
   `up_irqinitialize`, `up_initialize`, `up_idle`, `up_nputs`,
   `up_dump_register`. `up_saveusercontext` records a zeroed context.
4. **Board:** `up_putc()` through the simulator console command
   (`OUT 6` argument, `OUT 7` command 0xE0) with interrupts disabled. The
   argument buffer is shared by every device (docs/cdp1802/sim1802-fork.md).
5. **`sim1802:boot`**: `CONFIG_INIT_NONE`, scheduler debug output, no late
   initialisation thread.
6. Housekeeping: the `chip`/`board` links that `configure.sh` creates had
   been committed with the skeleton. They are now ignored (`.gitignore`, as
   in arch/avr). Defconfigs regenerated with `make savedefconfig`.

## Problems met

| Symptom | Cause | Fix |
|---------|-------|-----|
| link: `up_dump_register` undefined once `DEBUG_FEATURES` was on | `_assert()` needs it | `cosmac_registerdump.c` |
| First boot: assertion, then a second PANIC, and no useful message | `tls_init_info()` → `up_stack_frame()` stub PANIC → `_assert()` → `up_saveusercontext()` stub PANIC | Implement `up_stack_frame()`; `up_saveusercontext()` must never PANIC |
| Assertion in thread creation before the idle loop | `CONFIG_BOARD_LATE_INITIALIZE` (`default y` in sched/Kconfig) starts the `AppBringUp` thread → `up_create_stack()` stub | Disabled in `sim1802:boot` until Step 08 |

## Test

```
$ scripts/test-step-06.sh
ok: sim1802:boot builds (ROM (text+rodata+data) = 53629 bytes, RAM (data+bss, static) = 610 bytes)
ok: boots to the idle loop from ROM (3 RAM seeds)
ok: sim1802:minimal builds (ROM (text+rodata+data) = 62557 bytes, RAM (data+bss, static) = 544 bytes)
ok: nxstyle
ok: checkpatch c7080cbdfebaecf27c7325e7c7bfee9353b9eefa..HEAD
PASS: step 06
```

The console output in `--rom` mode (0xFF-filled ROM, pseudo-random RAM and
registers):

```
Entry
No init thread
CPU0: Beginning Idle Loop
@ Cycle limit 2000000 reached
```

The idle loop is reached within 449 804 machine cycles (found by bisection on
`--max-cycles`, to within 20 000 cycles). That is about 0.9 s at 4 MHz
(8 clocks per machine cycle, MPM p. 70).

Each intermediate NuttX commit was built separately (`sim1802:minimal`, 0
warnings), so the series bisects.

## Notes

- `sim1802:minimal` grew by 579 bytes (61 978 → 62 557) now that real
  implementations replace the stubs.
- ADR 0014 records the NCRT and memory-layout choices.
- Next: Step 06b (code banking, ADR 0013, amendment A5), then Step 07 on
  the banked profile.

## Time spent

About 3 h (including the assertion-path debugging).
