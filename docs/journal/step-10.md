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
- the 50 Hz tick takes about a third: each tick costs 3 381 cycles of a
  10 000-cycle tick period, and 31 % of the cycles in a sampled part of
  `ps` were interrupt code. (An earlier version of this journal said 12 %.
  That added up only the tick functions' own cycles, not the NCRT calls
  they make, which the profile counts under `cosmac_ncrt_*`.)
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

## Gate outcome (Alan, 2026-09-30) and follow-up

Alan's decisions:
1. **NSH on HWB accepted.** He also wants a flat-only system, 48/16 if
   need be, and asked whether `sim1802:minimal` can start a minimal NSH.
2. **ADR 0021 accepted:** prepare it for mainline, keeping 32- and 64-bit
   compatibility.
3. **BRS default depth 24.**
4. **Errata:** leave the tags as they are and add errata notes.
5. **20 Hz tick**, and make `ps` as fast as possible, through placement
   and compiler work. About 2–3 s at 4 MHz would be fine.

### 1. Flat profile: not feasible at 48/16 (measured)

Sizes of flat builds on HW48/16 (48 KiB ROM, 16 KiB RAM, no banking):

| Build | ROM | Over 48 KiB by |
|---|---:|---:|
| `sim1802:minimal` (hello, no NSH) | 65 585 | 16 436 |
| + `-minline-compare` (smaller code) | 63 617 | 14 468 |
| + `CONFIG_DISABLE_ALL_SIGNALS` | 62 878 | 13 728 |
| + both | 61 569 | 12 420 |
| + both, `-march=1804` (CDP1804/5/6 instructions) | 59 021 | 9 872 |
| `sim1802:nsh` built flat (Step 10 feature set) | 134 376 | 85 229 |

Even the flat SIM64 profile (all 64 KiB, ROM and RAM together) cannot
hold `minimal` any more: it is 570 bytes over.

So `sim1802:minimal` cannot start even a minimal NSH on a flat machine.
NSH adds about 20–30 KB to `minimal`: the shell and readline (apps
13–19 KB), plus a console driver (the drivers library, mostly the
serial upper half, is 12 KB in `sim1802:nsh`). A flat 48 KiB NSH needs
the code roughly halved. Where the size goes:
- `minimal` already has `DEFAULT_SMALL`, no pthreads, message queues,
  environment or POSIX timers;
- the remainder is spread over the whole kernel. The largest items are
  `vsprintf` (7.5 KB), the file table (4 KB), 64-bit division (3.5 KB),
  semaphores and task setup (about 2 KB each);
- the dominant factor is the 1802's code density under this GCC. With
  no indexed addressing, loading a 16-bit field through a pointer takes
  10 instructions and 12 bytes (`glo adi plo ghi adci phi lda phi ldn
  plo`, seen in `memoutstream_puts`), and 32-bit values need about twice
  that.

What could make a flat NSH possible, largest effect first:
- compiler code density (backend work);
- fixing toolchain issue 0002, which saves about 5.4 KB of the
  `-fno-split-wide-types` workaround (Step 04);
- a console without the serial upper half, using `up_putc`/`up_getc`
  polling;
- an NSH with only built-in commands.

Even all of that together is not expected to reach 48 KiB. The banked
profile remains the way to run NSH.

### 2. `fcntl.h` for mainline (prepared, not sent)

- **Patch:** `docs/upstream/0001-include-fcntl.h-keep-open-flags-within-a-16-bit-int.patch`
  on current apache/nuttx master; branch `upstream/fcntl-16bit-int`.
- **PR description:** `docs/upstream/fcntl-16bit-int.md`.
- **Evidence:** `docs/upstream/compare-open-flags.sh` compiles all 28
  `O_*` constants with the upstream and the patched header.
  - x86_64, i386 and ARM: identical, so Linux compatibility is kept.
  - AVR: upstream has `O_DIRECTORY` = `O_NOFOLLOW` = `O_CLOEXEC` = 0 (the
    bug exists in mainline today); patched, 0x4, 0x10 and 0x8.
- `arduino-mega2560:nsh` (AVR) and `sim:nsh` build with and without the
  patch; `sim:nsh` runs.
- `checkpatch` passes.

### 3–4. BRS default, errata

- `CONFIG_COSMAC_BRS_DEPTH` defaults to 24 for all configurations.
- Errata notes are at the top of journals step-08 and step-09, and in the
  README status table.

### 5. Speed

Details and measurements are in ADR 0023, with the ADR 0016, 0013 and
0009 revisions. In order:

| Change | `ps` (machine cycles) | at 4 MHz |
|---|---:|---:|
| `step-10-nsh` | 9 589 392 | 19.2 s |
| 20 Hz tick | 8 060 728 | 16.1 s |
| GCC `-minline-calls/-compare/-shifts` (toolchain patch 0002) and the 16-bit division path | 4 399 904 | 8.8 s |
| `hot` placement: small, widely called functions in fixed ROM | 3 528 620 | 7.1 s |
| same-bank far-call fast path, procfs formatting in the stdio bank, more hot functions | **3 349 011** | **6.7 s** |

