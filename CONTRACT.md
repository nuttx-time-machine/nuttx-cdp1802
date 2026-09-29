# CONTRACT — Porting Apache NuttX to the RCA CDP1802 (COSMAC)

**Owner / reviewer:** Alan
**Executor:** AI coding agent
**Workspace:** `~/nuttxspace/cdp1802/`
**Contract version:** 1.0

---

## 1. Purpose

You will port Apache NuttX to the RCA CDP1802 family (CDP1802, and optionally CDP1804/5/6). You will use Mikael Pettersson's (mikpe) GCC/binutils toolchain and run the result in a CDP1802 simulator.

This project has **two equal deliverables**:

1. **A working port.** NuttX boots in the simulator, runs multiple threads with preemption, and passes a reduced `ostest`. If memory allows, it also reaches an interactive NSH prompt.
2. **A teaching artifact.** The git history and documentation must let a human reproduce, understand and study every step. They must also serve as a **general guide for porting NuttX to any new CPU/MCU**, with the CDP1802 as the worked example.

A port that works but cannot be followed is a failed contract. Documentation that describes things you did not actually do and verify is also a failed contract.

---

## 2. Reference material

### Toolchain (mandatory)

Use these sources:

- Overview and status: https://gist.github.com/mikpe (the "RCA CDP1802 toolchain: Intro" gist)
- binutils: https://github.com/mikpe/binutils-gdb (target `cdp1802-elf`)
- GCC: https://github.com/mikpe/gcc (gcc-14/15 based, C only, soft-float)
- Build helper: https://github.com/mikpe/buildcross
- Simulator: https://github.com/mikpe/sim1802 (loads ELF / Intel HEX)

Do not assume branch names or build flags. Discover them from the gist and the repositories. Then **pin every source by commit SHA** in `toolchain/VERSIONS`.

### CPU documentation

- RCA MPM-201 *User Manual for the CDP1802 COSMAC Microprocessor* (bitsavers)
- CDP1802 datasheet
- CDP1804/1805/1806 datasheets and user manual (for the extended instructions and the on-chip counter/timer)

Cite the document and section/page for every hardware fact the port relies on.

### NuttX

- `apache/nuttx` and `apache/nuttx-apps`, pinned to one commit recorded in `docs/VERSIONS.md`
- `include/nuttx/arch.h` is the authoritative list of what an architecture must provide. It changes over time, so always read it at the pinned commit rather than relying on memory.
- Existing small-architecture ports worth studying: `arch/avr`, `arch/z80` (eZ80), `arch/renesas`, and `arch/sim`

---

## 3. Starting hypotheses (verify, do not trust)

These come from a prior feasibility analysis. Treat each one as a hypothesis. Confirm or refute it with a citation or a measurement, and record the result in `docs/journal/`.

- **H1.** The CPU has sixteen 16-bit registers (R0–RF), an 8-bit accumulator D, carry flag DF, 4-bit pointers X and P, T, IE and Q. There is no hardware stack and no CALL/RET on the 1802; the 1804+ add SCAL/SRET.
- **H2.** On an interrupt, the hardware does T ← (X,P), P ← 1, X ← 2, IE ← 0. R1 is therefore the ISR program counter, and R2 must always be a valid stack pointer.
- **H3.** IE cannot be read back. Interrupt save/restore therefore needs a software shadow, plus the DIS/RET inline-byte technique.
- **H4.** The bare 1802 has no timer. The 1805/1806 have an on-chip counter/timer that can generate interrupts.
- **H5.** A full context save plus restore costs roughly 2,000 clocks on a plain 1802.
- **H6.** Code and data share a single 64 KB address space. NuttX code-size growth versus Thumb-2 is expected to be large. **This is the main feasibility risk.**
- **H7.** mikpe's GCC ABI: you must discover the stack pointer register, the reserved registers (R0 DMA, R1 ISR PC?), the caller- and callee-saved sets, the call/return sequence and the soft-float helpers. Document the result in `docs/cdp1802/abi.md`. This must happen **before** you write any context-switch code.

---

## 4. Repository layout

Create a meta-repository that pins everything:

