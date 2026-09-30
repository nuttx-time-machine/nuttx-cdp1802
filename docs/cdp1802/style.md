# Style checks in the step tests

The step tests run NuttX's `tools/checkpatch.sh -r -g <base>..HEAD` on the
`cdp1802-port` branch, together with `nxstyle` on every file under
`arch/cosmac` and `boards/cosmac`.

`-r` checks only the lines each commit changes. Until ADR 0025 every
touched common-code file passed a whole-file check anyway. Since then the
branch touches `libs/libc/stream/lib_libvsprintf.c` and
`lib_ultoa_invert.c`, whose upstream versions already fail nxstyle:
- `lib_libvsprintf.c` has 78 "Bad alignment" errors, left behind when
  upstream commit `1b3af76bf3` removed the `CONFIG_LIBC_LONG_LONG`
  conditionals;
- `lib_ultoa_invert.c` has an `if`/`else` without braces.

Reformatting upstream code the port does not otherwise change would only
make the branch diverge. The port's own files are still checked whole.
Upstream CI checks whole files (`checkpatch.sh -c -u -m -g`), so a patch
submitted upstream for these files would have to fix their style first.
