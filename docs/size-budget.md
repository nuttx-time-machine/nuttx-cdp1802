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
