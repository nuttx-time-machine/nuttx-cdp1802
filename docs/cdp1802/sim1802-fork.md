# sim1802 `cdp1802-nuttx` fork

Decision: [ADR 0003](../adr/0003-simulator-strategy.md) (accepted by Alan).
Location: the `simulator/` submodule, branch `cdp1802-nuttx`, based on
mikpe/sim1802 `3b28ed21695b`. The fork is local only for now: Alan will
publish it and then `git submodule set-url simulator <url>` (amendment A4).
Its README documents the interface. This page records *why* each change
exists and how it was verified.

## Changes (one commit each, each builds with xref + dialyzer and passes eunit)

| Commit | Change | Why the port needs it |
|--------|--------|-----------------------|
| `f9250e7` | Pending-interrupt bits updated atomically, one ETS tuple element per IRQ | The timer process, console reader and CPU all change pending bits. The upstream read-modify-write of one byte can lose an update (e.g. a tick raised during an acknowledge). Found while debugging the console IRQ (see the journal). |
| `fd79dc3` | Machine-cycle accounting; timer mode 4 (IRQ 0 every N cycles); 32-bit cycle-counter readback; IDL fast-forward; `--cycles`, `--max-cycles`, `--pace` | Deterministic tick (Step 07 exit criterion "in simulated time"), cycle measurements (H5, `performance.md`), bounded test runs |
| `a63cf9e` | Console input: GETCHAR (0xE1), STATUS (0xE2), level-triggered IRQ 6, EOF signalled once | Serial driver RX and interactive NSH (Steps 09–10) |
| `1e08519`, `55b6d99` | `.gitignore`, README | housekeeping, documentation |
| `bef5700` | `__sim1802_rom_end` symbol sets the write-protect limit | ROM emulation for the board's memory profiles (ADR 0005). Upstream only used libc symbols (`__DTOR_END__`, `_fini`) that NuttX images do not have. |
| `a3d1933` | Console 8-bit clean (standard I/O in latin1) | Bytes ≥ 0x80 were written as two UTF-8 bytes (0xDB → C3 9B) and input was UTF-8-decoded; a serial console must pass every byte. |
| `f41d9eb` | `--rom FILE` mode: boot a raw ROM image like a real board (0xFF-filled ROM window, pseudo-random RAM and undefined registers from `--ram-seed`, no boot args, ROM writes ignored / `--rom-writes warn\|trap`, `--symbols ELF`) | Alan's requirement: the EPROM image must boot in the simulator exactly as on the real machine (ADR 0005). |
| `708bd2c` | README for ROM mode | documentation |
| `1be386b` | ELF segments loaded at `p_paddr` (load address), not `p_vaddr` | A ROM image keeps `.data`'s initial values in ROM and copies them to RAM. With `p_vaddr` the ROM copy was never loaded (found by the Step 03 smoke test). Ordinary images have `p_paddr == p_vaddr`. |

Cycle counts come from RCA MPM-201A p. 8 (2 machine cycles per instruction,
3 for long branch/skip and NOP) and the Intersil CDP1805AC/1806AC datasheet
(March 1997) for the 68-prefixed instructions. An interrupt response adds 1
cycle (the S3 cycle). A machine cycle is 8 clock periods [MPM p. 70].
eunit tests `cycles_1802_test` and `cycles_68_test` pin the table.

## Verification (`scripts/test-sim-fork.sh`)

```
busy: 10 ticks, 371 spins, 100256 cycles
idle: 10 wakeups, irq_count +10, 96734 cycles
@ cycles 758681
ok: deterministic cycle timer (10 ticks = 100256 cycles incl. read-out)
ok: --pace (.402454131s)
ok: --max-cycles -> 96
ok: console input (polled, IRQ 6, delayed chunks, EOF)
ok: upstream 10 Hz timer mode unchanged
PASS: sim1802 fork
```

- **Determinism:** two runs produce byte-identical output, including the total
  cycle count. With the upstream wall-clock timer, spins per tick varied from
  2 927 to 4 097 (Step 02).
- **10 ticks = 100 256 cycles:** that is 10 × 10 000 plus the cost of the two
  cycle-counter read-outs inside the measured window.
- **Idle:** 10 IDL wake-ups take no host time without `--pace`. With
  `--pace 4000000`, 10 idle ticks of 10 000 cycles (20 ms each at 4 MHz)
  take ≥ 0.2 s.
- **Upstream compatibility:** `hello`, `softfloat`, `abi` (Step 01) and the
  10 Hz timer program still pass on the fork. The Step 02 audit runs against
  the pinned upstream binary (`cdp1802-unknown-elf-sim-upstream`).

## Semantics to remember when writing NuttX drivers

- The **timer** period is programmed in machine cycles (24 bits: at most
  16 777 215 cycles, about 33.5 s at 4 MHz). Acknowledging IRQ 0 clears its
  enable bit (upstream behaviour), so the ISR must re-enable it. Ticks missed
  while interrupts are masked collapse into one, and the timer stays in phase.
- **IRQ 6 is level-triggered:** the ISR must drain the input (STATUS bit 0 →
  GETCHAR) before re-enabling IRQ 6, or it will be re-entered immediately.
- Input arrives in host time, so *when* a byte becomes visible is not
  deterministic; the byte order is. Tests that feed stdin should compare
  output, not cycle counts.
- `--pace HZ` only slows *idle* periods. Busy code still runs as fast as the
  host allows.
