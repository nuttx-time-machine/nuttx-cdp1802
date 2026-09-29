# scripts/env.sh — source this file: ". scripts/env.sh"
#
# Puts the pinned CDP1802 toolchain (built by toolchain/build-toolchain.sh)
# and the Erlang runtime needed by the simulator on PATH.

CDP1802_TOP=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
CDP1802_PREFIX=${CDP1802_PREFIX:-$CDP1802_TOP/toolchain/install}
CDP1802_TARGET=cdp1802-unknown-elf

export CDP1802_TOP CDP1802_PREFIX CDP1802_TARGET
export PATH="$CDP1802_PREFIX/bin:$CDP1802_PREFIX/otp/bin:$PATH"

# Python checkers used by NuttX's tools/checkpatch.sh (black, flake8,
# isort), installed by scripts/setup-checkers.sh.
if [ -d "$CDP1802_TOP/build/pyvenv/bin" ]; then
  export PATH="$CDP1802_TOP/build/pyvenv/bin:$PATH"
fi
