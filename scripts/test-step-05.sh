#!/usr/bin/env bash
# scripts/test-step-05.sh — Step 05 exit check: the architecture skeleton.
#   ./tools/configure.sh sim1802:minimal && make  links an ELF (SIM64
#   profile, amendment A5), with no compiler warnings; the ROM image starts
#   with the reset code; every composite R2 update is interrupt-safe; the new
#   files pass nxstyle and the port's NuttX commits pass checkpatch.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
fail() { echo "FAIL: $*"; exit 1; }

scripts/build.sh sim1802:minimal step05-minimal > /dev/null || fail "build failed"
b=build/step05-minimal
[ -s $b/nuttx.elf ] || fail "no nuttx.elf"
[ -s $b/diagnostics.txt ] && { cat $b/diagnostics.txt; fail "compiler/linker diagnostics"; }
[ "$(head -c 2 $b/nuttx.bin | od -An -tx1 | tr -d ' ')" = 7100 ] || fail "ROM image does not start with DIS; 0x00"
grep -q "sp-safety: OK" $b/sp-safety.txt || { cat $b/sp-safety.txt; fail "sp-safety"; }
echo "ok: sim1802:minimal links ($(grep '^ROM' $b/size.txt))"

gcc -o build/nxstyle nuttx/tools/nxstyle.c 2> /dev/null || fail "cannot build nxstyle"
for f in $(cd nuttx && git ls-files 'arch/cosmac/*.c' 'arch/cosmac/*.h' 'boards/cosmac/*.c' 'boards/cosmac/*.h'); do
  out=$(build/nxstyle "nuttx/$f") ; [ -z "$out" ] || { echo "$out"; fail "nxstyle $f"; }
done
echo "ok: nxstyle"
base=$(grep -o '[0-9a-f]\{40\}' docs/VERSIONS.md | head -1)
(cd nuttx && PATH=$PWD/../build:$PATH ./tools/checkpatch.sh -r -g "$base..HEAD" 2>&1 | tail -1) \
  | grep -q "All checks pass" || fail "checkpatch on $base..HEAD"
echo "ok: checkpatch $base..HEAD"

for c in 01-what-a-port-is 05-arch-directory 06-toolchain-integration 08-arch-interfaces; do
  [ -s docs/porting-guide/$c.md ] || fail "missing guide chapter $c"
done
echo "PASS: step 05"
