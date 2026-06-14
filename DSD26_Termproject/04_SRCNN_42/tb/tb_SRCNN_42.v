`timescale 1ns / 1ps

module tb_SRCNN_42;

    //--------------------------------------------------------------------------
    // USER SETTINGS
    //--------------------------------------------------------------------------

    // Mirror the 00_RTL_Skeleton block-design PL clock.
    // Vivado report_clocks shows clk_pl_0 = 10.000 ns, so this testbench uses
    // 10 ns for time-based latency/throughput conversion.
    localparam CLK_PERIOD = 10;

    // Simulation timeout. Increase this if the RTL latency becomes larger.
    localparam MAX_CYCLES = 2000000;

    // Number of detailed mismatch messages printed before suppressing repeats.
    localparam MISMATCH_PRINT_LIMIT = 20;

    // Set to 0 to check only the final SRCNN output.
    localparam CHECK_INTERNAL_LAYER = 1;

    //--------------------------------------------------------------------------
    // DO NOT MODIFY: fixed design/test data parameters
    //--------------------------------------------------------------------------

    localparam IMG_PIXELS    = 22500;
    localparam NUM_IMAGES    = 3;
    localparam TOTAL_PIXELS  = IMG_PIXELS * NUM_IMAGES;

    //--------------------------------------------------------------------------
    // DO NOT MODIFY: reference file paths
    //--------------------------------------------------------------------------

    // These files are generated from the fixed-point reference software.
    // The final output reference contains test images 1, 2, and 3.
    // Internal layer references are checked only for test image 1.

    //--------------------------------------------------------------------------
    // DUT interface
    //--------------------------------------------------------------------------

    reg         i_clk;
    reg         i_rstn;
    reg         i_start;

    wire        o_done;
    wire        output_bram_wen;
    wire [16:0] output_bram_waddr;
    wire [15:0] L3_p_out;

    //--------------------------------------------------------------------------
    // Test counters
    //--------------------------------------------------------------------------

    integer cycle_count;
    integer done_count;
    integer total_write_count;
    integer image_write_count;
    integer error_count;
    integer value_mismatch_count;
    integer layer1_mismatch_count;
    integer layer2_mismatch_count;
    integer first_done_cycle;
    integer total_latency_cycles;
    integer prev_done_cycle;
    integer steady_cycle_sum;
    integer steady_image_cycles;
    integer mismatch_count;
    integer oc;

    real clk_freq_mhz;
    real latency_us;
    real throughput_images_per_sec;

    reg [16:0] expected_waddr;
    reg [15:0] expected_output [0:TOTAL_PIXELS-1];
    reg [15:0] expected_layer1 [0:(4*IMG_PIXELS)-1];
    reg [15:0] expected_layer2 [0:(2*IMG_PIXELS)-1];

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------

    srcnn42_top #(
        .IN_ADDR_WIDTH (17),
        .IN_WIDTH      (16)
    ) dut (
        .i_clk             (i_clk),
        .i_rstn            (i_rstn),
        .i_start           (i_start),
        .o_done            (o_done),
        .output_bram_wen   (output_bram_wen),
        .output_bram_waddr (output_bram_waddr),
        .L3_p_out          (L3_p_out)
    );

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------

    initial begin
        i_clk = 1'b0;
        forever #(CLK_PERIOD/2) i_clk = ~i_clk;
    end

    //--------------------------------------------------------------------------
    // Stimulus
    //--------------------------------------------------------------------------

    initial begin
        i_rstn = 1'b0;
        i_start = 1'b0;

        cycle_count          = 0;
        done_count           = 0;
        total_write_count    = 0;
        image_write_count    = 0;
        error_count          = 0;
        value_mismatch_count = 0;
        layer1_mismatch_count = 0;
        layer2_mismatch_count = 0;
        first_done_cycle     = 0;
        total_latency_cycles = 0;
        prev_done_cycle      = 0;
        steady_cycle_sum     = 0;
        steady_image_cycles  = 0;
        mismatch_count       = 0;
        clk_freq_mhz         = 0.0;
        latency_us           = 0.0;
        throughput_images_per_sec = 0.0;
        expected_waddr       = 17'd0;

        $readmemh("C:/DSD26_Termproject_Materials/04_SRCNN_42/ref/expected_output_1_2_3.txt",
                  expected_output);
        $readmemh("C:/DSD26_Termproject_Materials/04_SRCNN_42/ref/expected_layer1_test_1.txt",
                  expected_layer1);
        $readmemh("C:/DSD26_Termproject_Materials/04_SRCNN_42/ref/expected_layer2_test_1.txt",
                  expected_layer2);

        repeat (10) @(posedge i_clk);
        i_rstn <= 1'b1;

        repeat (5) @(posedge i_clk);
        i_start <= 1'b1;
        @(posedge i_clk);
        i_start <= 1'b0;
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------

    always @(posedge i_clk) begin
        if (i_rstn) begin
            cycle_count <= cycle_count + 1;

            if (cycle_count > MAX_CYCLES) begin
                $display("[TB][FAIL] Timeout after %0d cycles", MAX_CYCLES);
                $finish;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Output checks
    //--------------------------------------------------------------------------

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            done_count           <= 0;
            total_write_count    <= 0;
            image_write_count    <= 0;
            error_count          <= 0;
            value_mismatch_count <= 0;
            layer1_mismatch_count <= 0;
            layer2_mismatch_count <= 0;
            first_done_cycle     <= 0;
            total_latency_cycles <= 0;
            prev_done_cycle      <= 0;
            steady_cycle_sum     <= 0;
            steady_image_cycles  <= 0;
            mismatch_count       <= 0;
            expected_waddr       <= 17'd0;
        end else begin
            if (CHECK_INTERNAL_LAYER && (dut.r_image_idx == 0) && (dut.r_layer == 0)) begin
                for (oc = 0; oc < 4; oc = oc + 1) begin
                    if (dut.l1_wr_en[oc]) begin
                        if (dut.post_l1_data[oc] !== expected_layer1[(oc*IMG_PIXELS)+dut.r_write_addr]) begin
                            if (layer1_mismatch_count < MISMATCH_PRINT_LIMIT) begin
                                $display("[TB][ERROR] Layer1 mismatch ch=%0d addr=%0d: expected %h, got %h",
                                         oc, dut.r_write_addr,
                                         expected_layer1[(oc*IMG_PIXELS)+dut.r_write_addr],
                                         dut.post_l1_data[oc]);
                            end

                            layer1_mismatch_count = layer1_mismatch_count + 1;
                        end
                    end
                end
            end

            if (CHECK_INTERNAL_LAYER && (dut.r_image_idx == 0) && (dut.r_layer == 1)) begin
                for (oc = 0; oc < 2; oc = oc + 1) begin
                    if (dut.l2_wr_en[oc]) begin
                        if (dut.post_l2_data[oc] !== expected_layer2[(oc*IMG_PIXELS)+dut.r_write_addr]) begin
                            if (layer2_mismatch_count < MISMATCH_PRINT_LIMIT) begin
                                $display("[TB][ERROR] Layer2 mismatch ch=%0d addr=%0d: expected %h, got %h",
                                         oc, dut.r_write_addr,
                                         expected_layer2[(oc*IMG_PIXELS)+dut.r_write_addr],
                                         dut.post_l2_data[oc]);
                            end

                            layer2_mismatch_count = layer2_mismatch_count + 1;
                        end
                    end
                end
            end

            if (output_bram_wen) begin
                if (output_bram_waddr !== expected_waddr) begin
                    $display("[TB][ERROR] Output address mismatch: expected %0d, got %0d",
                             expected_waddr, output_bram_waddr);
                    error_count = error_count + 1;
                end

                if (L3_p_out !== expected_output[expected_waddr]) begin
                    if (value_mismatch_count < MISMATCH_PRINT_LIMIT) begin
                        $display("[TB][ERROR] Output value mismatch at addr %0d: expected %h, got %h",
                                 expected_waddr, expected_output[expected_waddr], L3_p_out);
                    end

                    value_mismatch_count = value_mismatch_count + 1;
                    error_count = error_count + 1;
                end

                expected_waddr    = expected_waddr + 1'b1;
                total_write_count = total_write_count + 1;
                image_write_count = image_write_count + 1;
            end

            if (o_done) begin
                if (done_count == 0) begin
                    first_done_cycle = cycle_count;
                end else begin
                    steady_cycle_sum = steady_cycle_sum + (cycle_count - prev_done_cycle);
                end

                prev_done_cycle = cycle_count;

                if (image_write_count != IMG_PIXELS) begin
                    $display("[TB][ERROR] Image write count mismatch: expected %0d, got %0d",
                             IMG_PIXELS, image_write_count);
                    error_count = error_count + 1;
                end

                if (done_count == NUM_IMAGES - 1) begin
                    total_latency_cycles = cycle_count;

                    if (total_write_count != TOTAL_PIXELS) begin
                        $display("[TB][ERROR] Total write count mismatch: expected %0d, got %0d",
                                 TOTAL_PIXELS, total_write_count);
                        error_count = error_count + 1;
                    end

                    // Evaluation metrics:
                    // - latency_cycles: start to final completed image.
                    // - first_done_cycle: start to first completed image.
                    // - throughput_cycles_per_image: average done-to-done interval
                    //   between consecutive images after the first image.
                    // - time values are derived from the project PL clock period.
                    steady_image_cycles = steady_cycle_sum / (NUM_IMAGES - 1);
                    mismatch_count = value_mismatch_count +
                                     layer1_mismatch_count +
                                     layer2_mismatch_count;
                    clk_freq_mhz = 1000.0 / CLK_PERIOD;
                    latency_us = total_latency_cycles * CLK_PERIOD / 1000.0;
                    throughput_images_per_sec =
                        1000000000.0 / (steady_image_cycles * CLK_PERIOD);

                    $display("[TB]");
                    $display("[TB]============================================================");
                    $display("[TB] SRCNN_42 TESTBENCH SUMMARY");
                    $display("[TB]============================================================");

                    if (error_count == 0) begin
                        $display("[TB][PASS] Result      : reference comparison completed");
                    end else begin
                        $display("[TB][FAIL] Result      : %0d errors, %0d output mismatches",
                                 error_count, value_mismatch_count);
                    end

                    $display("[TB] Clock             : %0d ns (%0.4f MHz)",
                             CLK_PERIOD, clk_freq_mhz);
                    $display("[TB] Latency           : %0d cycles, %0.4f us",
                             total_latency_cycles, latency_us);
                    $display("[TB] First image done  : %0d cycles",
                             first_done_cycle);
                    $display("[TB] Check             : writes=%0d, mismatches=%0d",
                             total_write_count, mismatch_count);
                    $display("[TB]============================================================");

                    repeat (10) @(posedge i_clk);
                    $finish;
                end

                done_count = done_count + 1;
                image_write_count = 0;
            end
        end
    end

endmodule
