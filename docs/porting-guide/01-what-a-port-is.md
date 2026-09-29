# 1. What a NuttX port consists of

> First tag: `step-00-bootstrap` (naming, ADR 0001); first code in
> `step-05-skeleton`.

## 1.1 Three layers

NuttX separates hardware support into three layers. Each one lives in its
own directory and has its own Kconfig symbols:

| Layer | Directory | Kconfig | Contains |
|-------|-----------|---------|----------|
| **Architecture** | `arch/<arch>/` | `CONFIG_ARCH_<ARCH>`, `CONFIG_ARCH="<arch>"` | everything that depends on the *instruction set*: C types, interrupt entry, context switching, start-up, the toolchain definition |
| **Chip** | `arch/<arch>/src/<chip>/`, `arch/<arch>/include/<chip>/` | `CONFIG_ARCH_CHIP_<CHIP>`, `CONFIG_ARCH_CHIP="<chip>"` | one member of the family: on-chip peripherals, memory, chip-specific instructions |
| **Board** | `boards/<arch>/<chip>/<board>/` | `CONFIG_ARCH_BOARD_<BOARD>` | one circuit: memory map (linker script), clocks, which peripherals are used, the configurations (`configs/<name>/defconfig`) |

Put code in the *lowest* layer that is correct for it. A driver for a UART on
the chip goes in the chip layer; the board only says which UART is the
console. This is what makes the second board, and the second chip, cheap.

> **CDP1802 example** (ADR 0001): the architecture is `cosmac` (the family),
> the chip `cdp1802` (a later `cdp1805` would add the on-chip timer), the
> board `sim1802`. The CDP1802 has no on-chip peripherals, so the chip layer
> is nearly empty. The console, timer and interrupt controller belong to the
> *board* (they are the simulator's I/O controller). The register convention
> (R0 for DMA, R1 interrupt PC, R2 stack, R3 PC; ADR 0006) belongs to the
> *architecture*: it is the same on every COSMAC board.

## 1.2 Flat, protected and kernel builds

- **Flat** (`CONFIG_BUILD_FLAT`): kernel and applications share one address
  space and call each other directly. The only mode that makes sense without
  an MMU or MPU, and by far the smallest.
- **Protected** (`CONFIG_BUILD_PROTECTED`): an MPU separates the kernel;
  applications enter it through system calls (`syscall.h`).
- **Kernel** (`CONFIG_BUILD_KERNEL`): an MMU and separate processes.

> **CDP1802 example:** flat only. There is no MPU/MMU, and the size budget
> leaves no room for system-call stubs. `arch/cosmac/include/syscall.h`
> exists but defines nothing.

## 1.3 What NuttX calls, and what calls NuttX

- NuttX **calls the port** through the interfaces declared in
  `include/nuttx/arch.h` (`up_*`) and `include/nuttx/board.h` (`board_*`).
  Chapter 8 lists them all.
- The port **calls NuttX** from three places: the reset code calls
  `nx_start()`, the interrupt entry calls `irq_dispatch()`, and the timer
  interrupt calls the tick handler (`nxsched_process_timer()`).

## Checklist

- [ ] Names chosen for arch, chip and board, with no Kconfig clashes (`grep -rni`).
- [ ] You know which build mode you need (usually flat for small parts).
- [ ] You can say, for each piece of hardware, which layer it belongs to.

## Common pitfalls

- Naming the architecture after one chip: the second family member then lives
  in a misnamed directory.
- Putting board facts (memory map, which UART) in the chip layer.
