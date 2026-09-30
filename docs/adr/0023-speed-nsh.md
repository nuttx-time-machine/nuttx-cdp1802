# 0023 — Speed: compiler options for inline code, hot placement, cheaper far calls

Status: Proposed (agent). Alan asked for this work after the Step 10 gate:
"work on (c) and (d) too to speed up the ps command … about 2 or 3 s is
fine". It includes toolchain patch 0002 (CONTRACT §5.9: toolchain patches
need an ADR and Alan's approval).
Date: 2026-09-30
Step: after step-10

## Context

At the `step-10-nsh` tag, NSH's `ps` took 9.59 M machine cycles, which is
19.2 s at 4 MHz (500 000 cycles/s). The target of 2–3 s is 1.0–1.5 M
cycles.

A new inclusive profiler (`scripts/trace-callgraph.py`) and a far-call
histogram showed where the time went:
- the 50 Hz tick: about a third;
- the NCRT call/return routines: 30 %, because every call and return goes
  through a subroutine;
- far calls: 13 %, 3 394 of them in one `ps`, 636 to `memcpy` alone;
- 16-bit comparisons and constant shifts: about 15 %, because each is a
  library call;
- 64-bit division when printing numbers: about 10 %.

## Decision

1. **Toolchain patch 0002** adds three GCC options, all off by default.
   The default output is unchanged: all nine NuttX libraries of
   `sim1802:nsh` compile to identical code with and without the patch.

   | Option | What it does | Cost |
   |---|---|---|
   | `-minline-calls` | pushes the return address (`ldi lo; stxd; ldi hi; stxd; lbr f`) instead of `sep 4` + the NCRT call routine: 11 instead of about 37 machine cycles | +6 bytes per call site |
   | `-minline-compare` | 16-bit comparisons inline; a constant operand as an immediate | often smaller, not larger |
   | `-minline-shifts` | 16-bit shifts by a constant inline | larger for big counts |

   Indirect calls still go through `__call_reg`, and returns still go
   through `sep 5`.

   The test is `scripts/test-gcc-inline.sh`, which runs
   `toolchain/tests/inline/gen.py`. It covers all 10 comparison codes on
   20 edge values, with register and constant operands, all three shifts
   by every count from 1 to 15, and calls with stack arguments, recursion
   and varargs. The expected output is computed in Python. 10 builds pass:
   -Os and -O2, each with every option alone, all three, and none.
2. **Kconfig** `CONFIG_COSMAC_INLINE_{CALLS,COMPARE,SHIFTS}` pass the
   options. They are off by default and on in `sim1802:nsh`.
3. **20 Hz tick** (Alan; ADR 0016 revision).
4. **`udivmod64` 16-bit fast path** (ADR 0009 revision). printf's
   `__ultoa_invert()` divides in 64 bits for every digit; small operands
   now use the 16-bit division.
5. **Placement** (ADR 0013 revision):
   - `hot` rules keep small, widely called functions in fixed ROM while
     it has room. These are `memcpy`, the string functions, the atomics,
     the semaphores, the file table, `sched_lock`/`sched_unlock` and a few
     more;
   - the procfs formatting helpers join the stdio chain in bank 0;
   - `__cosmac_farcall` skips the bank switch and the bank-return-stack
     entry when the callee's bank is already selected. That is the case
     for calls through function pointers within one bank, such as a
     stream's `putc`.

## Consequences

NSH, per command, in machine cycles (`scripts/test-step-10.sh`; 4 MHz =
500 000 cycles/s):

| Build | boot | help | ps | free | uptime |
|---|---:|---:|---:|---:|---:|
| `step-10-nsh` (50 Hz, no options) | 2.54 M | 1.45 M | 9.59 M | 4.46 M | 1.91 M |
| 20 Hz tick | 2.04 M | 1.15 M | 8.06 M | 3.46 M | 1.47 M |
| + inline options + 16-bit division | 1.23 M | 0.69 M | 4.40 M | 1.77 M | 0.84 M |
| + hot functions in fixed ROM | 0.96 M | 0.56 M | 3.53 M | 1.52 M | 0.68 M |
| + same-bank fast path, bank-0 procfs helpers, more hot functions | 0.94 M | 0.54 M | **3.35 M** | 1.44 M | 0.66 M |

`ps` went from 19.2 s to **6.7 s** at 4 MHz, 2.9 times faster. That is not
yet the 2–3 s target.

Size of `sim1802:nsh`: fixed ROM 18.0 KB (was 10.8 KB); banked code
121.7 KB in 8 banks (was 126.2 KB).

Side effects:
- A cross-bank far call costs 421 cycles instead of 398, because of the
  fast path's bank comparison. A same-bank far call costs about 200
  fewer.
- ostest at 20 Hz: 2.51 G cycles (was 2.30 G at 50 Hz). Every step test
  still passes.

What remains in `ps` (3.73 M cycles in the profile) is mostly generated
code, not overhead:
- `vsprintf_internal` and `memoutstream_puts`: about 0.4 M each of their
  own code. GCC's code for structure fields and 32-bit `off_t` arithmetic
  is long on a CPU without indexed addressing: `memoutstream_puts` is
  about 350 instructions per call.
- The design of NSH's `ps`:
  - procfs formats `/proc/<pid>/status` and `stat` with `snprintf`, one
    character at a time, into memory;
  - NSH reads that text back, parses it and prints again;
  - 50 `snprintf` calls take 1.2 M cycles, a third of the total.
- Console output: about 2 000 cycles per character in the serial upper
  half.
- Returns: every `sep 5` goes through the NCRT return routine (0.2 M).

Tried and rejected: `-O2` for NSH. It compiles, and needs 9 banks and a
rule file without explicit bank-0 placement, but `ps` then never
finishes. This compiler has open wrong-code and hang issues at -Os and
-O1 (issues 0002 and 0003), and this was not investigated further.

## How to revisit

Options for the remaining factor of 2–3:
- **Compiler code quality** for field access and 32-bit arithmetic
  (addressing through a base register, fewer register copies). This is
  real backend work for mikpe or for the port.
- **A cheaper `ps` in NSH** that reads the TCBs directly instead of
  formatting and re-parsing procfs text. That is an apps change, and
  upstream would not want it for this reason alone.
- **A faster console lower half and upper half.**
- **A CDP1805/1806 build** (`-march=1804`) where the hardware allows:
  RLDI/RLXA/RSXD and the call instructions shorten call, return and field
  access.
