# Running the port in sim1802

## 1. Toolchain and simulator (once)

```sh
cd NUTTX_CDP1802
toolchain/build-toolchain.sh     # pinned binutils, GCC (+ patches 0001/0002), libc, Erlang, sim1802
. scripts/env.sh                 # PATH for cdp1802-unknown-elf-* and the simulator
```

The script is idempotent: stages that are already built at their pinned
SHA are skipped. The simulator is the port's fork of sim1802, in the
`simulator/` submodule (bank window, cycle timer, console input,
`--dump`).

## 2. Build a configuration

```sh
scripts/build.sh sim1802:nsh     # -> build/sim1802-nsh/nuttx.elf (+ nuttx.bin, nuttx.banks, size.txt)
```

`build.sh` always starts from `make distclean`.

| Configuration | What it is |
|---|---|
| `sim1802:nsh` | NSH on the banked HWB profile: help, ps, free, uptime, poweroff |
| `sim1802:nshflat` | the smallest NSH (help, poweroff), on HWB |
| `sim1802:ostest` | apps/testing/ostest; powers off with its result |
| `sim1802:threads` | Step 08 thread, signal and printf test |
| `sim1802:tick` | Step 07 interrupt and timer test |
| `sim1802:hwboot`, `minimal`, `boot` | boot to the idle loop |

HWB profile:
- 32 KiB fixed ROM at 0x0000;
- a 16 KiB bank window at 0x8000, bank latch on `OUT 1`;
- 16 KiB RAM at 0xC000.

`build/<name>/nuttx.banks` says which function went to which bank.

## 3. Run it

```sh
RUN_TIMEOUT=0 scripts/run.sh build/sim1802-nsh/nuttx.elf
```

- `run.sh` boots the raw ROM image (`nuttx.bin`, as an EPROM would hold
  it) with the bank count taken from the ELF. The ELF is only used for
  symbol names. The underlying command is
  `cdp1802-unknown-elf-sim --rom nuttx.elf.bin --rom-size 32768 --banks 16 --symbols nuttx.elf`.
- `RUN_TIMEOUT=0` removes the default 120 s time limit; Ctrl-C stops the
  simulator.
- Type NSH commands. Each line appears twice: once from your terminal,
  once from NSH's echo.
- `poweroff` ends the run with exit status 0.
- Without `--pace` the simulator runs as fast as the host allows and
  skips idle time, so the clock runs fast (`uptime`).
  `--pace 4000000` gives real-time behaviour at a 4 MHz clock.

Useful simulator options (put them before the ELF):

| Option | Effect |
|---|---|
| `--cycles` | print the machine cycle count at exit |
| `--max-cycles N` | stop after N machine cycles (exit 96) |
| `-t` | instruction trace, with `[bN]` = selected bank for window addresses |
| `--dump FILE` | write the 64 KiB address space at exit |
| `--rom-writes trap` | stop at any write to ROM (a stack running out of RAM does this first) |
| `--pace HZ` | real-time pacing at a nominal clock |

Scripted input: `printf 'help\nps\npoweroff\n' | scripts/run.sh build/sim1802-nsh/nuttx.elf`.

## 4. Look inside

```sh
# task list from a memory dump
scripts/run.sh --dump d.bin --max-cycles 20000000 build/sim1802-nsh/nuttx.elf < /dev/null
python3 scripts/nuttx-tasks.py build/sim1802-nsh/nuttx.elf d.bin

# where the cycles go (inclusive, bank-aware)
printf 'ps\npoweroff\n' | scripts/run.sh -t build/sim1802-nsh/nuttx.elf 2>&1 \
  | python3 scripts/trace-callgraph.py - --elf build/sim1802-nsh/nuttx.elf \
      --start cmd_ps --stop readline_fd
```

## 5. The tests

- `scripts/test-step-06.sh` through `test-step-10.sh`, `test-banking.sh`
  and `test-gcc-inline.sh`: each prints `PASS`.
- `test-step-09.sh` (ostest) takes about 3 minutes.
- `scripts/measure-flat-nsh.sh` shows the flat 48 KiB measurement.
