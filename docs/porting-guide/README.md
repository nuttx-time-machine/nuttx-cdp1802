# Porting NuttX to a new CPU — a worked guide

This is a **generic** tutorial on porting Apache NuttX to a new CPU or MCU
architecture. The running example is the RCA CDP1802 (COSMAC). It appears only
inside boxes like this one:

> **CDP1802 example:** …

If you are porting to a different CPU, skip the boxes.

Each chapter ends with a *Checklist* and *Common pitfalls*. It also names the
git tag of this repository where the concept first shows up in code, so you can
`git checkout <tag>` and read the exact state.

| # | Chapter | First tag | Status |
|---|---------|-----------|--------|
| 1 | What a NuttX port consists of | step-00-bootstrap | not written |
| 2 | Before you start: toolchain requirements and measuring feasibility | step-04 | not written |
| 3 | Understanding your CPU and its ABI | step-01-toolchain | not written |
| 4 | Choosing or defining a target and a memory map | step-03 | not written |
| 5 | The arch directory | step-05 | not written |
| 6 | Toolchain integration | step-05 | not written |
| 7 | Linker scripts and startup code | step-06 | not written |
| 8 | The interfaces in `include/nuttx/arch.h` | step-05 | not written |
| 9 | Interrupts | step-07 | not written |
| 10 | The system timer and timekeeping | step-07 | not written |
| 11 | Context switching and the interrupt frame | step-08 | not written |
| 12 | Signals and task exit | step-08 | not written |
| 13 | The console and serial driver | step-09 | not written |
| 14 | Validation: ostest and step tests | step-09 | not written |
| 15 | Size optimisation techniques | step-04 | not written |
| 16 | Preparing a port for upstream | step-11 | not written |

Chapters are written during the step that introduces their topic. They are
finished in Step 11.
