/* sim64.ld — sim1802 board, SIM64 profile (docs/cdp1802/board-sim1802.md):
 * a development board with exactly as much ROM as the image needs and RAM
 * for the rest of the 64 KiB.  The ROM image (reset code, .text, .rodata and
 * the initial values of .data) starts at the reset vector 0x0000; .data is
 * copied to RAM at start-up, exactly as in HW32/32.  The ROM size is the
 * symbol __sim1802_rom_end, which scripts/run.sh passes as --rom-size.
 * Prototype for the NuttX linker script of Step 05.
 */

OUTPUT_ARCH(cdp1802)
ENTRY(__start)

MEMORY
{
  mem (rwx) : ORIGIN = 0x0000, LENGTH = 64K
}

SECTIONS
{
  .text :
  {
    KEEP(*(.reset))             /* must be first: reset starts at 0x0000 */
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > mem

  _eronly = .;                  /* ROM copy of .data starts here */

  /* RAM starts right after the ROM image (read-only part + .data copy) */
  .data _eronly + SIZEOF(.data) : AT(_eronly)
  {
    _sdata = .;
    *(.data .data.*)
    _edata = .;
  } > mem

  __sim1802_rom_end = _sdata;   /* ROM = [0, _sdata), write-protected */

  .bss (NOLOAD) :
  {
    _sbss = .;
    *(.bss .bss.*)
    *(COMMON)
    _ebss = .;
  } > mem

  ASSERT(_eronly == LOADADDR(.data), "sim64: .data load address")
}