The other commands improved as well: boot to prompt 5.1 → 1.9 s,
`help` 2.9 → 1.1 s, `free` 8.9 → 2.9 s, `uptime` 3.8 → 1.3 s.

**The 2–3 s target for `ps` is not reached.** 6.7 s is 2.9 times faster
than at the tag. What remains (ADR 0023, "Consequences"):
- the compiled code of formatting itself: `vsprintf` and the memory
  stream's `puts`, about 0.4 M cycles each;
- the design of `ps`: procfs formats text with `snprintf` and NSH parses
  it back, which is a third of the time;
- about 2 000 cycles per character in the console output path;
- the NCRT return routine.

Getting below 1.5 M cycles needs one of:
- compiler work on code quality, the largest lever;
- an NSH `ps` that reads the task list directly, which is an apps change;
- a faster console path.

Tools added for this work:
- `scripts/trace-callgraph.py`: inclusive profiles from a trace;
- `scripts/test-gcc-inline.sh` with `toolchain/tests/inline/gen.py`;
- `scripts/cycles-per-tick.sh`: tests follow the tick rate;
- the placement tool's `hot` class and bank capacity check.

Tried and rejected: NSH at `-O2`. It needs 9 banks, and `ps` never
finishes, most likely wrong code; not investigated.

Regression on the final commits: steps 06, 06b, 07, 08, 09 (ostest exit
0, 24 tests, 2.51 G cycles at 20 Hz) and 10 pass, as do the GCC inline
test (10 builds), the banking test and the div64 vectors (648, with and
without the inline options).

## Flat NSH, second attempt (Alan, 2026-09-30)

Alan asked me to use `CONFIG_DISABLE_ALL_SIGNALS` and to disable every
other NSH command and feature that can go, to fit 48 KiB.

`sim1802:nshflat` is the result (`scripts/measure-flat-nsh.sh`). Its NSH
has only `help`, `poweroff` and `quit`: `DEFAULT_SMALL` already disables
every other command, and scripting, background commands, the semicolon,
aliases and pipelines. It has no signals, pthreads, POSIX message queues,
environment, POSIX timers, mount points or procfs. NSH error messages are
off, readline is minimal and stdio unbuffered. The measurements, linked
flat for HW48/16:

| Step | ROM | Over 48 KiB |
|---|---:|---:|
| NSH (help, poweroff) + serial driver + `DISABLE_ALL_SIGNALS` and the options above | 93 464 | 44 315 |
| minimal console driver instead of the serial driver (`CONFIG_SIM1802_CONSOLE`, new) | 77 288 | 28 139 |
| NSH started by the board, no `task_spawn()` (`CONFIG_SIM1802_START_NSH`, new); compact 64-bit division; NSH error messages off | 72 006 | 22 854 |
| echo in the console driver (final) | **72 032** | **22 882** |

**It does not fit: 72.0 KB against 48 KiB.** On the banked profile the same
configuration runs, which is how the test checks it: `help`, an unknown
command and `poweroff`. A Kconfig inconsistency in NuttX got in the way:
`DISABLE_ALL_SIGNALS` selects `DISABLE_MQUEUE_NOTIFICATION`, whose
dependency needs one kind of message queue, so `configure.sh` refuses the
combination "no signals and no message queues at all". SysV message
queues stay enabled; they add little, because unused code is discarded at
link time. That is an upstream report candidate.

What the remaining 72 KB is, grouped from the link map (code and
read-only data):

| Part | Bytes | Share |
|---|---:|---:|
| file system: VFS, file table, `/dev/console` | 14 338 | 19.9 % |
| printf and number formatting (`vsprintf`, streams, 64-bit division) | 13 302 | 18.5 % |
| tasks, task groups, start-up | 9 668 | 13.4 % |
| NSH and readline | 8 074 | 11.2 % |
| semaphores, mutexes, atomics | 5 122 | 7.1 % |
| time and clock | 4 959 | 6.9 % |
| scheduler core, interrupts, assertions | 4 082 | 5.7 % |
| memory manager | 3 724 | 5.2 % |
| strings, ctype, `strtol` | 3 469 | 4.8 % |
| port, board, libgcc, other | 5 184 | 7.2 % |

None of it can be switched off any further:
- **File descriptors:** every task's file list is set up through the
  spawn file-action code, which pulls in the scheduler-parameter
  functions.
- **printf:** NSH prints everything with `dprintf`, and NuttX's printf
  has no option without `long long`.
- **Time:** the clock is initialized from a calendar date.

Reaching 48 KiB needs about a third less code. The possibilities:
- **compiler code density**, the only lever that shrinks everything. With
  no indexed addressing, a 16-bit field load through a pointer takes
  10 instructions;
