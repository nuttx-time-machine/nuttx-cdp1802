#!/usr/bin/env bash
# toolchain/build-toolchain.sh
#
# Reproducibly build the CDP1802 toolchain used by the NuttX port:
#
#   1. Erlang/OTP     (host dependency of the simulator; built from source so
#                      that no root access / distro package is required)
#   2. binutils       (mikpe/binutils-gdb, cdp1802-unknown-elf)
#   3. GCC            (mikpe/gcc, C only, soft-float, multilib 1802/1804)
#   4. cdp1802-elf-libc (mikpe, GPL-3.0; ONLY for toolchain validation)
#   5. sim1802        (mikpe, Erlang escript): the cdp1802-nuttx fork from
#                      the simulator/ submodule as $TARGET-sim, and upstream
#                      as $TARGET-sim-upstream
#
# Every source is fetched at the exact commit SHA recorded in
# toolchain/VERSIONS.  The script is idempotent: each stage writes a stamp
# file and is skipped when its stamp exists and matches the pinned SHA.
#
# Usage:
#   toolchain/build-toolchain.sh [PREFIX]
#
# Environment:
#   PREFIX   install prefix (default: <repo>/toolchain/install)
#   WORKDIR  sources + build trees (default: <repo>/toolchain/work)
#   JOBS     parallel make jobs (default: nproc)

set -euo pipefail

TOP=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=VERSIONS
. "$TOP/VERSIONS"

PREFIX=${1:-${PREFIX:-$TOP/install}}
WORKDIR=${WORKDIR:-$TOP/work}
JOBS=${JOBS:-$(nproc)}
SYSROOT=$PREFIX/$TARGET/sysroot

mkdir -p "$PREFIX" "$WORKDIR"
PREFIX=$(cd "$PREFIX" && pwd)
WORKDIR=$(cd "$WORKDIR" && pwd)
export PATH="$PREFIX/bin:$PREFIX/otp/bin:$PATH"

log() { printf '\n=== [build-toolchain] %s\n' "$*"; }

# fetch <dir> <url> <sha>: shallow-fetch exactly one commit and check it out.
fetch() {
  local dir=$1 url=$2 sha=$3
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]; then
    return 0
  fi
  log "fetch $url @ $sha"
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$sha"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  test "$(git -C "$dir" rev-parse HEAD)" = "$sha"
}

# stage <name> <sha>: returns 0 (run) when the stage is not yet done at sha.
stage() { ! grep -qx "$2" "$WORKDIR/.stamp-$1" 2>/dev/null; }
done_stage() { echo "$2" > "$WORKDIR/.stamp-$1"; }

# ---------------------------------------------------------------- Erlang/OTP
if stage otp "$OTP_SHA"; then
  fetch "$WORKDIR/otp" "$OTP_URL" "$OTP_SHA"
  log "build Erlang/OTP $OTP_TAG"
  (
    cd "$WORKDIR/otp"
    ./configure --prefix="$PREFIX/otp" --without-javac --without-wx \
      --without-odbc --without-jinterface --without-debugger \
      --without-observer --without-et --without-megaco --without-diameter \
      --disable-silent-rules > "$WORKDIR/otp-configure.log" 2>&1
    make -j"$JOBS" > "$WORKDIR/otp-build.log" 2>&1
    make install > "$WORKDIR/otp-install.log" 2>&1
  )
  done_stage otp "$OTP_SHA"
fi

# ---------------------------------------------------------------- rebar3
if stage rebar3 "$REBAR3_SHA"; then
  fetch "$WORKDIR/rebar3" "$REBAR3_URL" "$REBAR3_SHA"
  log "bootstrap rebar3 $REBAR3_TAG"
  (cd "$WORKDIR/rebar3" && ./bootstrap > "$WORKDIR/rebar3.log" 2>&1)
  install -D -m 755 "$WORKDIR/rebar3/rebar3" "$PREFIX/bin/rebar3"
  done_stage rebar3 "$REBAR3_SHA"
fi

# ---------------------------------------------------------------- binutils
if stage binutils "$BINUTILS_SHA"; then
  fetch "$WORKDIR/binutils-gdb" "$BINUTILS_URL" "$BINUTILS_SHA"
  log "build binutils for $TARGET"
  rm -rf "$WORKDIR/build-binutils"
  mkdir -p "$WORKDIR/build-binutils"
  (
    cd "$WORKDIR/build-binutils"
    ../binutils-gdb/configure --target="$TARGET" --prefix="$PREFIX" \
      --with-sysroot="$SYSROOT" --disable-nls --disable-werror \
      --disable-gdb --disable-gdbserver --disable-sim --disable-gprofng \
      --disable-libdecnumber --disable-readline \
      > "$WORKDIR/binutils-configure.log" 2>&1
    make -j"$JOBS" > "$WORKDIR/binutils-build.log" 2>&1
    make install > "$WORKDIR/binutils-install.log" 2>&1
  )
  done_stage binutils "$BINUTILS_SHA"
fi

