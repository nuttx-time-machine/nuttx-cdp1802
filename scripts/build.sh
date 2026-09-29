#!/usr/bin/env bash
# scripts/build.sh <board:config> [name] [make-variables...]
#
# Clean build of NuttX for a board configuration (e.g. sim1802:minimal) with
# the pinned toolchain (other architectures, e.g. the ARM comparison boards
# of Step 04, use whatever compiler their Toolchain.defs selects).  Always starts from "make distclean": NuttX's make
# does not rebuild objects when only compiler flags change, so an
# incremental build can silently measure stale code.
#
# Results in build/<name>/ (name defaults to the config with ':' -> '-'):
#   nuttx.elf, nuttx.map, nuttx.bin (the ROM image, objcopy -O binary),
#   build.log, size.txt (scripts/size-report.py), sp-safety.txt, and for
#   banked profiles nuttx.banks (the placement report)
# Exit status: that of make (a ROM overflow is a failed link, but the map
# and size report are still produced for the feasibility measurements).
#
# Extra arguments are passed to make, e.g. COSMAC_GCC_WORKAROUNDS= .
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

[ $# -ge 1 ] || { echo "usage: $0 <board:config> [name] [make-vars...]" >&2; exit 2; }
cfg=$1; shift
name=${1:-${cfg/:/-}}; [ $# -ge 1 ] && shift
out=build/$name
mkdir -p "$out"
top=$PWD

cd nuttx
make distclean > /dev/null 2>&1
./tools/configure.sh -l -a ../apps "$cfg" > "$top/$out/configure.log" 2>&1 \
  || { echo "configure failed, see $out/configure.log"; exit 1; }
# BUILD_TWEAKS: optional kconfig-tweak arguments applied after configure,
# e.g. BUILD_TWEAKS="--disable DEBUG_FULLOPT --enable DEBUG_CUSTOMOPT
#                    --set-str DEBUG_OPTLEVEL -O2"
# BUILD_FRAGMENT: optional file of .config lines ("CONFIG_X=..." or
# "# CONFIG_X is not set") merged after configure (scripts/merge-config.py).
if [ -n "${BUILD_FRAGMENT:-}" ]; then
  python3 "$top/scripts/merge-config.py" .config "$BUILD_FRAGMENT"
  make olddefconfig > /dev/null 2>&1
fi
if [ -n "${BUILD_TWEAKS:-}" ]; then
  # shellcheck disable=SC2086
  kconfig-tweak --file .config $BUILD_TWEAKS
  make olddefconfig > /dev/null 2>&1
fi
make -j"$(nproc)" "$@" > "$top/$out/build.log" 2>&1
rc=$?
cp .config "$top/$out/config"
[ -f nuttx.map ] && cp nuttx.map "$top/$out/nuttx.map"
[ -f nuttx.banks ] && cp nuttx.banks "$top/$out/nuttx.banks"
for f in nuttx.elf nuttx; do
  [ -f "$f" ] && cp "$f" "$top/$out/nuttx.elf" && break
done
if [ -f "$top/$out/nuttx.elf" ] && grep -q "^CONFIG_ARCH_COSMAC=y" .config; then
  "$CDP1802_TARGET-objcopy" -O binary --gap-fill 0xff nuttx.elf "$top/$out/nuttx.bin"
  python3 "$top/scripts/check-sp-safety.py" --allow __start "$top/$out/nuttx.elf" \
    > "$top/$out/sp-safety.txt" 2>&1 || true
fi
cd "$top"
[ -f "$out/nuttx.map" ] && python3 scripts/size-report.py "$out/nuttx.map" --top 20 > "$out/size.txt"
tr '\r' '\n' < "$out/build.log" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' \
  | grep -E "warning:|error:|undefined reference|overflow|will not fit" | sort -u > "$out/diagnostics.txt"
echo "build $cfg -> $out (make exit $rc)"
[ -s "$out/diagnostics.txt" ] && head -5 "$out/diagnostics.txt"
exit $rc
