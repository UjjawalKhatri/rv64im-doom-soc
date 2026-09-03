/* ============================================================================
 * Linker Script for DOOM SoC On-Chip Memory (8KB Instruction + 8KB Data)
 * ============================================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
}

SECTIONS
{
    /* 1. Code Segment */
    .text : ALIGN(8)
    {
        *(.text.init)
        *(.text .text.*)
    } > RAM

    /* 2. Read-Only Data */
    .rodata : ALIGN(8)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > RAM

    /* 3. Initialized Data */
    .data : ALIGN(8)
    {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        __data_end = .;
    } > RAM

    /* 4. Uninitialized Data (Zeroed by crt0.S) */
    .bss : ALIGN(8)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    /* 5. Stack Top in 8KB Space */
    . = ALIGN(16);
    __stack_top = 0x00001FF0;
}