# ---------------------------------------------------------------- GCC
# --with-arch=1802 makes the default multilib the "1802" one, which is where
#   the libc Makefile installs crt0.o/libc.a (sysroot/usr/lib/1802).
# --disable-gcov: NuttX does not need libgcov (see docs/journal/step-01.md).
# --without-headers --with-newlib: build libgcc with inhibit_libc, i.e.
#   without ANY target libc headers, so that the libgcc linked into NuttX
#   does not depend on mikpe's GPL libc (ADR 0004).  --with-newlib is GCC's
#   standard "no target libc yet" switch; no newlib code is used.
GCC_CONFIG=(--with-arch=1802 --without-headers --with-newlib
  --enable-languages=c --disable-nls
  --disable-shared --disable-threads --disable-libssp --disable-libquadmath
  --disable-libgomp --disable-libatomic --disable-bootstrap --disable-werror
  --disable-gcov)
GCC_STAMP="$GCC_SHA $(echo "${GCC_CONFIG[*]}" | md5sum | cut -c1-8)"
if stage gcc "$GCC_STAMP"; then
  fetch "$WORKDIR/gcc" "$GCC_URL" "$GCC_SHA"
  log "build GCC for $TARGET"
  # fixincludes requires the sysroot include directory to exist; it stays
  # empty of libc headers until the (validation-only) libc stage below.
  mkdir -p "$SYSROOT/usr/include"
  rm -rf "$WORKDIR/build-gcc"
  mkdir -p "$WORKDIR/build-gcc"
  (
    cd "$WORKDIR/build-gcc"
    ../gcc/configure --target="$TARGET" --prefix="$PREFIX" \
      --with-sysroot="$SYSROOT" "${GCC_CONFIG[@]}" \
      > "$WORKDIR/gcc-configure.log" 2>&1
    make -j"$JOBS" all-gcc all-target-libgcc > "$WORKDIR/gcc-build.log" 2>&1
    make install-gcc install-target-libgcc > "$WORKDIR/gcc-install.log" 2>&1
  )
  done_stage gcc "$GCC_STAMP"
fi

# ---------------------------------------------------------------- libc
fetch "$WORKDIR/cdp1802-elf-libc" "$LIBC_URL" "$LIBC_SHA"
if stage libc "$LIBC_SHA"; then
  log "build cdp1802-elf-libc (validation only, never linked into NuttX)"
  (
    cd "$WORKDIR/cdp1802-elf-libc"
    make clean > /dev/null 2>&1 || true
    make PREFIX="$SYSROOT" build > "$WORKDIR/libc-build.log" 2>&1
    make PREFIX="$SYSROOT" install > "$WORKDIR/libc-install.log" 2>&1
  )
  done_stage libc "$LIBC_SHA"
fi

# ---------------------------------------------------------------- sim1802
# build_sim <srcdir> <installed-name>: build the escript only; do not let
# "make install" edit the user's ~/.dejagnurc.
build_sim() {
  (
    cd "$1"
    make REBAR3="$PREFIX/bin/rebar3" build > "$WORKDIR/$2-build.log" 2>&1
    install -D -m 755 _build/default/bin/sim1802 "$PREFIX/bin/$2"
  )
}

if stage sim1802-upstream "$SIM_UPSTREAM_SHA"; then
  fetch "$WORKDIR/sim1802" "$SIM_UPSTREAM_URL" "$SIM_UPSTREAM_SHA"
  log "build upstream sim1802 (for the Step 02 audit)"
  build_sim "$WORKDIR/sim1802" "$TARGET-sim-upstream"
  done_stage sim1802-upstream "$SIM_UPSTREAM_SHA"
fi

SIM_DIR=$(cd "$TOP/.." && pwd)/$SIM_SRC
[ -f "$SIM_DIR/src/sim1802_core.erl" ] \
  || { echo "missing $SIM_DIR: run 'git submodule update --init'" >&2; exit 1; }
if have=$(git -C "$SIM_DIR" rev-parse HEAD 2> /dev/null); then
  [ "$have" = "$SIM_SHA" ] || { echo "$SIM_DIR is at $have, VERSIONS pins $SIM_SHA" >&2; exit 1; }
  [ -z "$(git -C "$SIM_DIR" status --porcelain --untracked-files=no)" ] \
    || { echo "$SIM_DIR has uncommitted changes" >&2; exit 1; }
else
  # e.g. inside the Docker build, where the submodule's .git is not copied
  echo "note: $SIM_DIR is not a git checkout; trusting it is $SIM_SHA"
fi
if stage sim1802 "$SIM_SHA"; then
  log "build sim1802 cdp1802-nuttx fork @ $SIM_SHA"
  build_sim "$SIM_DIR" "$TARGET-sim"
  done_stage sim1802 "$SIM_SHA"
fi

# ---------------------------------------------------------------- short names
# Amendment A3 (accepted): the contract names the tools cdp1802-elf-*.  The
# canonical triplet stays cdp1802-unknown-elf (mikpe's libc and sim1802
# expect it); cdp1802-elf-* are symlinks to the same binaries.  The GCC
# driver resolves its own path through symlinks, so it finds cc1/as/ld.
for tool in "$PREFIX/bin/$TARGET-"*; do
  short="$PREFIX/bin/cdp1802-elf-${tool##*/$TARGET-}"
  ln -sfn "${tool##*/}" "$short"
done

log "done. Add to PATH: $PREFIX/bin:$PREFIX/otp/bin"
"$PREFIX/bin/cdp1802-elf-gcc" --version | head -1
"$PREFIX/bin/cdp1802-elf-as" --version | head -1
