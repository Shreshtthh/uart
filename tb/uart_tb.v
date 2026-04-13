//==============================================================================
// Testbench: uart_tb
// Description: Self-checking loopback testbench for the UART.
//              - Connects TX output directly to RX input (loopback)
//              - Sends multiple test vectors and automatically verifies
//                that RX output matches the transmitted data
//              - Tests: boundary values, random data, back-to-back TX,
//                       framing error injection, break detection
//              - Generates VCD waveform file for GTKWave
//
// Author:      Shreshth
// Date:        2026-04-13
//==============================================================================

`timescale 1ns / 1ps

module uart_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_FREQ    = 29_491_200;  // 29.4912 MHz (standard UART crystal)
    localparam BAUD_RATE   = 115_200;     // 256 clks/bit, 16 clks/sample — exact
    localparam DATA_BITS   = 8;
    localparam STOP_BITS   = 1;
    localparam PARITY_EN   = 0;
    localparam PARITY_MODE = 0;

    // Derived timing
    localparam CLK_PERIOD  = 1_000_000_000 / CLK_FREQ;           // 100 ns
    localparam TICKS_PER_BIT = CLK_FREQ / BAUD_RATE;             // ~86
    localparam FRAME_CLKS  = TICKS_PER_BIT * (1 + DATA_BITS + PARITY_EN + STOP_BITS);
    localparam TIMEOUT_CLKS = FRAME_CLKS * 4;                    // generous timeout

    // =========================================================================
    // Signals
    // =========================================================================
    reg                  clk;
    reg                  rst_n;
    reg                  tx_start;
    reg  [DATA_BITS-1:0] tx_data;

    wire                 tx_out;
    wire                 tx_busy;
    wire                 tx_done;
    wire [DATA_BITS-1:0] rx_data;
    wire                 rx_valid;
    wire                 rx_error;
    wire                 rx_break;

    // Loopback wire with error injection capability
    reg                  loopback_override;
    reg                  loopback_force_val;
    wire                 rx_in_wire = loopback_override ? loopback_force_val : tx_out;

    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    uart_top #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .DATA_BITS   (DATA_BITS),
        .STOP_BITS   (STOP_BITS),
        .PARITY_EN   (PARITY_EN),
        .PARITY_MODE (PARITY_MODE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_out   (tx_out),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .rx_in    (rx_in_wire),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .rx_error (rx_error),
        .rx_break (rx_break)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end

    // =========================================================================
    // Task: send_and_check
    //   Sends a byte via TX, then waits for RX to produce rx_valid and
    //   compares received data. Fully self-contained (no fork needed).
    // =========================================================================
    task send_and_check;
        input [DATA_BITS-1:0] data;
        integer timeout;
        begin
            test_count = test_count + 1;

            // Pulse tx_start
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Wait for rx_valid with timeout
            timeout = 0;
            while (!rx_valid && timeout < TIMEOUT_CLKS) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (!rx_valid) begin
                $display("[FAIL] Test %0d: TIMEOUT waiting for rx_valid (expected 0x%02h)",
                         test_count, data);
                fail_count = fail_count + 1;
                // Wait for TX to finish to avoid corrupting next test
                wait (!tx_busy);
            end else if (rx_data !== data) begin
                $display("[FAIL] Test %0d: Expected 0x%02h, Got 0x%02h",
                         test_count, data, rx_data);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] Test %0d: Data 0x%02h received correctly",
                         test_count, data);
                pass_count = pass_count + 1;
            end

            // Add realistic inter-frame gap to allow RX to fully settle
            repeat (TICKS_PER_BIT * 2) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    reg [DATA_BITS-1:0] random_data;
    integer i;

    initial begin
        // Initialise
        rst_n              = 1'b0;
        tx_start           = 1'b0;
        tx_data            = {DATA_BITS{1'b0}};
        loopback_override  = 1'b0;
        loopback_force_val = 1'b1;
        test_count         = 0;
        pass_count         = 0;
        fail_count         = 0;

        $display("==============================================================");
        $display("  UART Self-Checking Loopback Testbench");
        $display("  CLK_FREQ = %0d Hz, BAUD_RATE = %0d", CLK_FREQ, BAUD_RATE);
        $display("  DATA_BITS = %0d, STOP_BITS = %0d, PARITY_EN = %0d",
                 DATA_BITS, STOP_BITS, PARITY_EN);
        $display("==============================================================");

        // Reset
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ----- Boundary Values -----
        $display("\n--- Test: Boundary Values ---");
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'h55);
        send_and_check(8'hAA);

        // ----- Walking Ones -----
        $display("\n--- Test: Walking Ones ---");
        for (i = 0; i < DATA_BITS; i = i + 1) begin
            send_and_check(1 << i);
        end

        // ----- Random Data -----
        $display("\n--- Test: 10 Random Bytes ---");
        for (i = 0; i < 10; i = i + 1) begin
            random_data = $random;
            send_and_check(random_data);
        end

        // ----- Back-to-back -----
        $display("\n--- Test: Back-to-Back Transmissions ---");
        send_and_check(8'hDE);
        send_and_check(8'hAD);
        send_and_check(8'hBE);
        send_and_check(8'hEF);

        // ----- Framing Error Injection -----
        $display("\n--- Test: Framing Error Injection ---");
        begin
            test_count = test_count + 1;
            // Start a normal transmission
            @(posedge clk);
            tx_data  <= 8'h42;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Wait for start bit to actually begin on the wire
            @(negedge tx_out);

            // Wait until just before the stop bit region (approx 9 bit periods)
            repeat (9 * TICKS_PER_BIT - 20) @(posedge clk);

            // Fork so we can hold the line low while simultaneously waiting for rx_valid
            fork
                begin
                    // Force stop bit low → framing error. Hold it low a bit longer
                    loopback_override  = 1'b1;
                    loopback_force_val = 1'b0;
                    repeat (TICKS_PER_BIT + 40) @(posedge clk);
                    loopback_override  = 1'b0;
                end
                begin
                    // Wait for the rx_valid strobe to sample the error flag
                    @(posedge rx_valid);
                    
                    if (rx_error) begin
                        $display("[PASS] Test %0d: Framing error correctly detected", test_count);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] Test %0d: Framing error NOT detected", test_count);
                        fail_count = fail_count + 1;
                    end
                end
            join
            
            // Let things settle
            repeat (FRAME_CLKS) @(posedge clk);
        end

        // ----- Break Detection -----
        $display("\n--- Test: Break Condition Detection ---");
        begin
            test_count = test_count + 1;
            loopback_override  = 1'b1;
            loopback_force_val = 1'b0;   // hold line low

            // Wait longer than 1 full frame
            repeat (FRAME_CLKS * 3) @(posedge clk);

            if (rx_break) begin
                $display("[PASS] Test %0d: Break condition correctly detected", test_count);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: Break condition NOT detected", test_count);
                fail_count = fail_count + 1;
            end
            loopback_override = 1'b0;
            repeat (100) @(posedge clk);
        end

        // =================================================================
        // Final Report
        // =================================================================
        $display("\n==============================================================");
        $display("  FINAL RESULTS");
        $display("==============================================================");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("==============================================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d TEST(S) FAILED <<<", fail_count);

        $display("==============================================================\n");
        $finish;
    end

    // =========================================================================
    // Global timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * FRAME_CLKS * 200);
        $display("[ERROR] Global simulation timeout reached!");
        $finish;
    end

endmodule
