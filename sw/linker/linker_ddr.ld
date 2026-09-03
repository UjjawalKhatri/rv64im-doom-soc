/* ============================================================================
 * Linker Script for DOOM RV64IM Bare-Metal on ZedBoard DDR3
 * Code, Rodata, Data, BSS live in DDR3 at 0x8010_0000 (DDR offset 1 MB)
 * WAD is at 0x8100_0000 (16 MB), Zone Heap is at 0x8200_0000 (32 MB)
 * ============================================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* DDR3 Memory Partition for DOOM Binary & Stack */
    DDR (rwx) : ORIGIN = 0x80100000, LENGTH = 15M
}

SECTIONS
{
    /* 1. Code Segment */
    .text : ALIGN(8)
    {
        *(.text.init)
        *(.text .text.*)
    } > DDR

    /* 2. Read-Only Data */
    .rodata : ALIGN(8)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > DDR

    /* 3. Initialized Data */
    .data : ALIGN(8)
    {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        __data_end = .;
    } > DDR

    /* 4. Uninitialized Data (Zeroed by crt0.S) */
    .bss : ALIGN(8)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        __bss_end = .;
    } > DDR

    /* 5. Stack Top */
    . = ALIGN(16);
    __stack_top = ORIGIN(DDR) + LENGTH(DDR) - 16;
}