- **a small printf** for NuttX (a libc change);
- **a leaner file layer** for a single console (common-code changes);
- **fixing toolchain issue 0002**, which saves the cost of the
  `-fno-split-wide-types` workaround (about 5.4 KB at Step 04).

As a flat system, NSH needs at least 72 KB of ROM with this compiler.
That also rules out SIM64, whose 64 KiB must hold RAM as well.

The new pieces also help other configurations:
- the minimal console driver;
- the board-started NSH;
- the compact `udivmod64`, which is 2.1 KB instead of 4.6 KB in every
  configuration.

After them, all step tests pass: ostest exit 0 with 2.52 G cycles, and
`ps` at 3.40 M cycles, +1.5 % from placement shifts.

## printf without long long (Alan, 2026-09-30)

Alan asked for printf without `long long`, and a `CONFIG_NO_POSIX_COMPLIANT`
that removes everything that needs 64-bit arithmetic (ADR 0025). He also
asked me to confirm that the size builds use `CONFIG_DEFAULT_SMALL`: they
do. `sim1802:nshflat`, `minimal`, `nsh` and `ostest` all set it.

- `CONFIG_NO_POSIX_COMPLIANT` selects `SYSTEM_TIME32`, turns off
  `FS_LARGEFILE` and the new `CONFIG_LIBC_LONG_LONG`.
- Without `CONFIG_LIBC_LONG_LONG`, printf converts integers in
  `unsigned long`. "ll" and "j" arguments are still read whole, but only
  their low 32 bits are printed.
- After it, no 64-bit helper routine is linked in `sim1802:nshflat`. The
  remaining 64-bit code in the linked sources is all behind options that
  are off (`LIBC_MEMSET_64BIT`, `FDSAN`, `HRTIMER`).

| `sim1802:nshflat` linked flat (HW48/16) | ROM | Over 48 KiB |
|---|---:|---:|
| before (ADR 0024) | 72 032 | 22 882 |
| `CONFIG_NO_POSIX_COMPLIANT` | **65 857** | **16 706** |

Tests:
- the thread test now prints every integer conversion, including
  `long long` values above 32 bits followed by one more argument;
- `test-step-08.sh` checks it in three variants, the new one with the
  option;
- the first run showed that a Kconfig *default* does not switch
  `LIBC_LONG_LONG` off in an existing configuration, so it is now a
  dependency;
- ostest with the option passes: exit 0, 24 tests, 0 errors;
- all step tests pass.

Two findings:
- **Upstream removed `CONFIG_LIBC_LONG_LONG` in May 2026** (`1b3af76bf3`)
  to always support `long long`. This change undoes that locally.
- The upstream printf files already fail nxstyle (78 alignment errors).
  The step tests now run checkpatch on changed lines only
  (`docs/cdp1802/style.md`).

Still 16.7 KB over 48 KiB. By part:
- file system: 14.3 KB;
- printf and formatting: now about 7 KB;
- task management: 9.7 KB;
- NSH: 8.1 KB.

## NSH stops after 65 536 ticks (found by Alan, 2026-09-30)

Alan ran `sim1802:nsh` by hand. `ps` did not answer, and neither did
anything typed afterwards. The investigation:

1. **`/proc` was mounted**: `free` worked. `ps` worked in every
   automated test, including through a pseudo-terminal and with Alan's
   exact command sequence.
2. **Typing one character at a time**: `scripts/typing-test.py` passed
   120 commands. While reading the simulator's console code for this, I
   found a real race: a byte arriving while the queue was being drained
   could lose its interrupt. It was fixed in the fork (`f195be3`), but it
   was not the cause.
3. **The cause was elapsed time.** The failing run waited 10 s before
   typing again. Without `--pace` the simulator runs idle time at full
   speed, about 150 M cycles/s here, so the pause crossed 65 536 ticks
   (1.64 G cycles). Measured:
   - five runs of that sequence: five hangs;
   - boot and wait: answers up to 60 k ticks, none from about 66 k;
   - memory dumps: `g_system_ticks` = 65 536 and the tick seqlock's
     sequence = 0x00010000, frozen;
   - the CPU spins in `clock_get_sched_ticks()`, whose sequence copy is an
     `unsigned int` (16 bits here) compared against a `uint32_t` (ADR
     0026).
4. **Fix:** `uint32_t seq`. NSH now answers at 1 h 48 min of uptime.
   `test-step-10.sh` checks an uptime past 65 536 ticks; without the fix
   it fails, verified by reverting.

On real hardware the port would have stopped after 55 minutes at 20 Hz.
The bug is in upstream master (since `29e514b276`, 2026-01) and affects
every 16-bit-`int` target. The patch for mainline is in `docs/upstream/`
(not sent).

Lessons for the tests:
- **run for a long time:** the step tests all ran for well under 65 536
  ticks, and ostest's virtual 64 MHz clock makes its ticks longer;
- **test the way a person uses it:** Alan found this in a minute of
  interactive use.
