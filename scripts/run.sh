#!/usr/bin/env bash
# scripts/run.sh [sim-options...] <elf> [args...] — run a program in sim1802.
#
# Board images (anything that defines __sim1802_rom_end, i.e. NuttX and the
# board smoke test) are booted the way the real machine boots them: the ELF
# is converted to the raw ROM binary (<elf>.bin, the bytes an EPROM would
# hold) and started with --rom; --rom-size is __sim1802_rom_end and the ELF
# only provides symbol names (--symbols).  See docs/cdp1802/board-sim1802.md.
#
# Other programs (the mikpe-libc validation programs of Steps 01-02) are run
# through the simulator's ELF loader, as before.  RUN_MODE=elf forces that
# for board images too.
#
# The simulator's exit status is the program's exit status.  RUN_TIMEOUT
# (seconds, default 120) bounds wall-clock time so that a hung test cannot
# block CI; timeout(1) returns 124 in that case.  SIM selects another
# simulator binary, e.g. SIM=$CDP1802_TARGET-sim-upstream.
set -euo pipefail
. "$(dirname "$0")/env.sh"
[ $# -ge 1 ] || { echo "usage: $0 [sim-options...] <elf> [args...]" >&2; exit 2; }

sim=${SIM:-$CDP1802_TARGET-sim}
args=("$@")

# The image is the first argument that is an existing file (options before
# it, such as --max-cycles N, take numbers or words, not file names).
for i in "${!args[@]}"; do
  [ -f "${args[$i]}" ] || continue
  elf=${args[$i]}
  rom_end=$("$CDP1802_TARGET-nm" "$elf" 2> /dev/null \
            | awk '$3 == "__sim1802_rom_end" { print $1 }')
  if [ -n "$rom_end" ] && [ "${RUN_MODE:-rom}" = rom ]; then
    "$CDP1802_TARGET-objcopy" -O binary "$elf" "$elf.bin"
    rom=("--rom" "$elf.bin" "--rom-size" "$((16#$rom_end))" "--symbols" "$elf")
    [ $((i + 1)) -eq ${#args[@]} ] \
      || { echo "$0: program arguments are not supported in ROM mode" >&2; exit 2; }
    args=("${args[@]:0:$i}" "${rom[@]}")
  fi
  break
done

exec timeout "${RUN_TIMEOUT:-120}" "$sim" "${args[@]}"
