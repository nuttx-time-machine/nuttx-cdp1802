# Size budget

One row per step, as required by CONTRACT §8. Sizes are in bytes and come from
`cdp1802-unknown-elf-size` (Berkeley format) on the NuttX ELF of that step.
The subsystem grouping comes from `nm -S --size-sort` over the object files
and archives.

Memory profiles (defined in Step 03: `docs/cdp1802/board-sim1802.md`, ADR 0005):

- **SIM64**: all 64 KiB is usable (development). ROM image (code, read-only data, `.data` initial values) from 0x0000, exactly as large as needed; RAM from there to 0xFFFF.
- **HW32/32**: 32 KiB ROM 0x0000–0x7FFF (`.text` + `.rodata` + `.data` init image) and 32 KiB RAM 0x8000–0xFFFF (`.data` + `.bss` + heap + stacks). This profile is used for the feasibility judgement. Both profiles boot the raw ROM binary in the simulator exactly like the real machine (ADR 0005).

| Step | Config | .text | .rodata | .data | .bss | ROM total | RAM total | Largest 3 subsystems | SIM64 | HW32/32 | Note |
|------|--------|------:|--------:|------:|-----:|----------:|----------:|----------------------|:-----:|:-------:|------|
| 00 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet |
| 01 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet. Toolchain reference points (mikpe libc, not NuttX): hello 995 B text; printf+double soft-float 47 517 B text (`__adddf3` 15 198, `__muldf3` 12 012). See journal step-01. |
| 02 | — | — | — | — | — | — | — | — | — | — | No NuttX image yet (simulator audit only) |
| 03 | board smoke test (`smoke.S`, no NuttX) | 346 | (in .text) | 1 | 4 | 347 | 5 | — | ✅ | ✅ | No NuttX image yet; freestanding board smoke test (ROM image 347 B incl. `.data` copy) |
| 04 | `sim1802:minimal` (-Os + `-fno-split-wide-types`, HW32/32) | 74 663 | 463 | 55 | 501 | 75 181 | 556 | libsched 33.7 KB, libc 16.2 KB, libfs 13.1 KB | ❌ (> 64 KiB) | ❌ (2.29×) | First NuttX image. Does not link: ROM overflow by 42 416 bytes. Without the wrong-code workaround: 62 016 B (fits neither). See journal step-04 for all variants |
