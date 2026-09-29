/* flat.ld -- measuring link for the code-banking test: everything in one
 * region, only to get a map with the code each object keeps after
 * --gc-sections (tools/cosmac/cosmac_bank.py --map).
 */

OUTPUT_ARCH(cdp1802)
ENTRY(__start)

MEMORY
{
  mem (rwx) : ORIGIN = 0x0000, LENGTH = 64K
}

SECTIONS
{
  .text : { KEEP(*(.reset)) *(.text .text.*) *(.rodata .rodata.*) } > mem
  _eronly = .;
  .data : { _sdata = .; *(.data .data.*) _edata = .; } > mem
  .bss (NOLOAD) : { _sbss = .; *(.bss .bss.*) *(COMMON) _ebss = .; } > mem
}
