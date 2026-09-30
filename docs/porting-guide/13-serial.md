# 13. The console and serial driver

> First tag: `step-09-ostest`. Journal `step-09.md`.

## 13.1 Two consoles

NuttX has two ways to print:

- **`up_putc()`** (and `up_nputs()`) is polled, character-at-a-time output
  that works from reset, in interrupt handlers and inside `_assert()`.
  `syslog()` uses it when no other channel is set up. Implement it first
  (chapter 7). It needs no initialization and no interrupts.
- **The serial driver** (`drivers/serial/serial.c`, the *upper half*)
  provides `/dev/console` and `/dev/ttySn` with buffering, blocking reads,
  termios and flow control. You write the *lower half*: a `struct uart_ops_s`
  and a `uart_dev_t` per port, registered with `uart_register()` during
  `up_initialize()` (or from your board's early initialization).

## 13.2 The lower half in practice

| Operation | What it must do |
|-----------|-----------------|
| `setup` / `shutdown` | configure / quiesce the device (baud rate etc.) |
| `attach` / `detach` | `irq_attach()` your interrupt handler |
| `rxint(enable)` / `rxavailable` / `receive` | receive interrupt on/off; "is a byte there"; read one byte |
| `send` / `txready` / `txempty` / `txint(enable)` | write one byte; "can I write"; "all sent"; transmit interrupt on/off |
| `rxflowcontrol` (with `CONFIG_SERIAL_IFLOWCONTROL`) | the receive buffer is full (`upper`) or drained: stop or restart the sender |
| interrupt handler | `uart_recvchars()` for input, `uart_xmitchars()` for output |

If the device has **no transmit interrupt** (output always accepted), make
`txready` always true, and let `txint(true)` call `uart_xmitchars()`
immediately inside a critical section.

If the receive interrupt is **level-triggered**, drain the device in the
handler. If the software buffer fills, you must stop the interrupt:
implement `rxflowcontrol`, mask the source when the buffer is full, and
unmask it when the reader drains it. Otherwise the interrupt fires forever.

> **CDP1802 example** (`boards/cosmac/cdp1802/sim1802/src/sim1802_serial.c`,
> `CONFIG_SIM1802_UART0`):
> - Output is the simulator's PUTCHAR command, so there is no transmit
>   interrupt.
> - Input is IRQ 6, level-triggered, plus STATUS/GETCHAR. When the buffer is
>   full, flow control masks IRQ 6, and the rest of the input waits in the
>   simulator, like a sender stopped by RTS.
> - The arch calls the board's `cosmac_serialinit()` from `up_initialize()`
>   when `CONFIG_MCU_SERIAL` is set.

## 13.3 Test with input you do not type

Run your tests with stdin from `/dev/null` (end of input immediately), and
with a script piped in (everything at once). Both are corner cases for the
input path: the second stresses flow control, the first the end-of-input
signal.

> **CDP1802 example:** `ostest` with stdin at `/dev/null` never passed its
> first test. The simulator started a new console reader for every STATUS
> query after end of input, and each new reader signalled end of input
> again: an endless stream of IRQ 6. That was a simulator bug, fixed in the
> sim1802 fork (Step 09).

## 13.4 Line buffering

With `CONFIG_STDIO_BUFFER_SIZE=0` every character is a separate `write()`.
Output from two tasks then interleaves character by character when
preemption switches between them. For readable test logs use a small
line buffer (`CONFIG_STDIO_BUFFER_SIZE=64`, `CONFIG_STDIO_LINEBUFFER=y`).

## Checklist

- [ ] `up_putc()` works before the serial driver exists, and inside
      interrupt handlers.
- [ ] The serial driver registers `/dev/console` (if it is the console) and
      `/dev/ttySn`.
- [ ] Level-triggered receive interrupts cannot storm: the handler drains
      the device, and flow control masks the source when the buffer is full.
- [ ] Tests run with stdin at end of file and with piped input.

## Common pitfalls

- A receive interrupt that is re-raised by the act of checking for input.
- Forgetting the critical section around `uart_xmitchars()` when calling it
  from thread context.
