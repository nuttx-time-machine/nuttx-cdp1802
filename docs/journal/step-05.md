# Step 05 — Architecture skeleton

**Goal (contract):** `arch/cosmac` Kconfig, `Make.defs`/`Toolchain.defs`,
headers, the chip directory, the board directory with a defconfig, and the
linker script. Every file documented in the porting guide. **Exit:**
`./tools/configure.sh sim1802:<config> && make` links an ELF.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## What was done, in order

Most of the skeleton was written at Step 04, because the size measurement
needed it (journal step-04, Part 1). Step 05:

1. Switched `sim1802:minimal` to the **SIM64** profile (amendment A5):
   `CONFIG_BOARD_SIM1802_PROFILE_SIM64=y`, `CONFIG_RAM_SIZE=65536`.
   `CONFIG_RAM_START`/`RAM_SIZE` are used by no common code except
   `include/nuttx/page.h` (paging, not used). The heap will be taken from
   linker symbols (Step 06).
2. Built: **`make` exits 0**, with no warnings and no linker diagnostics.

```
$ scripts/build.sh sim1802:minimal step05-minimal
build sim1802:minimal -> build/step05-minimal (make exit 0)
ROM (text+rodata+data) = 61978 bytes, RAM (data+bss, static) = 544 bytes
sp-safety: OK            (whole kernel; 1 x SP<-register, 2 x SP<-memory)
$ nm nuttx.elf
00000000 T __start          0000f21c A _sdata / __sim1802_rom_end
0000f253 A _edata           0000f260 A _sbss      0000f450 A _ebss
```

   RAM above `.bss`: 0xF450–0xFFFF = 2 991 bytes for the heap and stacks.
3. Generated the `include/nuttx/arch.h` interface table (126 documented
   entries, the preprocessor condition around each prototype, and the 16
   interfaces our link needs) for porting-guide chapter 8.
4. Wrote porting-guide chapters 1 (layers, build modes), 5 (every arch and
   board file: purpose, what NuttX expects, what consumes it), 6 (toolchain
   integration) and 8 (the interface table), and `docs/cdp1802/primer.md`.
5. `scripts/test-step-05.sh`: build, diagnostics, reset code at 0,
   sp-safety, nxstyle on every arch/board C file, `tools/checkpatch.sh -g`
   over all port commits since the pinned base.

## Test

```
$ scripts/test-step-05.sh
ok: sim1802:minimal links (ROM (text+rodata+data) = 61978 bytes, RAM (data+bss, static) = 544 bytes)
ok: nxstyle
ok: checkpatch c7080cbdfebaecf27c7325e7c7bfee9353b9eefa..HEAD
PASS: step 05
```

## Notes

- CMake support: not attempted (contract: optional, separate step with ADR).
- The linker scripts define `__sim1802_rom_end` for the simulator. The
  `struct xcptcontext` layout is provisional until Step 08.

## Time spent

About 1 h (mostly documentation).
