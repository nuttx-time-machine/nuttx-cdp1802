# Toolchain issue 0003 reproducer

`lib_getpwbufr.i` is NuttX's `libs/libc/pwd/lib_getpwbufr.c` (Apache-2.0,
NuttX commit `c7080cbdfebaecf27c7325e7c7bfee9353b9eefa`) preprocessed for the
`sim1802:minimal` configuration.

    cdp1802-elf-gcc -O1 -march=1802 -c -o /dev/null lib_getpwbufr.i   # does not finish
    cdp1802-elf-gcc -Os -march=1802 -c -o /dev/null lib_getpwbufr.i   # < 1 s
    cdp1802-elf-gcc -O2 -march=1802 -c -o /dev/null lib_getpwbufr.i   # < 1 s
