# Minimal reproduction of the ra-corruption bug.
# Linked at 0x80000000 (executes from DDR via the arbiter).
# Pattern: DDR store, then `jal callee`; callee saves/restores ra across a
# burst of DDR stores and returns. If the return address is corrupted, the
# `ret` jumps to a bad address (testbench flags CRASH). If it returns cleanly,
# the post-call marker 0x22 is written (testbench flags SUCCESS).
.section .text
.global _start
_start:
    lui  sp, 0x80010          # sp = 0x80010000 (stack in DDR)
    lui  t0, 0x80020
    li   t1, 0x21
    sd   t1, 0(t0)            # DDR store immediately before the call (like TRACE)
    jal  ra, callee           # ra should be _start+... (a 0x8000xxxx code addr)
    lui  t0, 0x80020
    li   t1, 0x22
    sd   t1, 8(t0)            # SUCCESS marker -> phys 0x00020008

    # High-DDR write test (mimic Z_Init writing the zone at 0x82000000).
    # On hardware this address read back as garbage; check it in sim.
    lui  t0, 0x82000          # t0 = 0x82000000 -> phys 0x02000000
    li   t1, 0x00C0FFEE
    sd   t1, 0(t0)            # store to zone base
    ld   t2, 0(t0)            # read it back
    lui  t3, 0x80020
    sd   t2, 16(t3)           # readback -> phys 0x00020010 (TB checks == 0xC0FFEE)

    # Test 3: DDR load -> ALU -> store (operand must survive an EX stall).
    # 0x80030000 holds 0x1234 (written by callee earlier).
    lui  t0, 0x80030
    ld   t4, 0(t0)            # t4 = 0x1234
    addiw t5, t4, 1           # t5 = 0x1235  (load -> ALU consumer)
    lui  t3, 0x80020
    sd   t5, 32(t3)           # -> phys 0x00020020, TB expects 0x1235

    # Test 4: DDR load -> branch compare (load feeds branch_unit operands)
    lui  t0, 0x80030
    ld   t6, 0(t0)            # t6 = 0x1234
    lui  a0, 0x1
    addiw a0, a0, 564         # a0 = 0x1234
    bne  t6, a0, tfail        # load -> branch
    lui  a1, 0xA
    j    tstore
tfail:
    lui  a1, 0xB
tstore:
    lui  t3, 0x80020
    sd   a1, 40(t3)           # -> phys 0x00020028, TB expects 0xA000 (pass)
done:
    j    done

callee:
    addi sp, sp, -32
    sd   ra, 24(sp)           # save incoming ra to stack (DDR)
    mv   s0, ra               # also capture incoming ra in s0
    lui  t0, 0x80030
    li   t1, 0x1234
    sd   t1, 0(t0)            # body DDR stores (mimic Z_Init zone init)
    sd   t1, 8(t0)
    sd   t1, 16(t0)
    sd   s0, 24(t0)           # store captured incoming ra -> phys 0x00030018
    ld   ra, 24(sp)           # restore ra (the failing pattern)
    addi sp, sp, 32
    ret
