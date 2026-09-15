/* Small_SoC: 32 KB unified BRAM at 0x0000_0000, reset vector 0x0. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K }

SECTIONS
{
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > RAM

  .rodata : { *(.rodata .rodata.*) } > RAM
  .data   : { *(.data .data.* .sdata .sdata*) } > RAM
  .bss    : { *(.bss .bss.* .sbss .sbss*) *(COMMON) } > RAM

  /DISCARD/ : { *(.tohost) *(.comment) *(.riscv.attributes) }
}
