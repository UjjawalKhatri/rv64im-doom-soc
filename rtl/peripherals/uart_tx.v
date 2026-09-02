// ============================================================================
// Module: uart_tx
// Description: UART Transmitter (8N1) @ 115200 Baud from 100 MHz System Clock
// Shift-register based, LSB-first transmission
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output wire       busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift_reg;

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            tx        <= 1'b1;   // Idle line is HIGH
            clk_count <= 16'b0;
            bit_index <= 3'b0;
            shift_reg <= 8'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (start) begin
                        state     <= START;
                        shift_reg <= data;
                        clk_count <= 16'b0;
                    end
                end

                START: begin
                    tx <= 1'b0;  // Start bit = LOW
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        bit_index <= 3'b0;
                        state     <= DATA;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                DATA: begin
                    tx <= shift_reg[0];  // LSB first
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // Stop bit = HIGH
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        state     <= IDLE;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
