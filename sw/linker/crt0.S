# ============================================================================
# File: crt0.S
# Description: Minimal RISC-V 64-bit Startup Code for DOOM SoC
# Initializes stack pointer, clears BSS, and jumps to main()
# ============================================================================

.section .text.init
.global _start
.type _start, @function

_start:
    # 1. Initialize all 32 architectural registers to zero
    li  x1,  0
    li  x2,  0
    li  x3,  0
    li  x4,  0
    li  x5,  0
    li  x6,  0
    li  x7,  0
    li  x8,  0
    li  x9,  0
    li  x10, 0
    li  x11, 0
    li  x12, 0
    li  x13, 0
    li  x14, 0
    li  x15, 0
    li  x16, 0
    li  x17, 0
    li  x18, 0
    li  x19, 0
    li  x20, 0
    li  x21, 0
    li  x22, 0
    li  x23, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0

    # Milestone 1: Reached _start! Turn on LED 0 (0x01)
    li  t0, 0x10001008
    li  t1, 0x01
    sd  t1, 0(t0)

    # 2. Set up the Stack Pointer (SP = x2)
    la  sp, __stack_top

    # Milestone 2: Stack pointer set! Turn on LED 0 & 1 (0x03)
    li  t0, 0x10001008
    li  t1, 0x03
    sd  t1, 0(t0)

    # 3. Clear .bss section to zero
    la  t0, __bss_start
    la  t1, __bss_end
1:
    bgeu t0, t1, 2f
    sd  zero, 0(t0)
    addi t0, t0, 8
    j   1b

2:
    # Milestone 3: BSS cleared! Turn on LED 0, 1, 2 (0x07)
    li  t0, 0x10001008
    li  t1, 0x07
    sd  t1, 0(t0)

    # Milestone 4: Calling main! Turn on LED 0-3 (0x0F)
    li  t1, 0x0F
    sd  t1, 0(t0)

    # 4. Jump to C main() entry point
    call main

    # Milestone 5 (if main returns): Turn on LED 0-5 (0x3F)
    li  t0, 0x10001008
    li  t1, 0x3F
    sd  t1, 0(t0)

    # 5. Trap if main() ever returns (infinite loop)
_hang:
    j   _hang

.size _start, . - _start
