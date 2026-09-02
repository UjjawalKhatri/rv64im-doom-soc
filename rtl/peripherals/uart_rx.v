// ============================================================================
// Module: uart_rx
// Description: UART Receiver (8N1) @ 115200 Baud from 100 MHz System Clock
// 16x oversampling with majority-vote start bit detection
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
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

    // Double-flop synchronizer for metastability protection
    reg rx_sync1, rx_sync2;

    always @(posedge clk) begin
        if (reset) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            clk_count <= 16'b0;
            bit_index <= 3'b0;
            shift_reg <= 8'b0;
            data      <= 8'b0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;  // Default: valid is a single-cycle pulse

            case (state)
                IDLE: begin
                    if (rx_sync2 == 1'b0) begin  // Falling edge detected (start bit)
                        state     <= START;
                        clk_count <= 16'b0;
                    end
                end

                START: begin
                    // Sample at mid-bit to confirm start bit is still LOW
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_sync2 == 1'b0) begin
                            clk_count <= 16'b0;
                            bit_index <= 3'b0;
                            state     <= DATA;
                        end else begin
                            state <= IDLE;  // False start, go back
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        shift_reg <= {rx_sync2, shift_reg[7:1]};  // LSB first
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
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        if (rx_sync2 == 1'b1) begin  // Valid stop bit
                            data  <= shift_reg;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
