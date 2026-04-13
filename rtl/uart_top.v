//==============================================================================
// Module:      uart_top
// Description: Top-level UART wrapper. Instantiates the baud-rate generator,
//              transmitter, and receiver with shared parameters.
//              Provides a clean external interface for integration.
//
// Parameters:  CLK_FREQ    — system clock frequency in Hz
//              BAUD_RATE   — target baud rate
//              DATA_BITS   — number of data bits per frame
//              STOP_BITS   — number of stop bits (1 or 2)
//              PARITY_EN   — enable parity bit
//              PARITY_MODE — 0 = even, 1 = odd
//
// Author:      [Your Name]
// Date:        2026-04-13
//==============================================================================

`timescale 1ns / 1ps

module uart_top #(
    parameter CLK_FREQ    = 50_000_000,
    parameter BAUD_RATE   = 115_200,
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_EN   = 0,
    parameter PARITY_MODE = 0
)(
    // System
    input  wire                  clk,
    input  wire                  rst_n,

    // Transmitter interface
    input  wire                  tx_start,
    input  wire [DATA_BITS-1:0]  tx_data,
    output wire                  tx_out,
    output wire                  tx_busy,
    output wire                  tx_done,

    // Receiver interface
    input  wire                  rx_in,
    output wire [DATA_BITS-1:0]  rx_data,
    output wire                  rx_valid,
    output wire                  rx_error,
    output wire                  rx_break
);

    // =========================================================================
    // Internal wires — baud ticks
    // =========================================================================
    wire tick;
    wire tick_16x;

    // =========================================================================
    // Baud Rate Generator
    // =========================================================================
    baud_rate_gen #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_baud_rate_gen (
        .clk     (clk),
        .rst_n   (rst_n),
        .tick    (tick),
        .tick_16x(tick_16x)
    );

    // =========================================================================
    // UART Transmitter
    // =========================================================================
    uart_tx #(
        .DATA_BITS   (DATA_BITS),
        .STOP_BITS   (STOP_BITS),
        .PARITY_EN   (PARITY_EN),
        .PARITY_MODE (PARITY_MODE)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tick     (tick),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_out   (tx_out),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // =========================================================================
    // UART Receiver
    // =========================================================================
    uart_rx #(
        .DATA_BITS   (DATA_BITS),
        .STOP_BITS   (STOP_BITS),
        .PARITY_EN   (PARITY_EN),
        .PARITY_MODE (PARITY_MODE)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tick_16x (tick_16x),
        .rx_in    (rx_in),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .rx_error (rx_error),
        .rx_break (rx_break)
    );

endmodule
