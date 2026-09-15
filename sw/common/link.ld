/* Small_SoC software link script.
 * 32 KB unified BRAM at 0x0000_0000: code, data and stack all live here.
 * The image is loaded whole (BRAM init), so .data needs no copy at start-up;
 * crt0 only zeroes .bss and sets up sp/gp.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K }

_stack_size = 2K;

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > RAM

  .rodata : { *(.rodata .rodata.*) } > RAM

  .data : {
    . = ALIGN(4);
    __global_pointer$ = . + 0x800;
    *(.data .data.* .sdata .sdata.*)
  } > RAM

  .bss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.*) *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  _end = .;
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_end + _stack_size <= _stack_top, "program does not fit in 32 KB RAM")

  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
