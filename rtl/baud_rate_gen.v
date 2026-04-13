//==============================================================================
// Module:      baud_rate_gen
// Description: Parameterized baud-rate tick generator for UART.
//              Produces a single-cycle 'tick' pulse at the baud rate and
//              a 'tick_16x' pulse at 16× the baud rate (for RX oversampling).
//              Uses free-running counters (clock-enable style), NOT clock
//              dividers — this is the FPGA best practice.
//
// Parameters:  CLK_FREQ  — system clock frequency in Hz (default 50 MHz)
//              BAUD_RATE — desired baud rate (default 115200)
//
// Author:      [Your Name]
// Date:        2026-04-13
//==============================================================================

`timescale 1ns / 1ps

module baud_rate_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick,
    output reg  tick_16x
);

    // -------------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------------
    localparam TICKS_PER_BIT    = CLK_FREQ / BAUD_RATE;
    // Derive from TICKS_PER_BIT so that exactly 16 samples == 1 bit period
    localparam TICKS_PER_SAMPLE = TICKS_PER_BIT / 16;

    // Counter widths sized to hold the max count value
    localparam BIT_CNT_WIDTH    = $clog2(TICKS_PER_BIT);
    localparam SAMPLE_CNT_WIDTH = $clog2(TICKS_PER_SAMPLE);

    // -------------------------------------------------------------------------
    // 1× baud-rate counter  →  'tick'
    // -------------------------------------------------------------------------
    reg [BIT_CNT_WIDTH-1:0] bit_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            bit_cnt <= 0;
            tick    <= 1'b0;
        end else if (bit_cnt == TICKS_PER_BIT - 1) begin
            bit_cnt <= 0;
            tick    <= 1'b1;
        end else begin
            bit_cnt <= bit_cnt + 1;
            tick    <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 16× baud-rate counter  →  'tick_16x'
    // -------------------------------------------------------------------------
    reg [SAMPLE_CNT_WIDTH-1:0] sample_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_cnt <= 0;
            tick_16x   <= 1'b0;
        end else if (sample_cnt == TICKS_PER_SAMPLE - 1) begin
            sample_cnt <= 0;
            tick_16x   <= 1'b1;
        end else begin
            sample_cnt <= sample_cnt + 1;
            tick_16x   <= 1'b0;
        end
    end

endmodule
