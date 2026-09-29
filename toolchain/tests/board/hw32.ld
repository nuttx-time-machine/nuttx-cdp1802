/* hw32.ld — sim1802 board, HW32/32 profile (docs/cdp1802/board-sim1802.md):
 * 32 KiB ROM at 0x0000 (reset vector at 0), 32 KiB RAM at 0x8000.
 * Prototype for the NuttX linker script of Step 05.
 */

OUTPUT_ARCH(cdp1802)
ENTRY(__start)

MEMORY
{
  rom (rx)  : ORIGIN = 0x0000, LENGTH = 32K
  ram (rwx) : ORIGIN = 0x8000, LENGTH = 32K
}

SECTIONS
{
  .text :
  {
    KEEP(*(.reset))             /* must be first: reset starts at 0x0000 */
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > rom

  .data :
  {
    _sdata = .;
    *(.data .data.*)
    _edata = .;
  } > ram AT > rom

  _eronly = LOADADDR(.data);    /* ROM copy of .data */

  .bss (NOLOAD) :
  {
    _sbss = .;
    *(.bss .bss.*)
    *(COMMON)
    _ebss = .;
  } > ram

  /* sim1802 fork: write-protect the whole ROM region */
  __sim1802_rom_end = ORIGIN(ram);

  /* the image (ROM contents incl. the .data copy) must fit in ROM */
  ASSERT(_eronly + SIZEOF(.data) <= ORIGIN(ram), "HW32/32: ROM overflow")
}
