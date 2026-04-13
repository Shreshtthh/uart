//==============================================================================
// Module:      uart_tx
// Description: Parameterized UART Transmitter.
//              Serialises parallel data with configurable data bits, stop bits,
//              and optional parity (even/odd). Uses a finite state machine
//              driven by a baud-rate tick.
//
// Parameters:  DATA_BITS   — number of data bits (default 8)
//              STOP_BITS   — 1 or 2 stop bits (default 1)
//              PARITY_EN   — 0 = no parity, 1 = parity enabled (default 0)
//              PARITY_MODE — 0 = even parity, 1 = odd parity (default 0)
//
// Interface:   tx_start  — pulse high for 1 clk cycle to begin transmission
//              tx_data   — parallel data input (active when tx_start is high)
//              tx_out    — serial output (idles HIGH)
//              tx_busy   — high while a transmission is in progress
//              tx_done   — single-cycle pulse when transmission completes
//
// Author:      Shreshth
// Date:        2026-04-13
//==============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_EN   = 0,
    parameter PARITY_MODE = 0    // 0 = even, 1 = odd
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  tick,       // baud-rate tick from baud_rate_gen
    input  wire                  tx_start,   // pulse to begin TX
    input  wire [DATA_BITS-1:0]  tx_data,    // parallel data in
    output reg                   tx_out,     // serial line out (idles high)
    output wire                  tx_busy,    // high during transmission
    output reg                   tx_done     // single-cycle completion pulse
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0] S_IDLE   = 3'd0,
                     S_START  = 3'd1,
                     S_DATA   = 3'd2,
                     S_PARITY = 3'd3,
                     S_STOP   = 3'd4;

    reg [2:0] state, next_state;

    // =========================================================================
    // Internal registers
    // =========================================================================
    reg [DATA_BITS-1:0]        shift_reg;   // data shift register
    reg [$clog2(DATA_BITS)-1:0] bit_idx;    // current data bit index
    reg [$clog2(STOP_BITS):0]   stop_cnt;   // stop bit counter
    reg                         parity_bit; // calculated parity

    // Busy flag: high whenever we are NOT in IDLE
    assign tx_busy = (state != S_IDLE);

    // =========================================================================
    // FSM — Sequential Logic (state register + datapath)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            tx_out    <= 1'b1;      // idle high
            tx_done   <= 1'b0;
            shift_reg <= {DATA_BITS{1'b0}};
            bit_idx   <= 0;
            stop_cnt  <= 0;
            parity_bit<= 1'b0;
        end else begin
            // Default: clear single-cycle pulse
            tx_done <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for tx_start
                // ---------------------------------------------------------
                S_IDLE: begin
                    tx_out <= 1'b1;             // line idles high
                    if (tx_start) begin
                        shift_reg  <= tx_data;  // latch data
                        // Compute parity across all data bits
                        parity_bit <= (PARITY_MODE == 1) ? ~(^tx_data) : (^tx_data);
                        bit_idx    <= 0;
                        stop_cnt   <= 0;
                        state      <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // START: send start bit (logic 0)
                // ---------------------------------------------------------
                S_START: begin
                    tx_out <= 1'b0;             // start bit = 0
                    if (tick) begin
                        state <= S_DATA;
                    end
                end

                // ---------------------------------------------------------
                // DATA: shift out data bits LSB-first
                // ---------------------------------------------------------
                S_DATA: begin
                    tx_out <= shift_reg[0];     // drive current LSB
                    if (tick) begin
                        shift_reg <= shift_reg >> 1;
                        if (bit_idx == DATA_BITS - 1) begin
                            // All data bits sent
                            if (PARITY_EN)
                                state <= S_PARITY;
                            else
                                state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // PARITY: send parity bit (only if PARITY_EN == 1)
                // ---------------------------------------------------------
                S_PARITY: begin
                    tx_out <= parity_bit;
                    if (tick) begin
                        state <= S_STOP;
                    end
                end

                // ---------------------------------------------------------
                // STOP: send stop bit(s) (logic 1)
                // ---------------------------------------------------------
                S_STOP: begin
                    tx_out <= 1'b1;             // stop bit = 1
                    if (tick) begin
                        if (stop_cnt == STOP_BITS - 1) begin
                            tx_done <= 1'b1;    // done pulse
                            state   <= S_IDLE;
                        end else begin
                            stop_cnt <= stop_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Default: return to IDLE (latch-safe)
                // ---------------------------------------------------------
                default: begin
                    state  <= S_IDLE;
                    tx_out <= 1'b1;
                end
            endcase
        end
    end

endmodule