```
~/nuttxspace/cdp1802/                 # meta repo (git)
├── CONTRACT.md                       # this file (never edit; amendments go in docs/amendments.md)
├── README.md                         # "start here": what this is, how to reproduce, how to read it
├── nuttx/                            # git submodule → fork of apache/nuttx, branch cdp1802-port
├── apps/                             # git submodule → fork of apache/nuttx-apps, branch cdp1802-port
├── simulator/                        # submodule (sim1802 or fork) — only if modifications are needed
├── toolchain/
│   ├── VERSIONS                      # pinned SHAs of binutils, gcc, buildcross, simulator
│   ├── build-toolchain.sh            # reproducible build, idempotent
│   ├── Dockerfile                    # same build in a container
│   └── patches/                      # only if an ADR authorises patching the toolchain
├── scripts/
│   ├── env.sh                        # PATH etc.
│   ├── build.sh <config>             # builds NuttX for a given defconfig
│   ├── run.sh <elf>                  # runs in simulator
│   └── test-step-NN.sh               # automated check for each step, with expected output
└── docs/
    ├── porting-guide/                # GENERIC guide: porting NuttX to a new CPU (see §7)
    ├── cdp1802/                      # CPU primer, ABI, memory map, interrupt model, context layout
    ├── adr/                          # Architecture Decision Records, NNNN-title.md
    ├── journal/                      # one file per step: what was done, tried, failed, measured
    ├── toolchain-issues/             # minimal reproducers for compiler/assembler/linker bugs
    ├── size-budget.md                # table updated at every step (see §8)
    ├── VERSIONS.md                   # pinned NuttX/apps commits
    └── amendments.md                 # contract changes agreed with Alan
```

**Naming inside NuttX.** The architecture directory and chip names are your first decision, and they need an ADR. The recommended starting point follows NuttX's family-style naming (`arm`, `avr`, `z80`):

- `arch/cosmac/` as the architecture
- `arch/cosmac/src/cdp1802/` as the chip, with `cdp1805/` possibly added later
- `boards/cosmac/cdp1802/sim1802/` as the board, i.e. a virtual board defined by the simulator's memory map and I/O

---

## 5. Non-negotiable rules

1. **Step discipline.** Work proceeds in the numbered steps of §6. Each step ends with:
   - (a) code committed,
   - (b) docs committed,
   - (c) an automated test script that passes,
   - (d) the size budget updated,
   - (e) a journal entry,
   - (f) an annotated tag `step-NN-<short-name>` in the meta repo. The submodule SHAs must point to the matching NuttX/apps commits.

   A reader who runs `git checkout step-05-...` must get a buildable, runnable state.
2. **Every commit builds.** History must be bisectable. One logical change per commit.
3. **Commit messages** follow NuttX conventions:
   - A subject in the form `area: summary`, e.g. `arch/cosmac: add interrupt entry and context save`.
   - A body explaining **why**, not only what.
   - A `Signed-off-by:` line using the configured git identity.
   - A `Generated-by: <agent name/version>` trailer, following ASF guidance on generative tooling.
4. **History rewriting.** You may squash or reorder commits only on the current, untagged step. This keeps the history readable. Never rewrite anything that is already tagged. Failed attempts are not preserved as noise commits; they are **described in the journal** instead.
5. **Decisions are recorded.** Any choice between alternatives gets an ADR. That includes naming, memory map, ABI assumptions, context layout, interrupt strategy, timer source, build system, Kconfig defaults, and workarounds. Use the format Context / Options considered / Decision / Consequences / How to revisit. The commit implementing the decision references the ADR number.
6. **No fabricated results.** Every claim in the docs must come from one of three sources: a command you ran, a measurement, or a citation. Paste real output (trimmed) into the journal. If something was not verified, say so explicitly.
7. **Reproducibility.** A fresh machine running `toolchain/build-toolchain.sh`, then `scripts/build.sh`, then `scripts/run.sh` must reproduce each step. The Dockerfile must produce the same result.
8. **Code quality.**
   - Follow the NuttX coding standard.
   - Run `tools/checkpatch.sh` / `nxstyle` on every C file you add, and record the result.
   - Use Apache License 2.0 headers in the NuttX style on all new files.
   - Do not copy third-party code with incompatible licenses.
9. **Toolchain bugs.** Suspect the toolchain only after ruling out your own code. When you do:
   - Produce a minimal C reproducer in `docs/toolchain-issues/NNNN-*.md` with the exact command, the expected result and the actual result.
   - Isolate any workaround behind a clearly named macro or file, together with an ADR.
   - Do not patch GCC or binutils without an ADR **and** Alan's approval.
   - Prepare a bug report for mikpe as a draft, but do not send it.
10. **Keep upstream NuttX untouched where possible.**
    - Changes outside `arch/cosmac`, `boards/cosmac` and the relevant Kconfig/Make glue need a strong justification. Isolate each one in its own commit with an ADR, because each is a potential upstream discussion.
    - Common code assumes certain things (e.g. `sizeof(int) == 4`, alignment, `uintptr_t` width). If you find such an assumption, document it rather than hacking around it silently.

---

## 6. Steps and exit gates

Each step lists its deliverable and its **exit criterion**. Steps marked **GATE** require a written go/no-go report in the journal. You must then **stop and wait for Alan's decision**.

### Step 00 — Bootstrap

- Create the meta repo, README skeleton and this layout.
- Pin the NuttX and apps commits.

**Exit:** the repository structure is committed and the `README.md` "how to read this repo" section exists.

