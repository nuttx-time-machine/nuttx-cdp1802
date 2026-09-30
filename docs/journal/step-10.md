# Step 10 — NSH (GATE)

**Goal (contract):** only if the size budget allows, an interactive NSH
with `help`, `ps`, `free` and `uptime` working. Otherwise, a documented
analysis of why it does not fit.

**Exit:** NSH works, or the infeasibility analysis. This is a **GATE**:
stop for Alan's decision.

**Outcome:** NSH works on the **HWB** banked profile. It cannot fit in the
flat **SIM64** profile: the image is 136.9 KB, more than twice the 64 KiB
address space.

**Date:** 2026-09-29. **Executor:** Claude Opus 5.5 (claude-opus-5-5).

## What was done, in order

1. **`sim1802:nsh`** (ADR 0022):
   - HWB, 16 banks, `DEFAULT_SMALL`, serial console with readline;
   - procfs with process and meminfo entries;
   - the commands `help`/`?`, `ps`, `free`, `uptime`, `poweroff` and
     `quit`, and nothing else.
   It built at the first attempt: fixed ROM 8.6 KB, 7 banks.
2. The build warned about `uptime`'s load-average constant,
   `FIXED_1 = 1 << 16`, which overflows a 16-bit `int`. That is an apps
   fix (apps commit "nshlib: fix the uptime load-average constant for
   16-bit int").
3. `help` and `uptime` worked. `ps` and `free` were missing:
   `DEFAULT_SMALL` excludes procfs's process and meminfo entries, and no
   code mounted `/proc`. Fix: the configuration enables both, and the
   board mounts procfs in `board_late_initialize()`.
4. The problems in the next table were found in this order.
5. `scripts/test-step-10.sh` and the regression runs of every earlier
   step.

## Problems met

| # | Symptom | Cause | Class | Fix |
|---|---------|-------|-------|-----|
| 1 | `ps`: the CPU stops with "Trap deadlock" (IDL with IE=0) at P=15, running in RAM | a trap on ROM writes (`--rom-writes trap`) showed `__cosmac_farcall` writing through a bank return stack (BRS) pointer of 0x5F0F; a memory dump just before showed the BRS full (`free` = 0). `ps` nests 18 far calls, and the depth is 16. The overflow handler reported with `_alert()`, which is **banked**, so the report's own far call overflowed again, and the recursion ran the stack through `.bss` | port bug + sizing | handler switches to the static exit BRS before reporting, so an overflow is now a clean PANIC (exit 3); depth 24 in `sim1802:nsh`; `nuttx-tasks.py` reports each thread's BRS high-water mark (18 measured) |
| 2 | `ps`: "Could not open /proc (is procfs mounted?)", errno 2, while `free` reads `/proc/meminfo` | **common-code bug**: `O_DIRECTORY` is `1U << 16`, which the compiler folds to 0 where `int` is 16 bits (checked by compiling it; the warning is hidden because `include/` is a system directory). `opendir()` opened `/proc` as a file. `O_CLOEXEC`, `O_NOFOLLOW` and the other flags above bit 15 were 0 too | common code | on 16-bit `int` only: the free bits 2–4 for `O_DIRECTORY`/`O_CLOEXEC`/`O_NOFOLLOW`; `O_NOATIME`, `__O_SYNC` 0; `O_PATH`, `O_TMPFILE` undefined (ADR 0021; own commit; needs Alan's review) |
| 3 | regression: the Step 08 thread test now stops with "bank return stack overflow" after "signal 12 handled", in a build from a dirty tree only | the version string's length moved the code; the BRS state was all zeros. Bisecting memory dumps by cycle count showed `.bss` being cleared, i.e. the CPU re-entered the reset code, and the overflow was the boot code's first far call. An instruction trace showed the jump to 0x0000, and that the interrupt which delivered SIGUSR2 had hit `cosmac_ncrt_ret` between `lda 2` and `ldn 2` | **port bug** (Step 08) | the free byte M(SP) was live there (the return address's low byte), and `cosmac_sigdeliver()`'s first push overwrote it. The signal path now saves and restores the frame *and* M(SP) (ADR 0017 revision, `docs/cdp1802/context.md`) |
| 4 | first "signal storm" test (a signal every tick) passed without the fix | a signal sent from the tick costs about 6 000 cycles, and a delivery takes several ticks; signals merged into running deliveries, and the task was almost never in its loop when one was redirected (23 redirects, 3 deliveries in 40 M cycles) | test design | 100 signals, 7 to 9 ticks apart: **the test crashes without the fix** and passes with it. In the fixed build's trace, at least 8 of the redirects hit `cosmac_ncrt_call` while the free byte held the call target's high byte |

Bug #3 was in the Step 08 code, not the Step 10 code, and had been there
since `step-08-context`. Steps 08 and 09 passed only because no signal had
landed in the three-instruction window. The tools that found it:
- the simulator's `--rom-writes trap` and `--dump`;
- dumps bisected by cycle count;
- an instruction trace post-processed to find the instruction an
  interrupt hit.

The simulator's debugger was tried first, but its memory reads do not show
RAM in ROM-boot mode: `g_npidhash` read 0. It is not used for memory.

## Test

```
$ scripts/test-step-10.sh
ok: sim1802:nsh builds (banked: fixed ROM = 10760 bytes, banks = 126150 bytes (bank 0: 16128, bank 1: 16128, bank 2: 16128, bank 3: 16128, bank 4: 16128, bank 5: 16127, bank 6: 16127, bank 7: 13256))

NuttShell (NSH) NuttX-13.1.0-RC0
nsh> help
help usage:  help [-v] [<cmd>]

    ?           help        quit        uptime
    free        poweroff    ps
nsh> ps
  TID   PID  PPID PRI POLICY   TYPE    NPX STATE    EVENT     COMMAND
    0     0     0   0 FIFO     Kthread   - Ready              Idle_Task
    2     2     0 100 FIFO     Task      - Running            nsh_main
nsh> free
      total       used       free    maxused    maxfree  nused  nfree name
      14376       3576      10800       4512      10000     16      2 Umem
nsh> uptime
00:00:28 up  0:00, load average: 0.00, 0.00, 0.00
nsh> nosuchcmd
nsh: nosuchcmd: command not found
nsh> poweroff
@ cycles 21193831
ok: help, ps, free, uptime, unknown command, poweroff
boot to prompt + poweroff: 2543376 machine cycles
help: 1450533 machine cycles
ps: 9589392 machine cycles
free: 4458947 machine cycles
uptime: 1910938 machine cycles
ok: nxstyle, checkpatch
PASS: step 10
```

The test sends the commands through the simulated console input, and
`poweroff` ends the run with status 0. `--rom-writes trap` makes a stack
that runs out of RAM fail the test. The run is at the nominal 4 MHz, with
no virtual clock.

**Interactive use:**

```
RUN_TIMEOUT=0 scripts/run.sh build/step10-nsh/nuttx.elf
```

This runs as fast as the host can. Add `--pace 4000000` for real-time
speed. The test drives NSH through the same console driver with piped
input; a session from a real terminal was not tried here, so the terminal
mode (echo, line editing) may still need a look.

Regression, on the final commits: steps 06, 06b, 07, 08 (including the
new signal storm, 101 signals, 0 errors, in both IE variants) and 09
(ostest exit 0, 24 tests, 2.30 G cycles) pass. A host `sim:nsh` build
(32-bit `int`, unchanged `fcntl.h` values) builds and runs `ps`.

## What it costs (4 MHz = 500 000 machine cycles/s)

| Command | Machine cycles | Time at 4 MHz |
|---------|---------------:|--------------:|
| boot to the prompt | 2.54 M | 5.1 s |
| `help` | 1.45 M | 2.9 s |
| `ps` (2 tasks) | 9.59 M | 19.2 s |
| `free` | 4.46 M | 8.9 s |
| `uptime` | 1.91 M | 3.8 s |

Profile of `ps` (`scripts/trace-profile.py --start cmd_ps --stop
readline_fd`, 9.19 M cycles):
- the NCRT call/return routines take 2.74 M (30 %);
- far-call trampolines take 1.16 M (13 %);
- the 50 Hz tick path takes about 1.1 M (12 %);
- formatting (`vsprintf_internal`, `memoutstream_puts`, `ultoa`) and
  16-bit shift/compare helpers take most of the rest;
- the console output path takes about 0.3 M.

About 9 000 cycles per printed character (ADR 0020) explains most of the
time. The CPU is the limit, not memory.

## Size and memory

- ROM: 136 910 bytes. Of that, 10 760 bytes are fixed ROM (of 32 768),
  including only 2.9 KB of read-only data (1.6 KB merged strings), and
  126 150 bytes are in 8 of 16 banks. By library: `libfs` 32.8 KB (VFS,
  procfs), `libsched` 30.9 KB, `libc` 25.1 KB, apps 19.0 KB (NSH,
  readline).
- RAM: 972 bytes static, a 1 KiB idle stack, and a 14 376-byte heap. At
  the prompt 3 576 bytes of the heap are used (4 512 at most); the largest
  free block is 10 000 bytes.
- `sim1802:ostest` still fits: fixed ROM 32 604 / 32 768.

## Gate: what Alan decides

1. **Accept NSH on HWB as the Step 10 result.** The contract's
   alternative, "document why it does not fit", applies only to the flat
   profiles: in SIM64, 136.9 KB does not fit in 64 KiB.
2. **ADR 0021** (common code: `fcntl.h` open flags on 16-bit `int`), in
   addition to 0019 and 0008, which are still open.
3. **ADR 0022:** the NSH configuration, the procfs mount in the board, and
   BRS depth 24 in this configuration. The Kconfig default stays 16.
   Alternative: raise the default to 24 for every configuration, which
   costs 24 bytes per TCB.
4. **The Step 08 bug fixed here** (#3). It changes code that is already
   tagged. The fix is in the NuttX branch after `step-09-ostest`, and the
   earlier tags remain as they were.
5. Whether 19 s for `ps` at 4 MHz is acceptable. The options, measured
   above:
   - fewer far calls in the formatting path (placement rules, as Step 09
     did for the console chain);
   - an NCRT with fewer cycles (`SCRT`-style macros inline, which is a
     toolchain change);
   - a slower tick (ADR 0016).

## Time spent

About 6 h. Most of it went on #3: the signal-window bug, then the storm
test that could show it.
