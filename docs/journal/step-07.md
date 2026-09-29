# Step 07 — Interrupts and the system timer

**Goal (contract):** ISR entry/exit in assembly and `irq_dispatch()`
integration; the IE save/restore with an ADR (H3); the timer tick via
`up_timer_initialize`; the measured interrupt entry+exit cost. **Exit:** a
tick counter advances and a watchdog callback fires at the expected rate
in simulated time. Profile: HWB (banked), amendment A5.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## What was done, in order

1. **Register frame and restore path** (ADR 0015). The frame is 31 bytes on
   the interrupted stack: T, D, DF, IE, R3–R15 and the I/O buffer.
   `xcptcontext.regs` points at it (the ARM/RISC-V pointer model).
   - One exit path ends in `RET` just before the entry, or in `DIS` +
     `lbr entry`. Step 08's thread-level switch will reuse it.
   - The entry reloads R4/R5 before calling C. This was found while writing
     the Step 06b test ISR, and is already noted in abi.md §4.
2. **`cosmac_doirq()`** follows the current `arm_doirq()` pattern. The
   board's controller (`sim1802_irq.c`) acknowledges and re-arms: the
   sim1802 controller clears a source's enable bit on acknowledge.
3. **Tick** (`sim1802_timer.c`): the simulator's cycle timer, mode 4,
   period = clock/8 × `USEC_PER_TICK` / 10⁶ machine cycles.
4. **IE state:** LSIE (default) and the RAM copy
   `COSMAC_IRQSTATE_SWFLAG` (Alan's Q4 decision). The contract's H3
   ("IE cannot be read back") was refuted at Step 02; ADR 0015 explains
   both techniques and the copy's four update points.
5. **Idle:** `IDL`.
6. **Test** `sim1802:tick`: a board idle loop (`ARCH_IDLE_CUSTOM`) runs a
   self-re-arming watchdog, measures the tick cost with a busy loop, and
   measures the idle stack high-water mark with a fill pattern.
7. `scripts/trace-profile.py`: cycles per function for one interrupt, from
   a `sim1802 -t` trace.

## Problems met

| Symptom | Cause | Fix |
|---------|-------|-----|
| Banked build: only "Entry" printed, then nothing | The tick path (`irq_dispatch`, `nxsched_process_timer`, `wd_timer`, the tick counter) was banked. The trace profile showed a tick taking 5 795 cycles (1 206 in `__cosmac_farcall` alone), more than the 5 000-cycle period, so the CPU never left the tick interrupt: livelock. | Tick path fixed in `banks.txt` (ADR 0016) |
| Flat build: watchdog periods 4–6 garbage | The 512-byte idle stack overflowed into the end of `.bss` (the test's own arrays). `syslog` from the idle loop plus an interrupt frame used 696 bytes (fill-pattern measurement). | 1 KiB idle stack (the NuttX default) |
| 67 % of the CPU in the tick at 100 Hz | 3 400 cycles per tick: NCRT call overhead (about 1 050) and the tick counter's seqlock (about 890) dominate | 50 Hz (ADR 0016); tickless and the seqlock are recorded as future work |
| checker: 2 "UNSAFE" SP updates in the banked image | `check-sp-safety.py` fetched code by address; every bank has the same addresses, so it decoded another bank's bytes | the checker reads each function from its own section. Step 06b's image had passed by luck; it still passes with the fixed checker |
| `#if` on the tick-period macro failed | C casts in a preprocessor expression | plain integer expression for the range check |
| profile script split `+a`, `+b` offsets | hexadecimal offsets parsed as decimal | fixed regex |

## Test

```
$ scripts/test-step-07.sh
ok: hwb-lsie: 6 watchdog callbacks, 51 ticks = 510000 cycles apart; timer interrupt 3407 cycles; idle stack used 684 of 1024 bytes
ok: hwb-swflag: 6 watchdog callbacks, 51 ticks = 510000 cycles apart; timer interrupt 3450 cycles; idle stack used 672 of 1024 bytes
ok: sim64-lsie: 6 watchdog callbacks, 51 ticks = 510000 cycles apart; timer interrupt 3407 cycles; idle stack used 682 of 1024 bytes
ok: sim64-swflag: 6 watchdog callbacks, 51 ticks = 510000 cycles apart; timer interrupt 3439 cycles; idle stack used 444 of 1024 bytes
ok: interrupt entry 175 + exit 119 = 294 machine cycles (+1 response cycle); whole tick 3407 (tick-profile.txt)
ok: nxstyle, checkpatch
PASS: step 07
```

The watchdog is re-armed with 50 ticks; NuttX's `wd_start()` adds one
tick, hence 51. At 50 Hz and 4 MHz a tick is 10 000 machine cycles, so
51 ticks = 510 000 cycles. Every period except the first (which starts
between two ticks) is exact.

## Measurements

| | machine cycles |
|--|--:|
| interrupt entry (frame push, R4/R5, C call setup) | 175 |
| interrupt exit (frame pop, RET) | 119 |
| interrupt response (hardware) | 1 |
| C dispatch: `cosmac_doirq` 284 + acknowledge 83 + re-arm 27 + NCRT | ≈ 550 |
| whole tick, LSIE (trace; busy-loop measurement 3 396–3 407) | 3 407 |
| whole tick, SWFLAG | 3 439–3 450 |

## Notes

- Step 08 must add the thread-level switch (the same restore path, entered
  with P=1 and IE=0) and the per-thread banking state.
- The idle stack peak (684–696 bytes) is set by `syslog` from the idle
  loop. Thread stacks will need a similar margin; Step 08 measures them.

## Time spent

About 4 h.