### Step 01 — Toolchain

- Build binutils and GCC for `cdp1802-elf`, using buildcross or a manual build (choose via ADR).
- Build the simulator.
- Compile and run a C "hello" plus a small soft-float test in the simulator.
- Document the ABI (hypothesis H7) with evidence: disassembly of annotated test functions, prologues/epilogues, argument passing, and returning structs and longs.

**Exit:** `test-step-01.sh` passes, and `docs/cdp1802/abi.md` is complete.

### Step 02 — Simulator capability audit — **GATE**

Determine exactly what the simulator models:

- Instruction set coverage (1802 vs 1804/5/6)
- The INT pin and interrupt entry semantics
- The DMA behaviour of R0
- Timers
- Console I/O (which mechanism, which port)
- Memory size and map
- Cycle counting
- Exit/halt conventions for automated tests

Compare it with at least one alternative that also models interrupts, such as Emma 02 or MAME's COSMAC core, noting their license and their scripting/headless ability.

The port needs **a periodic interrupt and a console**. If sim1802 lacks either, the options are:

- (a) propose minimal simulator extensions in a fork, e.g. a 1805-style counter/timer or a memory-mapped or port-mapped timer device, or
- (b) use an alternative simulator.

**Report:** the options, their costs, and a recommendation.

### Step 03 — Virtual board definition

- Define `sim1802` as the board: memory map, reset vector, ROM/RAM layout, console device, timer device and halt mechanism.
- Write it up in `docs/cdp1802/board-sim1802.md` with a diagram.
- Maintain two memory profiles in the size budget:
  - **SIM64**, where all 64 KB is available (used for development).
  - **HW32/32**, with 32 KB ROM and 32 KB RAM, a typical real board. This profile is used for the feasibility judgement.

**Exit:** the ADR is accepted and the doc is committed.

### Step 04 — Size feasibility — **GATE**

- Add the minimum arch stub needed to compile NuttX common code: empty or `PANIC()` implementations of the required `up_*` interfaces.
- Build a minimal configuration: no NSH; include sched, semaphores, wdog, mm, minimal VFS with `/dev/console`, and minimal libc.
- Measure with `cdp1802-elf-size` and `nm -S --size-sort`, grouped by subsystem.
- Compare against the same configuration built for a Cortex-M0/M3 target.

**Report:**

- Whether the kernel fits in the SIM64 and HW32/32 profiles.
- The top 20 symbols by size.
- Which Kconfig options reduce the size.
- A projected cost for NSH.

This report is itself a porting-guide chapter ("measure before you port").

### Step 05 — Architecture skeleton

Create:

- `arch/cosmac` Kconfig entries
- `Make.defs` and `Toolchain.defs`
- headers under `include/`: `arch.h`, `irq.h`, `types.h`, `limits.h`, `inttypes.h`, `syscall.h` as required
- the chip directory
- the board directory with a `defconfig`
- the linker script

Use the Make build first. CMake support is optional and must be a separate later step with its own ADR.

Document every file in the porting guide: what it is for, what NuttX expects from it, and where in common code it is consumed.

**Exit:** `./tools/configure.sh sim1802:nsh-less-config && make` links an ELF.

### Step 06 — Reset, early console, reaching `nx_start()`

- Write the startup code: set up the stack (R2), clear `.bss`, copy `.data` if needed, and set up the ISR vector in R1.
- Implement low-level `up_putc`/lowputc and early `syslog`.
- Print a boot banner from `nx_start()`, up to the point where the idle loop starts.

**Exit:** the banner appears in the simulator, checked by the test script.

### Step 07 — Interrupts and the system timer

- Write the ISR entry/exit in assembly and `irq_dispatch()` integration.
- Implement the shadow-IE `up_irq_save`/`up_irq_restore`/`up_irq_enable`, with an ADR explaining the technique (H3).
- Provide the timer tick via `up_timer_initialize`.
- Measure the interrupt entry+exit cost in cycles.

**Exit:** a tick counter advances and a watchdog callback fires at the expected rate in simulated time.

### Step 08 — Context switching

- Define the context layout in the interrupt frame, documented with a byte-accurate diagram in `docs/cdp1802/context.md`.
- Implement `up_initial_state`, the switch path (both from interrupt and from thread level), stack creation/use/release and task exit.
- Implement signal delivery.
- Measure the context-switch cost in cycles, validating H5.

**Exit:** two threads alternate under preemption, semaphores and `usleep` work, and the test script verifies interleaved output.

### Step 09 — Serial driver and `ostest`

- Write an upper-half serial driver for the simulator console.
- Build `ostest` with a reduced configuration. Document every disabled test and why.

**Exit:** `ostest` completes without failure in the automated test.

### Step 10 — NSH — **GATE**

