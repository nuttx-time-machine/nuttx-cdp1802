# Size budget

One row per step, as required by CONTRACT §8. Sizes are in bytes and come from
`cdp1802-unknown-elf-size` (Berkeley format) on the NuttX ELF of that step.
The subsystem grouping comes from `nm -S --size-sort` over the object files
and archives.

Memory profiles (defined formally in Step 03, `docs/cdp1802/board-sim1802.md`):

- **SIM64**: all 64 KiB is usable (development).
- **HW32/32**: 32 KiB ROM (`.text` + `.rodata` + `.data` init image) and 32 KiB RAM (`.data` + `.bss` + heap + stacks). This profile is used for the feasibility judgement.

| Step | Config | .text | .rodata | .data | .bss | ROM total | RAM total | Largest 3 subsystems | SIM64 | HW32/32 | Note |
|------|--------|------:|--------:|------:|-----:|----------:|----------:|----------------------|:-----:|:-------:|------|
| 00 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet |
| 01 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet. Toolchain reference points (mikpe libc, not NuttX): hello 995 B text; printf+double soft-float 47 517 B text (`__adddf3` 15 198, `__muldf3` 12 012). See journal step-01. |
| 02 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet (simulator audit only) |
