#!/usr/bin/env bash
# docs/upstream/compare-open-flags.sh <upstream-ref>
#
# Evidence for the include/fcntl.h patch (ADR 0021): compiles every O_*
# constant with include/fcntl.h from <upstream-ref> (e.g. origin/master)
# and from the working tree, for x86_64, i386, ARM, AVR (and the CDP1802
# when its toolchain is on PATH), and prints the constants that differ.
# Expected: no difference on the 32- and 64-bit targets.
set -euo pipefail
ref=${1:-origin/master}
N=$(cd "$(dirname "$0")/../../nuttx" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"
git -C "$N" show "$ref:include/fcntl.h" > fcntl_old.h
cp "$N/include/fcntl.h" fcntl_new.h
FL="O_RDONLY O_WRONLY O_RDWR O_ACCMODE O_TEXT O_CREAT O_EXCL O_NOCTTY O_TRUNC
O_APPEND O_NONBLOCK O_DSYNC O_ASYNC O_DIRECT O_LARGEFILE O_DIRECTORY
O_NOFOLLOW O_NOATIME O_CLOEXEC __O_SYNC O_PATH __O_TMPFILE O_NDELAY O_SYNC
O_RSYNC O_TMPFILE O_BINARY _O_MAXBIT"
{
  echo '#include <nuttx/config.h>'
  echo '#include FCNTL'
  for x in $FL; do
    printf '#ifdef %s\n#define V_%s ((unsigned long long)(%s))\n#else\n#define V_%s 0xdeadbeefULL\n#endif\n' $x $x $x $x
  done
  printf 'unsigned long long v[] = {'
  for x in $FL; do printf 'V_%s, ' $x; done
  echo '};'
} > probe.c

run() {  # run <name> <endian: < or >> <arch dir> <cc...>
  local name=$1 end=$2 arch=$3; shift 3
  command -v "$1" > /dev/null || { echo "$name: $1 not found, skipped"; return; }
  mkdir -p inc-$name/nuttx; : > inc-$name/nuttx/config.h
  ln -sfn "$N/arch/$arch/include" inc-$name/arch
  for h in old new; do
    "$@" -w -c -nostdinc -Iinc-$name -isystem "$N/include" \
      -DFCNTL="\"$T/fcntl_$h.h\"" -D__NuttX__ -o $name-$h.o probe.c
    "${1%gcc}objcopy" -O binary -j .data $name-$h.o $name-$h.bin
  done
  python3 - "$name" "$end" $FL <<'PY'
import struct, sys
name, end, fl = sys.argv[1], sys.argv[2], sys.argv[3:]
val = lambda h: struct.unpack(end + "%dQ" % len(fl),
                              open("%s-%s.bin" % (name, h), "rb").read()[:8 * len(fl)])
fmt = lambda v: "undefined" if v == 0xdeadbeef else hex(v)
d = [(f, a, b) for f, a, b in zip(fl, val("old"), val("new")) if a != b]
print("%s: %d constants, %d differ" % (name, len(fl), len(d)))
for f, a, b in d:
    print("   %-12s upstream %-10s patched %s" % (f, fmt(a), fmt(b)))
PY
}
run x86_64 "<" sim gcc -m64
run i386 "<" sim gcc -m32
run arm "<" arm arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb
run avr "<" avr avr-gcc -mmcu=atmega1284p
run cdp1802 ">" cosmac cdp1802-unknown-elf-gcc -march=1802
