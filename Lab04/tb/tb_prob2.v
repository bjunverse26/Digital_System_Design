`timescale 1ns / 1ps

module tb_prob2();

    parameter INPUT_WIDTH       = 128;
    parameter WEIGHT_WIDTH      = 128;
    parameter OUTPUT_WIDTH      = 48;
    parameter INPUT_DEPTH       = 4096;
    parameter WEIGHT_DEPTH      = 4096;
    parameter OUTPUT_DEPTH      = 4096;
    parameter INPUT_ADDR_WIDTH  = $clog2(INPUT_DEPTH);
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_DEPTH);
    parameter OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_DEPTH);

    reg                          clk;
    reg                          rstn;

    reg                          input_wr_en;
    reg  [INPUT_ADDR_WIDTH-1:0]  input_wr_addr;
    reg  [INPUT_WIDTH-1:0]       input_wr_din;
    reg                          input_rd_en;
    reg  [INPUT_ADDR_WIDTH-1:0]  input_rd_addr;

    reg                          weight_wr_en;
    reg  [WEIGHT_ADDR_WIDTH-1:0] weight_wr_addr;
    reg  [WEIGHT_WIDTH-1:0]      weight_wr_din;
    reg                          weight_rd_en;
    reg  [WEIGHT_ADDR_WIDTH-1:0] weight_rd_addr;

    reg                          mac_enable;

    reg                          output_wr_en;
    reg  [OUTPUT_ADDR_WIDTH-1:0] output_wr_addr;

    reg                          output_rd_en;
    reg  [OUTPUT_ADDR_WIDTH-1:0] output_rd_addr;
    wire                         output_rd_valid;
    wire [OUTPUT_WIDTH-1:0]      output_rd_dout;

    // DUT
    uram_based_gemv #(
        .INPUT_WIDTH      (INPUT_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .OUTPUT_WIDTH     (OUTPUT_WIDTH),
        .INPUT_DEPTH      (INPUT_DEPTH),
        .WEIGHT_DEPTH     (WEIGHT_DEPTH),
        .OUTPUT_DEPTH     (OUTPUT_DEPTH),
        .INPUT_ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) dut (
        .i_clk            (clk),
        .i_rstn           (rstn),
        .i_input_wr_en    (input_wr_en),
        .i_input_wr_addr  (input_wr_addr),
        .i_input_wr_din   (input_wr_din),
        .i_input_rd_en    (input_rd_en),
        .i_input_rd_addr  (input_rd_addr),
        .i_weight_wr_en   (weight_wr_en),
        .i_weight_wr_addr (weight_wr_addr),
        .i_weight_wr_din  (weight_wr_din),
        .i_weight_rd_en   (weight_rd_en),
        .i_weight_rd_addr (weight_rd_addr),
        .i_mac_enable     (mac_enable),
        .i_output_wr_en   (output_wr_en),
        .i_output_wr_addr (output_wr_addr),
        .i_output_rd_en   (output_rd_en),
        .i_output_rd_addr (output_rd_addr),
        .o_output_rd_valid(output_rd_valid),
        .o_output_rd_dout (output_rd_dout)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rstn           = 1'b0;
        input_wr_en    = 1'b0;
        input_wr_addr  = 1'b0;
        input_wr_din   = 1'b0;
        input_rd_en    = 1'b0;
        input_rd_addr  = 1'b0;
        weight_wr_en   = 1'b0;
        weight_wr_addr = 1'b0;
        weight_wr_din  = 1'b0;
        weight_rd_en   = 1'b0;
        weight_rd_addr = 1'b0;
        mac_enable     = 1'b0;
        output_wr_en   = 1'b0;
        output_wr_addr = 1'b0;
        output_rd_en   = 1'b0;
        output_rd_addr = 1'b0;

        repeat (3) @(posedge clk);
        rstn <= 1'b1;
        @(posedge clk);

        // 4x8 matrix A
        // row0 = [1, 2, 3, 4, 5, 6, 7, 8]
        // row1 = [2, 2, 2, 2, 2, 2, 2, 2]
        // row2 = [1, 0, 1, 0, 1, 0, 1, 0]
        // row3 = [8, 7, 6, 5, 4, 3, 2, 1]
        // 8x1 vector x
        // x = [1, 2, 3, 4, 1, 2, 3, 4]
        // expected y = A * x
        // y0 = 100
        // y1 = 40
        // y2 = 8
        // y3 = 80
        @(posedge clk);
        input_wr_en    <= 1'b1;
        input_wr_addr  <= 0;
        input_wr_din   <= 128'h0008_0007_0006_0005_0004_0003_0002_0001;
        weight_wr_en   <= 1'b1;
        weight_wr_addr <= 0;
        weight_wr_din  <= 128'h0004_0003_0002_0001_0004_0003_0002_0001;

        @(posedge clk);
        input_wr_addr  <= 1;
        input_wr_din   <= 128'h0002_0002_0002_0002_0002_0002_0002_0002;
        weight_wr_en   <= 1'b0;
        weight_wr_addr <= 1'b0;
        weight_wr_din  <= 1'b0;

        @(posedge clk);
        input_wr_addr <= 2;
        input_wr_din  <= 128'h0000_0001_0000_0001_0000_0001_0000_0001;

        @(posedge clk);
        input_wr_addr <= 3;
        input_wr_din  <= 128'h0001_0002_0003_0004_0005_0006_0007_0008;

        @(posedge clk);
        input_wr_en   <= 1'b0;
        input_wr_addr <= 1'b0;
        input_wr_din  <= 1'b0;

        // input read -> MAC -> 3-stage pipelined adder tree -> output write
        @(posedge clk);
        input_rd_en    <= 1'b1;
        weight_rd_en   <= 1'b1;
        input_rd_addr  <= 0;
        weight_rd_addr <= 0;
        mac_enable     <= 1'b1;
        output_wr_en   <= 1'b0;
        output_wr_addr <= 1'b0;

        @(posedge clk);
        input_rd_addr  <= 1;
        weight_rd_addr <= 0;
        mac_enable     <= 1'b1;
        output_wr_en   <= 1'b0;

        @(posedge clk);
        input_rd_addr  <= 2;
        weight_rd_addr <= 0;
        mac_enable     <= 1'b1;
        output_wr_en   <= 1'b0;
        output_wr_addr <= 0;

        @(posedge clk);
        input_rd_addr  <= 3;
        weight_rd_addr <= 0;
        mac_enable     <= 1'b1;
        output_wr_en   <= 1'b0;
        output_wr_addr <= 0;

        @(posedge clk);
        input_rd_en    <= 1'b0;
        weight_rd_en   <= 1'b0;
        input_rd_addr  <= 1'b0;
        weight_rd_addr <= 1'b0;
        mac_enable     <= 1'b1;
        output_wr_en   <= 1'b0;
        output_wr_addr <= 1'b0;

        @(posedge clk);
        mac_enable     <= 1'b0;
        output_wr_en   <= 1'b1;
        output_wr_addr <= 0;

        @(posedge clk);
        output_wr_en   <= 1'b1;
        output_wr_addr <= 1;

        @(posedge clk);
        output_wr_en   <= 1'b1;
        output_wr_addr <= 2;

        @(posedge clk);
        output_wr_en   <= 1'b1;
        output_wr_addr <= 3;

        @(posedge clk);
        output_wr_en   <= 1'b0;
        output_wr_addr <= 0;

        @(posedge clk);
        output_rd_en   <= 1'b1;
        output_rd_addr <= 0;

        @(posedge clk);
        output_rd_addr <= 1;

        @(posedge clk);
        output_rd_addr <= 2;

        @(posedge clk);
        output_rd_addr <= 3;

        @(posedge clk);
        output_rd_en   <= 1'b0;
        output_rd_addr <= 1'b0;

        repeat (2) @(posedge clk);
        $finish;
    end
endmodule
