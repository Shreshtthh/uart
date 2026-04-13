//==============================================================================
// Module:      uart_rx
// Description: Parameterized UART Receiver with 16× oversampling.
//              Features:
//                - Two-flip-flop synchronizer for metastability prevention
//                - Mid-bit sampling with 3-sample majority voting
//                - Configurable parity checking (even/odd/none)
//                - Framing error detection (bad stop bit)
//                - Break condition detection (rx_in held low > 1 frame)
//
// Parameters:  DATA_BITS   — number of data bits (default 8)
//              STOP_BITS   — 1 or 2 stop bits (default 1)
//              PARITY_EN   — 0 = no parity, 1 = parity enabled (default 0)
//              PARITY_MODE — 0 = even parity, 1 = odd parity (default 0)
//
// Author:      Shreshth
// Date:        2026-04-13
//==============================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_EN   = 0,
    parameter PARITY_MODE = 0    // 0 = even, 1 = odd
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  tick_16x,   // 16× oversampled baud tick
    input  wire                  rx_in,      // serial input line
    output reg  [DATA_BITS-1:0]  rx_data,    // received parallel data
    output reg                   rx_valid,   // single-cycle pulse: data ready
    output reg                   rx_error,   // framing or parity error
    output reg                   rx_break    // break condition detected
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0] S_IDLE      = 3'd0,
                     S_START_DET = 3'd1,
                     S_DATA      = 3'd2,
                     S_PARITY    = 3'd3,
                     S_STOP      = 3'd4;

    reg [2:0] state;

    // =========================================================================
    // Two-flip-flop synchronizer for rx_in (metastability guard)
    // =========================================================================
    reg rx_sync_0, rx_sync_1;
    wire rx_in_sync = rx_sync_1;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx_in;
            rx_sync_1 <= rx_sync_0;
        end
    end

    // =========================================================================
    // Internal registers
    // =========================================================================
    reg [3:0]                   tick_cnt;    // 0–15 counter within each bit
    reg [$clog2(DATA_BITS)-1:0] bit_idx;     // current data bit index
    reg [DATA_BITS-1:0]         shift_reg;   // incoming data shift register
    reg                         parity_calc; // running parity calculation
    reg [$clog2(STOP_BITS):0]   stop_cnt;    // stop bit counter

    // Majority voting: sample at ticks 7, 8, 9 and take 2-of-3
    reg [1:0] vote_sum;
    wire      vote_result = (vote_sum >= 2'd2) ? 1'b1 : 1'b0;

    // Break detection counter
    localparam FRAME_TICKS = (1 + DATA_BITS + PARITY_EN + STOP_BITS) * 16;
    localparam BREAK_CNT_W = $clog2(FRAME_TICKS + 1);
    reg [BREAK_CNT_W-1:0] break_cnt;

    // =========================================================================
    // Break detection (runs continuously, independent of FSM)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            break_cnt <= 0;
            rx_break  <= 1'b0;
        end else if (tick_16x) begin
            if (rx_in_sync == 1'b0) begin
                if (break_cnt < FRAME_TICKS) begin
                    break_cnt <= break_cnt + 1;
                    rx_break  <= 1'b0;
                end else begin
                    rx_break <= 1'b1;
                end
            end else begin
                break_cnt <= 0;
                rx_break  <= 1'b0;
            end
        end
    end

    // =========================================================================
    // FSM — Sequential Logic
    //
    // Strategy: count 16 tick_16x pulses per bit.
    //   - Sample at ticks 7, 8, 9 (near mid-bit) for majority voting.
    //   - Act on tick 15 (end of bit window): use vote result, advance state.
    //   - START_DET: also uses 0–15 count; checks mid-bit to confirm start.
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            rx_data     <= {DATA_BITS{1'b0}};
            rx_valid    <= 1'b0;
            rx_error    <= 1'b0;
            tick_cnt    <= 4'd0;
            bit_idx     <= 0;
            shift_reg   <= {DATA_BITS{1'b0}};
            parity_calc <= 1'b0;
            stop_cnt    <= 0;
            vote_sum    <= 2'd0;
        end else begin
            // Default: clear single-cycle pulses
            rx_valid <= 1'b0;
            rx_error <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for line to go low (start bit begins)
                // ---------------------------------------------------------
                S_IDLE: begin
                    tick_cnt <= 4'd0;
                    bit_idx  <= 0;
                    stop_cnt <= 0;
                    vote_sum <= 2'd0;
                    if (rx_in_sync == 1'b0) begin
                        state    <= S_START_DET;
                        tick_cnt <= 4'd0; // start counting ticks for the start bit
                    end
                end

                // ---------------------------------------------------------
                // START_DET: count to mid-bit and confirm start is still low
                // Then wait until tick 15 to boundary-align and move to data.
                // ---------------------------------------------------------
                S_START_DET: begin
                    if (tick_16x) begin
                        if (tick_cnt == 4'd7) begin
                            // Mid-bit sample of start bit
                            if (rx_in_sync == 1'b0) begin
                                // Valid start bit — continue counting to boundary
                                tick_cnt <= tick_cnt + 1;
                            end else begin
                                // False start — back to idle
                                state <= S_IDLE;
                            end
                        end else if (tick_cnt == 4'd15) begin
                            // Reached the end of the start bit period. Next is D0.
                            tick_cnt    <= 4'd0;
                            parity_calc <= 1'b0;
                            state       <= S_DATA;
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // DATA: sample each data bit using majority voting
                //   UART sends LSB first, so we shift right:
                //   {new_bit, shift_reg[7:1]} puts new_bit at MSB,
                //   after 8 bits the first-received bit (LSB) ends up at [0].
                // ---------------------------------------------------------
                S_DATA: begin
                    if (tick_16x) begin
                        // Accumulate majority vote at ticks 7, 8, 9
                        case (tick_cnt)
                            4'd7: vote_sum <= {1'b0, rx_in_sync};
                            4'd8: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            4'd9: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            default: ;
                        endcase

                        if (tick_cnt == 4'd15) begin
                            // Shift in the voted bit (MSB ← new bit, LSB falls into place)
                            shift_reg   <= {vote_result, shift_reg[DATA_BITS-1:1]};
                            parity_calc <= parity_calc ^ vote_result;
                            tick_cnt    <= 4'd0;
                            vote_sum    <= 2'd0;

                            if (bit_idx == DATA_BITS - 1) begin
                                if (PARITY_EN)
                                    state <= S_PARITY;
                                else
                                    state <= S_STOP;
                            end else begin
                                bit_idx <= bit_idx + 1;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // PARITY: sample and check parity bit
                // ---------------------------------------------------------
                S_PARITY: begin
                    if (tick_16x) begin
                        case (tick_cnt)
                            4'd7: vote_sum <= {1'b0, rx_in_sync};
                            4'd8: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            4'd9: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            default: ;
                        endcase

                        if (tick_cnt == 4'd15) begin
                            if (PARITY_MODE == 0) begin
                                if (parity_calc ^ vote_result)
                                    rx_error <= 1'b1;
                            end else begin
                                if (!(parity_calc ^ vote_result))
                                    rx_error <= 1'b1;
                            end
                            tick_cnt <= 4'd0;
                            vote_sum <= 2'd0;
                            state    <= S_STOP;
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // STOP: verify stop bit(s) are high
                // ---------------------------------------------------------
                S_STOP: begin
                    if (tick_16x) begin
                        case (tick_cnt)
                            4'd7: vote_sum <= {1'b0, rx_in_sync};
                            4'd8: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            4'd9: vote_sum <= vote_sum + {1'b0, rx_in_sync};
                            default: ;
                        endcase

                        if (tick_cnt == 4'd15) begin
                            if (vote_result == 1'b0)
                                rx_error <= 1'b1; // framing error: stop bit not high

                            if (stop_cnt == STOP_BITS - 1) begin
                                rx_data  <= shift_reg;
                                rx_valid <= 1'b1;
                                state    <= S_IDLE;
                            end else begin
                                stop_cnt <= stop_cnt + 1;
                                tick_cnt <= 4'd0;
                                vote_sum <= 2'd0;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
