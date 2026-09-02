// ============================================================================
// Module: uart_mmio
// Description: UART MMIO Peripheral Wrapper
// Combines uart_tx, uart_rx, and sync_fifo instances
// Register Map:
//   +0x00 (Write): TX FIFO push (byte in wdata[7:0])
//   +0x00 (Read):  RX FIFO pop  (byte in rdata[7:0])
//   +0x08 (Read):  Status register
//     bit 0: TX FIFO full
//     bit 1: TX FIFO empty
//     bit 2: RX FIFO empty
//     bit 3: RX FIFO full
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module uart_mmio #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        reset,

    // MMIO Bus Interface
    input  wire        mmio_valid,
    input  wire        mmio_we,
    input  wire [3:0]  mmio_addr,    // Byte address within UART region (4 bits: 0x00-0x0F)
    input  wire [63:0] mmio_wdata,
    output reg  [63:0] mmio_rdata,
    output wire        mmio_ready,

    // Physical UART Pins
    output wire        uart_txd,
    input  wire        uart_rxd
);

    // UART TX/RX wires
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;

    // TX FIFO wires
    wire       tx_fifo_full, tx_fifo_empty;
    wire [7:0] tx_fifo_dout;
    reg        tx_fifo_pop;

    // RX FIFO wires
    wire       rx_fifo_full, rx_fifo_empty;
    wire [7:0] rx_fifo_dout;

    // TX FIFO push on MMIO write to +0x00
    wire tx_fifo_push = mmio_valid && mmio_we && (mmio_addr[3] == 1'b0);
    // RX FIFO pop on MMIO read from +0x00
    wire rx_fifo_pop  = mmio_valid && !mmio_we && (mmio_addr[3] == 1'b0);

    // MMIO always responds in 1 cycle
    assign mmio_ready = mmio_valid;

    // TX FIFO (CPU → TX shift register)
    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(16),
        .ADDR_WIDTH(4)
    ) tx_fifo_inst (
        .clk(clk),
        .reset(reset),
        .push(tx_fifo_push),
        .din(mmio_wdata[7:0]),
        .pop(tx_fifo_pop),
        .dout(tx_fifo_dout),
        .full(tx_fifo_full),
        .empty(tx_fifo_empty),
        .count()
    );

    // RX FIFO (RX shift register → CPU)
    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(16),
        .ADDR_WIDTH(4)
    ) rx_fifo_inst (
        .clk(clk),
        .reset(reset),
        .push(rx_valid),
        .din(rx_data),
        .pop(rx_fifo_pop),
        .dout(rx_fifo_dout),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty),
        .count()
    );

    // UART Transmitter
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) tx_inst (
        .clk(clk),
        .reset(reset),
        .data(tx_fifo_dout),
        .start(tx_fifo_pop),
        .tx(uart_txd),
        .busy(tx_busy)
    );

    // UART Receiver
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) rx_inst (
        .clk(clk),
        .reset(reset),
        .rx(uart_rxd),
        .data(rx_data),
        .valid(rx_valid)
    );

    // TX FIFO drain logic: pop from FIFO and start TX when TX is idle and FIFO not empty
    always @(posedge clk) begin
        if (reset) begin
            tx_fifo_pop <= 1'b0;
        end else begin
            tx_fifo_pop <= (!tx_busy && !tx_fifo_empty && !tx_fifo_pop);
        end
    end

    // MMIO Read Mux
    always @(*) begin
        if (mmio_addr[3] == 1'b0) begin
            // +0x00: RX data
            mmio_rdata = {56'b0, rx_fifo_dout};
        end else begin
            // +0x08: Status register
            mmio_rdata = {60'b0, rx_fifo_full, rx_fifo_empty, tx_fifo_empty, tx_fifo_full};
        end
    end

endmodule
