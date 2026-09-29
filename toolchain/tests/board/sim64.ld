/* sim64.ld — sim1802 board, SIM64 profile (docs/cdp1802/board-sim1802.md):
 * the whole 64 KiB address space; read-only code and data start at the
 * reset vector 0x0000 and are write-protected, RAM is everything after.
 * .data is loaded in place (load address = run address), so the start-up
 * copy loop does nothing.  Prototype for the NuttX linker script of Step 05.
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

  /* sim1802 fork: write-protect everything read-only */
  __sim1802_rom_end = .;

  .data :
  {
    _sdata = .;
    *(.data .data.*)
    _edata = .;
  } > mem

  _eronly = LOADADDR(.data);    /* == _sdata: nothing to copy */

  .bss (NOLOAD) :
  {
    _sbss = .;
    *(.bss .bss.*)
    *(COMMON)
    _ebss = .;
  } > mem

  /* the sim1802 loader rejects loadable bytes above 0xFF00 */
  ASSERT(_edata <= 0xFF00, "sim1802: loadable image must end below 0xFF00")
}
