// ============================================================================
// Module: rv64_divider
// Description: Multicycle Hardware Iterative Restoring Divider (65-bit wide)
// Supports DIV, DIVU, REM, REMU, DIVW, DIVUW, REMW, REMUW
// Compliant with RISC-V Spec for Div-by-Zero and Signed Overflow (INT_MIN / -1)
// Compatible with Xilinx Vivado Synthesis & FPGA Implementation
// ============================================================================
`timescale 1ns / 1ps

module rv64_divider (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [2:0]  op,          // funct3: 100=DIV/W, 101=DIVU/W, 110=REM/W, 111=REMU/W
    input  wire        is_word_op,  // 1 for DIVW, DIVUW, REMW, REMUW
    input  wire [63:0] a,           // Dividend
    input  wire [63:0] b,           // Divisor
    output wire        busy,
    output wire        done,
    output reg  [63:0] result
);

    // State Encoding
    localparam IDLE = 2'b00;
    localparam CALC = 2'b01;
    localparam DONE = 2'b10;

    reg [1:0]  state;
    reg [2:0]  saved_op;
    reg        saved_word_op;
    reg [6:0]  count;

    reg [63:0] quotient;
    reg [63:0] remainder;
    reg [63:0] divisor;

    reg sign_q, sign_r;
    reg is_special;
    reg [63:0] special_res;

    wire [31:0] a32 = a[31:0];
    wire [31:0] b32 = b[31:0];

    wire [63:0] q_signed = saved_word_op ? {{32{quotient[31]}}, quotient[31:0]} : quotient;
    wire [63:0] r_signed = saved_word_op ? {{32{remainder[31]}}, remainder[31:0]} : remainder;

    wire [63:0] final_q = sign_q ? (-q_signed) : q_signed;
    wire [63:0] final_r = sign_r ? (-r_signed) : r_signed;

    assign busy = (state != IDLE);
    assign done = (state == DONE);

    // 65-bit shift accumulator for restoring division
    wire shift_bit = saved_word_op ? quotient[31] : quotient[63];
    wire [64:0] rem_shift = {remainder[63:0], shift_bit};

    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            saved_op      <= 3'b0;
            saved_word_op <= 1'b0;
            count         <= 7'd0;
            quotient      <= 64'b0;
            remainder     <= 64'b0;
            divisor       <= 64'b0;
            sign_q        <= 1'b0;
            sign_r        <= 1'b0;
            is_special    <= 1'b0;
            special_res   <= 64'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        saved_op      <= op;
                        saved_word_op <= is_word_op;
                        is_special    <= 1'b0;

                        // ----------------------------------------------------
                        // 1. Handle Spec Corner Cases (Div by Zero & Overflow)
                        // ----------------------------------------------------
                        if (is_word_op) begin
                            if (b32 == 32'b0) begin
                                state      <= DONE;
                                is_special <= 1'b1;
                                case (op)
                                    3'b100: special_res <= 64'hFFFFFFFFFFFFFFFF;                 // DIVW by 0 -> -1
                                    3'b101: special_res <= 64'hFFFFFFFFFFFFFFFF;                 // DIVUW by 0 -> 0xFFFFFFFFFFFFFFFF (sign-extended MAX_UINT32)
                                    3'b110, 3'b111: special_res <= {{32{a32[31]}}, a32};        // REMW/REMUW by 0 -> dividend
                                    default: special_res <= 64'hFFFFFFFFFFFFFFFF;
                                endcase
                            end else if (op == 3'b100 && a32 == 32'h80000000 && b32 == 32'hFFFFFFFF) begin
                                state       <= DONE;
                                is_special  <= 1'b1;
                                special_res <= 64'hFFFFFFFF80000000;                             // DIVW overflow -> INT_MIN32
                            end else if (op == 3'b110 && a32 == 32'h80000000 && b32 == 32'hFFFFFFFF) begin
                                state       <= DONE;
                                is_special  <= 1'b1;
                                special_res <= 64'b0;                                            // REMW overflow -> 0
                            end else begin
                                state <= CALC;
                                count <= 7'd32;
                                if (op == 3'b100 || op == 3'b110) begin // Signed 32-bit
                                    sign_q    <= a32[31] ^ b32[31];
                                    sign_r    <= a32[31];
                                    quotient  <= a32[31] ? {32'b0, (-a32)} : {32'b0, a32};
                                    divisor   <= b32[31] ? {32'b0, (-b32)} : {32'b0, b32};
                                end else begin // Unsigned 32-bit
                                    sign_q    <= 1'b0;
                                    sign_r    <= 1'b0;
                                    quotient  <= {32'b0, a32};
                                    divisor   <= {32'b0, b32};
                                end
                                remainder <= 64'b0;
                            end
                        end else begin
                            // 64-bit operations
                            if (b == 64'b0) begin
                                state      <= DONE;
                                is_special <= 1'b1;
                                case (op)
                                    3'b100, 3'b101: special_res <= 64'hFFFFFFFFFFFFFFFF;         // DIV/DIVU by 0 -> MAX_UINT64 / -1
                                    3'b110, 3'b111: special_res <= a;                             // REM/REMU by 0 -> dividend
                                    default: special_res <= 64'hFFFFFFFFFFFFFFFF;
                                endcase
                            end else if (op == 3'b100 && a == 64'h8000000000000000 && b == 64'hFFFFFFFFFFFFFFFF) begin
                                state       <= DONE;
                                is_special  <= 1'b1;
                                special_res <= 64'h8000000000000000;                             // DIV overflow -> INT_MIN64
                            end else if (op == 3'b110 && a == 64'h8000000000000000 && b == 64'hFFFFFFFFFFFFFFFF) begin
                                state       <= DONE;
                                is_special  <= 1'b1;
                                special_res <= 64'b0;                                            // REM overflow -> 0
                            end else begin
                                state <= CALC;
                                count <= 7'd64;
                                if (op == 3'b100 || op == 3'b110) begin // Signed 64-bit
                                    sign_q    <= a[63] ^ b[63];
                                    sign_r    <= a[63];
                                    quotient  <= a[63] ? (-a) : a;
                                    divisor   <= b[63] ? (-b) : b;
                                end else begin // Unsigned 64-bit
                                    sign_q    <= 1'b0;
                                    sign_r    <= 1'b0;
                                    quotient  <= a;
                                    divisor   <= b;
                                end
                                remainder <= 64'b0;
                            end
                        end
                    end
                end

                CALC: begin
                    // 65-bit restoring division step
                    if (count != 7'd0) begin
                        count <= count - 7'd1;
                        if (rem_shift >= {1'b0, divisor}) begin
                            remainder <= rem_shift[63:0] - divisor;
                            quotient  <= {quotient[62:0], 1'b1};
                        end else begin
                            remainder <= rem_shift[63:0];
                            quotient  <= {quotient[62:0], 1'b0};
                        end
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Combinational Result Selection
    always @(*) begin
        if (is_special) begin
            result = special_res;
        end else if (saved_word_op) begin
            if (saved_op == 3'b100 || saved_op == 3'b101)
                result = {{32{final_q[31]}}, final_q[31:0]};
            else
                result = {{32{final_r[31]}}, final_r[31:0]};
        end else begin
            if (saved_op == 3'b100 || saved_op == 3'b101)
                result = final_q;
            else
                result = final_r;
        end
    end

endmodule
