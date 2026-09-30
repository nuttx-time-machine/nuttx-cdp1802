# scripts/env.sh — source this file: ". scripts/env.sh"
#
# Puts the pinned CDP1802 toolchain (built by toolchain/build-toolchain.sh)
# and the Erlang runtime needed by the simulator on PATH.

# Find this file: bash knows it (BASH_SOURCE), zsh puts it in $0; POSIX sh
# (dash) does not tell a sourced file its path, so fall back to the
# current directory (the repository or its scripts/ directory).
_cdp1802_env=${BASH_SOURCE:-$0}
case $_cdp1802_env in
  *env.sh) ;;
  *) if [ -f scripts/env.sh ]; then
       _cdp1802_env=scripts/env.sh
     elif [ -f env.sh ]; then
       _cdp1802_env=./env.sh
     else
       echo "env.sh: run it from the repository: . scripts/env.sh" >&2
     fi ;;
esac
if [ -n "${BASH_SOURCE:-}" ] && [ "$BASH_SOURCE" = "$0" ]; then
  echo "env.sh: source it (\". scripts/env.sh\"); running it changes nothing" >&2
fi

CDP1802_TOP=$(cd "$(dirname "$_cdp1802_env")/.." && pwd)
unset _cdp1802_env
CDP1802_PREFIX=${CDP1802_PREFIX:-$CDP1802_TOP/toolchain/install}
CDP1802_TARGET=cdp1802-unknown-elf

export CDP1802_TOP CDP1802_PREFIX CDP1802_TARGET
export PATH="$CDP1802_PREFIX/bin:$CDP1802_PREFIX/otp/bin:$PATH"

# Python checkers used by NuttX's tools/checkpatch.sh (black, flake8,
# isort), installed by scripts/setup-checkers.sh.
if [ -d "$CDP1802_TOP/build/pyvenv/bin" ]; then
  export PATH="$CDP1802_TOP/build/pyvenv/bin:$PATH"
fi