Only attempt this if the size budget allows. If NSH does not fit even in SIM64, document why and what would be needed, such as code banking or a 1805-specific build. That write-up is the deliverable, and it counts as success.

**Exit:** either an interactive NSH with `help`, `ps`, `free` and `uptime` working, or the documented infeasibility analysis.

### Step 11 — CI, final documentation, upstream-readiness report

- Provide a single `scripts/ci.sh` that builds the toolchain (or uses the Docker image), builds every board config and runs every step test.
- Finish the porting guide.
- Write `docs/upstream-readiness.md`. Be honest about the toolchain being out-of-tree, the maintenance burden, the size limits and the changes to common code. Include a draft of the `dev@nuttx.apache.org` announcement.

Do **not** open upstream PRs or send mail.

---

## 7. Documentation requirements

### 7.1 The porting guide (`docs/porting-guide/`)

This is the most important document. Write it as a **generic tutorial**, with the CDP1802 as a running example in clearly marked boxes, e.g. `> **CDP1802 example:** …`. Someone porting to a completely different CPU should be able to follow it while ignoring the boxes.

The minimum chapters, each ending with "Checklist" and "Common pitfalls":

1. What a NuttX port consists of: arch vs chip vs board layers, and the flat vs protected vs kernel builds
2. Before you start: toolchain requirements (C99, GCC attributes, weak symbols, sections, linker scripts) and measuring feasibility (Step 04)
3. Understanding your CPU and its ABI: what you must know before writing a line of code
4. Choosing or defining a target (simulator or board) and a memory map
5. The arch directory: every file and every Kconfig symbol, and what consumes it
6. Toolchain integration: `Toolchain.defs`, `Make.defs`, flags, libgcc and soft-float
7. Linker scripts and startup code
8. The interfaces in `include/nuttx/arch.h`: a table listing each one, whether it is required or optional, a one-line purpose, and where the CDP1802 implementation lives
9. Interrupts: entry, dispatch, nesting, and critical sections
10. The system timer and timekeeping, including the tickless option explained but not implemented
11. Context switching and the interrupt frame
12. Signals and task exit
13. The console and serial driver
14. Validation: `ostest` and building your own step tests
15. Size optimisation techniques, based on real CDP1802 data
16. Preparing a port for upstream

The guide references the **git tag** where each concept first appears, e.g. "see tag `step-07-interrupts`", so readers can check out and study the exact code.

### 7.2 Journal (`docs/journal/step-NN.md`)

For each step:

- the goal
- what you did, in order
- commands run
- trimmed output
- what failed and why
- measurements
- the hypotheses confirmed or refuted
- open questions
- time spent

### 7.3 ADRs (`docs/adr/NNNN-title.md`)

Number ADRs sequentially and never delete one. A superseded ADR is marked "Superseded by NNNN".

### 7.4 CPU docs (`docs/cdp1802/`)

- `primer.md`: the CPU explained for a NuttX developer
- `abi.md`
- `board-sim1802.md`
- `context.md`
- `interrupts.md`
- `performance.md`: cycle counts for interrupt entry, context switch, a function call and a 16-bit add loop

### 7.5 README.md

This is the "start here" page. It covers:

- what the project is
- the status table (steps done, and what works)
- how to reproduce in 5 commands
- **how to read this repository as a course**: a suggested reading order through the tags, the guide chapters and the journal

---

## 8. Size budget tracking

`docs/size-budget.md` holds one row per step. The columns are:

- `.text`, `.rodata`, `.data`, `.bss`
- total ROM and total RAM
- the largest three subsystems
- fit in SIM64 and fit in HW32/32
- the config used

A regression of more than 10% between steps needs a sentence of explanation.

---

## 9. When to stop and ask Alan

Stop, write a short report in the journal and wait for input whenever any of these happens:

- a **GATE** step completes (02, 04, 10)
- a hypothesis in §3 is refuted in a way that changes the plan
- you want to patch the toolchain or substantially modify the simulator
- a change is needed in NuttX common code beyond a few trivial lines
- a licensing question comes up
- you have been blocked on the same problem for a long stretch without progress — document the attempts first
- you want to deviate from this contract in any way — propose an amendment

---

## 10. Out of scope

- Real hardware bring-up. Keep the board layer clean so it is possible later.
- C++ support, protected/kernel builds, SMP, and networking.
- Submitting anything upstream or contacting third parties.
- Optimising GCC itself.

---

## 11. Definition of done

- Steps 00–09 and 11 are tagged. Step 10 is tagged either as NSH working or as a documented infeasibility.
- `scripts/ci.sh` passes from a clean clone in the Docker image.
- The porting guide is complete per §7.1 and every chapter references real tags.
- Every hypothesis in §3 is marked confirmed or refuted, with evidence.
- Alan can follow the README's reading order from Step 00 to the end, reproduce each tag, and understand why every major decision was made.
