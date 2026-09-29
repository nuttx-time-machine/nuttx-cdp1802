#!/usr/bin/env bash
# scripts/measure-step-04.sh — reproduce every measurement of the Step 04
# size-feasibility report (docs/journal/step-04.md).  Takes ~25 minutes
# (the -O2 build is slow with this compiler).  Needs, besides the CDP1802
# toolchain, arm-none-eabi-gcc and avr-gcc on PATH for the comparison
# boards (Ubuntu: gcc-arm-none-eabi, gcc-avr, avr-libc).  Results: build/*/size.txt
set -uo pipefail
cd "$(dirname "$0")/.."

B=scripts/build.sh
OPT="--disable DEBUG_FULLOPT --enable DEBUG_CUSTOMOPT --set-str DEBUG_OPTLEVEL"
SMALL="--enable DEFAULT_SMALL --enable DISABLE_MOUNTPOINT --set-val NUNGET_CHARS 0 \
  --set-val STDIO_BUFFER_SIZE 0 --set-val TASK_NAME_SIZE 0 --enable DEBUG_LINK_MAP \
  --enable CONSOLE_SYSLOG --enable DISABLE_PTHREAD"

# CDP1802 variants
$B sim1802:minimal minimal-Os COSMAC_GCC_WORKAROUNDS=
$B sim1802:minimal minimal-Os-nsw
BUILD_TWEAKS="$OPT -O2" $B sim1802:minimal minimal-O2 COSMAC_GCC_WORKAROUNDS=
$B sim1802:minimal minimal-1804-Os ARCHCPUFLAGS=-march=1804 COSMAC_GCC_WORKAROUNDS=
$B sim1802:minimal minimal-1804-Os-nsw ARCHCPUFLAGS=-march=1804
printf '%s\n' 'CONFIG_DISABLE_ALL_SIGNALS=y' > build/nosig.frag
BUILD_FRAGMENT=$PWD/build/nosig.frag $B sim1802:minimal minimal-Os-nosig COSMAC_GCC_WORKAROUNDS=
# (-O1 is not measured: the compiler hangs, toolchain issue 0003)

# Comparison boards, same configuration shape
ARM="--disable SYSTEM_NSH --disable NSH_LIBRARY --enable EXAMPLES_HELLO \
  --set-str INIT_ENTRYPOINT hello_main $SMALL --disable FS_PROCFS \
  --disable DEBUG_SYMBOLS --disable DEBUG_NOOPT --enable DEBUG_FULLOPT"
BUILD_TWEAKS="$ARM" $B nucleo-f072rb:nsh cmp-m0
BUILD_TWEAKS="$ARM" $B stm32f103-minimum:hello cmp-m3
BUILD_TWEAKS="$SMALL --disable DEBUG_SYMBOLS $OPT -Os" $B arduino-mega2560:hello cmp-avr

# NSH with the NSH feature set of stm32f103-minimum:nsh
NSH="--enable SYSTEM_NSH --enable NSH_LIBRARY --set-str INIT_ENTRYPOINT nsh_main \
  --disable EXAMPLES_HELLO $SMALL --disable FS_PROCFS"
BUILD_TWEAKS="$NSH --disable DEBUG_SYMBOLS --disable DEBUG_NOOPT --enable DEBUG_FULLOPT" \
  $B stm32f103-minimum:nsh nsh-m3
{ grep -E "^(# )?CONFIG_(NSH|SYSTEM|READLINE)\w*( is not set|=)" build/nsh-m3/config
  printf '%s\n' 'CONFIG_INIT_ENTRYPOINT="nsh_main"' '# CONFIG_EXAMPLES_HELLO is not set' \
    'CONFIG_DEFAULT_SMALL=y' 'CONFIG_DISABLE_MOUNTPOINT=y' 'CONFIG_NUNGET_CHARS=0' \
    'CONFIG_STDIO_BUFFER_SIZE=0' 'CONFIG_TASK_NAME_SIZE=0' 'CONFIG_DEBUG_LINK_MAP=y' \
    'CONFIG_CONSOLE_SYSLOG=y' 'CONFIG_DISABLE_PTHREAD=y' '# CONFIG_FS_PROCFS is not set'
} > build/nsh-like-m3.frag
BUILD_FRAGMENT=$PWD/build/nsh-like-m3.frag $B sim1802:minimal nsh-cdp1802 COSMAC_GCC_WORKAROUNDS=

for d in minimal-Os minimal-Os-nsw minimal-O2 minimal-1804-Os minimal-1804-Os-nsw \
         minimal-Os-nosig cmp-m0 cmp-m3 cmp-avr nsh-m3 nsh-cdp1802; do
  printf '%-22s %s\n' "$d" "$(grep '^ROM' build/$d/size.txt)"
done
# The 32-bit time experiment (include/sys/types.h: time_t/clock_t int32_t,
# on a throw-away branch) is described in the journal; it is not automated
# because it modifies common code.
