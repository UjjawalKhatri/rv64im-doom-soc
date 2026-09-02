// ============================================================================
// Module: rv64_multiplier
// Description: Pipelined Hardware Multiplier with DSP48 Pipeline Registers
// Supports MUL, MULH, MULHSU, MULHU, MULW
// Enables >100 MHz Frequency Closure on Xilinx Zynq / ZedBoard FPGAs
// ============================================================================
`timescale 1ns / 1ps

module rv64_multiplier (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [2:0]  op,          // funct3: 000=MUL/MULW, 001=MULH, 010=MULHSU, 011=MULHU
    input  wire        is_word_op,  // 1 for MULW
    input  wire [63:0] a,
    input  wire [63:0] b,
    output wire        busy,
    output wire        done,
    output reg  [63:0] result
);

    // State Encoding
    localparam IDLE  = 2'b00;
    localparam COMP1 = 2'b01;
    localparam COMP2 = 2'b10;
    localparam DONE  = 2'b11;

    reg [1:0] state;
    reg [2:0] saved_op;
    reg       saved_word_op;
    reg       sign_a, sign_b;
    reg [63:0] abs_a, abs_b;
    reg [127:0] product_stage1;
    reg [127:0] product;

    wire [127:0] neg_product = -product;

    assign busy = (state != IDLE);
    assign done = (state == DONE);

    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            saved_op       <= 3'b0;
            saved_word_op  <= 1'b0;
            sign_a         <= 1'b0;
            sign_b         <= 1'b0;
            abs_a          <= 64'b0;
            abs_b          <= 64'b0;
            product_stage1 <= 128'b0;
            product        <= 128'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state         <= COMP1;
                        saved_op      <= op;
                        saved_word_op <= is_word_op;

                        if (is_word_op) begin
                            abs_a  <= {{32{1'b0}}, a[31:0]};
                            abs_b  <= {{32{1'b0}}, b[31:0]};
                            sign_a <= 1'b0;
                            sign_b <= 1'b0;
                        end else begin
                            if (op == 3'b001) begin // MULH
                                sign_a <= a[63];
                                sign_b <= b[63];
                                abs_a  <= a[63] ? (-a) : a;
                                abs_b  <= b[63] ? (-b) : b;
                            end else if (op == 3'b010) begin // MULHSU
                                sign_a <= a[63];
                                sign_b <= 1'b0;
                                abs_a  <= a[63] ? (-a) : a;
                                abs_b  <= b;
                            end else begin // MUL, MULHU
                                sign_a <= 1'b0;
                                sign_b <= 1'b0;
                                abs_a  <= a;
                                abs_b  <= b;
                            end
                        end
                    end
                end

                COMP1: begin
                    // DSP48 Partial Product Generation
                    product_stage1 <= abs_a * abs_b;
                    state          <= COMP2;
                end

                COMP2: begin
                    // DSP48 Output Pipeline Register (MREG -> PREG)
                    product <= product_stage1;
                    state   <= DONE;
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
        if (saved_word_op) begin
            result = {{32{product[31]}}, product[31:0]};
        end else begin
            case (saved_op)
                3'b000:  result = (sign_a ^ sign_b) ? neg_product[63:0] : product[63:0];
                3'b001,
                3'b010:  result = (sign_a ^ sign_b) ? neg_product[127:64] : product[127:64];
                3'b011:  result = product[127:64];
                default: result = product[63:0];
            endcase
        end
    end

endmodule
