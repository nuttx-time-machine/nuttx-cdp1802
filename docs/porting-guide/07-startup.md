# 7. Linker scripts and start-up code: from reset to the idle loop

> First tag: `step-06-boot` (`nuttx` branch `cdp1802-port`). Journal:
> `docs/journal/step-06.md`.

Between the reset vector and `nx_start()` NuttX gives you no help at all: no
C runtime is set up, no stack exists and nothing initialises memory.
The linker script and the reset code provide all of that.

## 7.1 What the linker script must provide

| Item | Why | Consumed by |
|------|-----|-------------|
| reset code first, in a `KEEP`-ed section | the CPU starts at a fixed address; `--gc-sections` would drop an unreferenced section | the hardware |
| `.text`, `.rodata` (and `.init_array` if C++ or constructors are used) in ROM | code and constants | — |
| `.data` with a **run** address in RAM and a **load** address in ROM (`AT(...)`) | initialised variables must be writable, but their initial values must survive power-off | the reset code copies them |
| `_eronly`, `_sdata`, `_edata`, `_sbss`, `_ebss` | the copy and clear loops, and the heap start | reset code, `up_allocate_heap()` |
| `ASSERT`s on the sizes | an overflowing image should fail to link, not fail at run time | the linker |

These are the same symbol names that the ARM, AVR and RISC-V ports use.
Keep them: common tools and readers expect them.

> **CDP1802 example:** `boards/cosmac/cdp1802/sim1802/scripts/sim64.ld`
> (and `hw32.ld`, `hw48.ld`) put `.reset` first at 0x0000. The ROM copy of
> `.data` follows `.init_section` (`_eronly`). Each script also defines
> `__sim1802_rom_end`, which `scripts/run.sh` passes to the simulator as
> `--rom-size`, so the simulator's ROM matches the image.

## 7.2 What the reset code must do

In order:

1. **Put the CPU in a known state.** Read your CPU manual's reset
   description: which registers are defined, and are interrupts enabled?
   Disable interrupts before anything else if they can be enabled.
2. **Set a stack pointer.** The idle thread's stack is conventionally the
   `CONFIG_IDLETHREAD_STACKSIZE` bytes right after `.bss`. The heap then
   starts after it.
3. **Copy `.data`** from `_eronly` to `_sdata`…`_edata`.
4. **Clear `.bss`** (`_sbss`…`_ebss`).
5. **Set up whatever the C ABI needs**: global pointer, small-data base,
   call/return helpers, a frame pointer.
6. Call board early initialisation (e.g. `<chip>_boardinitialize()`: clocks,
   memory controller, a UART for early output).
7. Call **`nx_start()`**. It never returns. It initialises the OS, starts
   the init task, and becomes the idle thread.

Do not assume RAM or any register is zero after reset unless the manual says
so. Test with RAM that is *not* zero (see 7.5).

> **CDP1802 example** (`arch/cosmac/src/cdp1802/cdp1802_head.S`):
> - The 1802 resets with P = X = 0, R0 = 0, **IE = 1** [MPM p. 72]. So the
>   first instruction is `DIS` (with its inline X,P byte 0x00), before the
>   stack pointer is valid.
> - R2 (the stack pointer) := `_ebss + CONFIG_IDLETHREAD_STACKSIZE - 1`. The
>   ABI's SP points one byte *below* the last pushed byte.
> - `SEP 3` moves the program counter from R0 to R3, leaving R0 free for DMA
>   (ADR 0006).
> - There is no call instruction: GCC calls through R4/R5 ("sep 4; .hword
>   f" / "sep 5"), so the reset code loads R4/R5 with the NCRT routines in
>   `common/cosmac_ncrt.S` before the first C call.
> - The copy and clear loops are about 60 bytes of assembly. With no 16-bit
>   compare, the end test compares the low and the high bytes separately.

## 7.3 The first interfaces `nx_start()` calls

`nx_start()` reaches these before the idle loop (chapter 8 has the full
table):

| Interface | Minimum implementation |
|-----------|------------------------|
| `up_allocate_heap()` | return the RAM between the idle stack top and the end of RAM |
| `up_initial_state()` | fill the idle thread's TCB with its stack (`stack_alloc_ptr`, `stack_base_ptr`, `adj_stack_size`); for the idle thread, the registers are the ones already running |
| `up_stack_frame()` | carve thread-local data out of the top of a stack (used by `tls_init_info()`, even for the idle thread) |
| `up_irqinitialize()` | interrupt controller off, `g_current_regs` = NULL |
| `up_initialize()` | may be empty at first |
| `up_putc()` / `up_nputs()` | polled character output, used by the scheduler's `sinfo()` and by `_assert()` |
| `up_idle()` | may be empty; a real one waits for an interrupt |
| `up_saveusercontext()`, `up_dump_register()` | called by `_assert()`; they must **not** themselves `PANIC()` |

> **CDP1802 example:** `up_stack_frame()` was first a `PANIC()` stub. The
> boot stopped in `tls_init_info()` → `PANIC()` → `_assert()` →
> `up_saveusercontext()`, which was also a `PANIC()` stub. The nested panic
> hid the original one. Fix the assert path first: then every other stub
> reports itself clearly.

## 7.4 A boot configuration

Keep a configuration whose only purpose is to reach the idle loop:

- `CONFIG_INIT_NONE=y`: no init task, so no context switch is needed.
- `CONFIG_DEBUG_FEATURES`, `CONFIG_DEBUG_SCHED_INFO`: `nx_start()` then
  prints `Entry`, and the idle loop prints `CPU0: Beginning Idle Loop`.
- Nothing else that creates a thread (for example `CONFIG_BOARD_LATE_INITIALIZE`
  starts a bring-up thread).

The success criterion is precise: the messages appear, then nothing more,
and no assertion.

> **CDP1802 example** (`sim1802:boot`, from the raw ROM image):
> ```
> Entry
> No init thread
> CPU0: Beginning Idle Loop
> ```
> This takes about 450 000 machine cycles (0.9 s at 4 MHz, 8 clocks per
> machine cycle [MPM p. 70]).

## 7.5 Test like the real machine

A simulator's ELF loader hides start-up bugs. It loads `.data` at its run
address, and memory it has not loaded usually reads as zero. Boot the
**same binary you would program into ROM**, with RAM and registers
filled with garbage, and repeat with several different fills.

> **CDP1802 example:** the sim1802 fork's `--rom` mode fills the ROM with
> 0xFF, loads only the raw image, and fills RAM and the registers that
> reset leaves undefined with pseudo-random values (`--ram-seed`). ROM
> writes can be trapped. The Step 06 test boots with three different seeds.

## Checklist

- [ ] The reset section is `KEEP`-ed and at the reset address (`nm`, first
      bytes of the binary).
- [ ] Interrupts are disabled before the stack pointer is valid.
- [ ] `.data` and `.bss` are initialised by your code, not by a loader.
- [ ] The heap starts above the idle stack and ends at the end of RAM.
- [ ] `_assert()` works: it prints and halts without a nested panic.
- [ ] The boot configuration reaches `Beginning Idle Loop` from the raw
      image, with non-zero RAM.

## Common pitfalls

- Relying on the ELF loader (7.5).
- Interrupts enabled at reset (the 1802 is one example).
- `PANIC()` stubs on the assertion path (7.3).
- Board options that start threads before the context switch exists.
- The idle stack overlapping the heap: derive both from the same symbol
  (`g_idle_topstack` in the CDP1802 port).
