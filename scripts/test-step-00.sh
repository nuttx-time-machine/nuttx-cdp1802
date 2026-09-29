#!/usr/bin/env bash
# scripts/test-step-00.sh — Step 00 exit check: repository layout and pins.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*"; exit 1; }

for f in CONTRACT.md README.md toolchain/VERSIONS toolchain/build-toolchain.sh \
         scripts/env.sh docs/VERSIONS.md docs/amendments.md docs/size-budget.md \
         docs/porting-guide/README.md docs/adr/README.md docs/journal/step-00.md; do
  [ -f "$f" ] || fail "missing $f"
done
for d in docs/cdp1802 docs/adr docs/journal docs/toolchain-issues docs/porting-guide; do
  git ls-files --error-unmatch "$d" > /dev/null 2>&1 || fail "dir $d not tracked"
done

grep -q '^## How to read this repository as a course' README.md \
  || fail "README lacks the 'how to read' section"

# The submodules must be checked out at the SHAs the meta repo records.
for sm in nuttx apps; do
  want=$(git ls-tree HEAD "$sm" | awk '{print $3}')
  have=$(git -C "$sm" rev-parse HEAD)
  [ -n "$want" ] || fail "$sm is not a submodule"
  [ "$want" = "$have" ] || fail "$sm at $have, meta repo records $want"
  grep -q "$(git -C "$sm" merge-base HEAD origin/master)" docs/VERSIONS.md \
    || fail "$sm base commit not listed in docs/VERSIONS.md"
done

# Every toolchain source is pinned by a full 40-hex SHA.
n=$(grep -cE '^[A-Z0-9]+_SHA=[0-9a-f]{40}$' toolchain/VERSIONS)
[ "$n" -ge 6 ] || fail "toolchain/VERSIONS has only $n pinned SHAs"

echo "PASS: step 00"
