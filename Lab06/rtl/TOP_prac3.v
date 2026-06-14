//==============================================================================
// File Name   : TOP_prac3.v
// Project     : Digital System Design - Lab06
// Author      : Beomjun Kim
// Description : Channel-parallel 3x3 convolution engine.
// Notes       : - Each input/weight word packs three signed 16-bit channels.
//               - Packing order is {ch2, ch1, ch0}.
//               - Three line buffers and three PEs operate in parallel.
//               - PE results are reduced by a two-stage channel-sum tree.
//==============================================================================

`timescale 1ns / 1ps

module TOP_prac3 #(
    parameter INPUT_WIDTH   = 5,
    parameter INPUT_HEIGHT  = 5,
    parameter WEIGHT_WIDTH  = 3,
    parameter WEIGHT_HEIGHT = 3,
    parameter DATA_WIDTH    = 16,
    parameter LINE_WIDTH    = INPUT_WIDTH,
    parameter KERNEL_SIZE   = WEIGHT_HEIGHT
) (
    input  wire                             i_clk,
    input  wire                             i_rstn,

    // Asserted when all channel line buffers can start one output row.
    input  wire                             i_line_done,

    // Packed input feature-map stream: {ch2, ch1, ch0}.
    input  wire                             i_input_valid,
    input  wire signed [(3*DATA_WIDTH)-1:0] i_input_data,

    // Packed kernel stream: {ch2, ch1, ch0}, loaded in row-major order.
    input  wire                             i_weight_valid,
    input  wire signed [(3*DATA_WIDTH)-1:0] i_weight_data,

    // Channel-reduced convolution output.
    output wire                             o_output_valid,
    output wire signed [(2*DATA_WIDTH)-1:0] o_output,

    // One-cycle pulse requesting the next input line.
    output wire                             o_line_rd_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam OUTPUT_WIDTH  = INPUT_WIDTH  - WEIGHT_WIDTH  + 1;
    localparam OUTPUT_HEIGHT = INPUT_HEIGHT - WEIGHT_HEIGHT + 1;
    localparam WEIGHT_NUM    = WEIGHT_WIDTH * WEIGHT_HEIGHT;
    localparam OUTPUT_COL_WIDTH = (OUTPUT_WIDTH  > 1) ? $clog2(OUTPUT_WIDTH)  : 1;
    localparam OUTPUT_ROW_WIDTH = (OUTPUT_HEIGHT > 1) ? $clog2(OUTPUT_HEIGHT) : 1;

    //--------------------------------------------------------------------------
    // Kernel and scan-control registers
    //--------------------------------------------------------------------------

    // Kernel register file. Each entry stores {ch2, ch1, ch0}.
    reg signed [(3*DATA_WIDTH)-1:0] r_weight [0:WEIGHT_NUM-1];

    // Number of loaded packed kernel words.
    reg [3:0] r_weight_cnt;

    // Shared PE enable for all three channel PEs.
    reg       r_mac_en;

    // Horizontal 3x3 window position within the current output row.
    reg [OUTPUT_COL_WIDTH-1:0] r_line_col;

    // Current output row index.
    reg [OUTPUT_ROW_WIDTH-1:0] r_out_row;

    //--------------------------------------------------------------------------
    // Channel reduction pipeline
    //--------------------------------------------------------------------------

    // Stage 0: ch0 + ch1, and ch2 bypass.
    reg signed [(2*DATA_WIDTH)-1:0] r_tree0_data0;
    reg signed [(2*DATA_WIDTH)-1:0] r_tree0_data1;

    // Stage 1: final channel-reduced output.
    reg signed [(2*DATA_WIDTH)-1:0] r_tree1_data;

    // Valid pipeline for the two-stage channel reduction tree.
    reg r_valid_ff0;
    reg r_valid_ff1;

    //--------------------------------------------------------------------------
    // Line-buffer window wires
    //--------------------------------------------------------------------------

    wire signed [DATA_WIDTH-1:0] w_window_ch0_00;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_01;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_02;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_10;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_11;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_12;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_20;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_21;
    wire signed [DATA_WIDTH-1:0] w_window_ch0_22;

    wire signed [DATA_WIDTH-1:0] w_window_ch1_00;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_01;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_02;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_10;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_11;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_12;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_20;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_21;
    wire signed [DATA_WIDTH-1:0] w_window_ch1_22;

    wire signed [DATA_WIDTH-1:0] w_window_ch2_00;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_01;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_02;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_10;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_11;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_12;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_20;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_21;
    wire signed [DATA_WIDTH-1:0] w_window_ch2_22;

    //--------------------------------------------------------------------------
    // PE output wires
    //--------------------------------------------------------------------------

    wire signed [(2*DATA_WIDTH)-1:0] w_pe_output_ch0;
    wire signed [(2*DATA_WIDTH)-1:0] w_pe_output_ch1;
    wire signed [(2*DATA_WIDTH)-1:0] w_pe_output_ch2;

    wire                             w_pe_valid_ch0;
    wire                             w_pe_valid_ch1;
    wire                             w_pe_valid_ch2;

    //--------------------------------------------------------------------------
    // Row control wires
    //--------------------------------------------------------------------------

    wire w_last_col;
    wire w_last_row;
    wire w_line_shift;

    // End of the current output row.
    assign w_last_col = r_mac_en && (r_line_col == OUTPUT_WIDTH - 1);

    // Last output row of the full convolution result.
    assign w_last_row = (r_out_row == OUTPUT_HEIGHT - 1);

    // Shift line buffers only between output rows.
    assign w_line_shift = w_last_col && !w_last_row;

    assign o_line_rd_done = w_line_shift;

    // Channel-reduced output. Valid is delayed by the reduction tree latency.
    assign o_output_valid = r_valid_ff1;
    assign o_output       = r_tree1_data;

    integer i;

    //--------------------------------------------------------------------------
    // Kernel load and output-row scan control
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_weight_cnt <= 4'd0;
            r_mac_en     <= 1'b0;
            r_line_col   <= {OUTPUT_COL_WIDTH{1'b0}};
            r_out_row    <= {OUTPUT_ROW_WIDTH{1'b0}};

            for (i = 0; i < WEIGHT_NUM; i = i + 1) begin
                r_weight[i] <= {(3*DATA_WIDTH){1'b0}};
            end
        end else begin
            // Load packed kernel words. Additional valid pulses after
            // WEIGHT_NUM words are ignored.
            if (i_weight_valid && (r_weight_cnt < WEIGHT_NUM)) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt           <= r_weight_cnt + 1'b1;
            end

            // Start one output-row MAC burst once the line buffers are ready.
            if (!r_mac_en && i_line_done) begin
                r_mac_en   <= 1'b1;
                r_line_col <= {OUTPUT_COL_WIDTH{1'b0}};
            end

            // Advance all three channel windows in lockstep.
            else if (r_mac_en) begin
                if (r_line_col == OUTPUT_WIDTH - 1) begin
                    r_mac_en   <= 1'b0;
                    r_line_col <= {OUTPUT_COL_WIDTH{1'b0}};

                    if (r_out_row == OUTPUT_HEIGHT - 1) begin
                        r_out_row <= {OUTPUT_ROW_WIDTH{1'b0}};
                    end else begin
                        r_out_row <= r_out_row + 1'b1;
                    end
                end else begin
                    r_line_col <= r_line_col + 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Channel reduction tree
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_tree0_data0 <= {(2*DATA_WIDTH){1'b0}};
            r_tree0_data1 <= {(2*DATA_WIDTH){1'b0}};
            r_tree1_data  <= {(2*DATA_WIDTH){1'b0}};

            r_valid_ff0   <= 1'b0;
            r_valid_ff1   <= 1'b0;
        end else begin
            // Stage 0: reduce ch0 and ch1, pass ch2 forward.
            r_tree0_data0 <= w_pe_output_ch0 + w_pe_output_ch1;
            r_tree0_data1 <= w_pe_output_ch2;

            // Stage 1: final channel sum.
            r_tree1_data <= r_tree0_data0 + r_tree0_data1;

            // Valid follows the two-stage channel reduction tree.
            r_valid_ff0 <= w_pe_valid_ch0 && w_pe_valid_ch1 && w_pe_valid_ch2;
            r_valid_ff1 <= r_valid_ff0;
        end
    end

    //--------------------------------------------------------------------------
    // Channel 0 line buffer: packed bits [15:0]
    //--------------------------------------------------------------------------

    line_buffer #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LINE_WIDTH  (LINE_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer_ch0 (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn),
        .i_clear       (1'b0),

        .i_input_valid (i_input_valid),
        .i_input_data  ($signed(i_input_data[15:0])),

        .i_line_col    (r_line_col),
        .i_line_shift  (w_line_shift),

        .o_window_00   (w_window_ch0_00),
        .o_window_01   (w_window_ch0_01),
        .o_window_02   (w_window_ch0_02),
        .o_window_10   (w_window_ch0_10),
        .o_window_11   (w_window_ch0_11),
        .o_window_12   (w_window_ch0_12),
        .o_window_20   (w_window_ch0_20),
        .o_window_21   (w_window_ch0_21),
        .o_window_22   (w_window_ch0_22)
    );

    //--------------------------------------------------------------------------
    // Channel 1 line buffer: packed bits [31:16]
    //--------------------------------------------------------------------------

    line_buffer #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LINE_WIDTH  (LINE_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer_ch1 (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn),
        .i_clear       (1'b0),

        .i_input_valid (i_input_valid),
        .i_input_data  ($signed(i_input_data[31:16])),

        .i_line_col    (r_line_col),
        .i_line_shift  (w_line_shift),

        .o_window_00   (w_window_ch1_00),
        .o_window_01   (w_window_ch1_01),
        .o_window_02   (w_window_ch1_02),
        .o_window_10   (w_window_ch1_10),
        .o_window_11   (w_window_ch1_11),
        .o_window_12   (w_window_ch1_12),
        .o_window_20   (w_window_ch1_20),
        .o_window_21   (w_window_ch1_21),
        .o_window_22   (w_window_ch1_22)
    );

    //--------------------------------------------------------------------------
    // Channel 2 line buffer: packed bits [47:32]
    //--------------------------------------------------------------------------

    line_buffer #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LINE_WIDTH  (LINE_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer_ch2 (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn),
        .i_clear       (1'b0),

        .i_input_valid (i_input_valid),
        .i_input_data  ($signed(i_input_data[47:32])),

        .i_line_col    (r_line_col),
        .i_line_shift  (w_line_shift),

        .o_window_00   (w_window_ch2_00),
        .o_window_01   (w_window_ch2_01),
        .o_window_02   (w_window_ch2_02),
        .o_window_10   (w_window_ch2_10),
        .o_window_11   (w_window_ch2_11),
        .o_window_12   (w_window_ch2_12),
        .o_window_20   (w_window_ch2_20),
        .o_window_21   (w_window_ch2_21),
        .o_window_22   (w_window_ch2_22)
    );

    //--------------------------------------------------------------------------
    // Channel 0 PE: packed bits [15:0]
    //--------------------------------------------------------------------------

    pe #(
        .KERNEL_SIZE (KERNEL_SIZE),
        .DATA_WIDTH  (DATA_WIDTH)
    ) u_pe_ch0 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_mac_en       (r_mac_en),

        .i_window_00    (w_window_ch0_00),
        .i_window_01    (w_window_ch0_01),
        .i_window_02    (w_window_ch0_02),
        .i_window_10    (w_window_ch0_10),
        .i_window_11    (w_window_ch0_11),
        .i_window_12    (w_window_ch0_12),
        .i_window_20    (w_window_ch0_20),
        .i_window_21    (w_window_ch0_21),
        .i_window_22    (w_window_ch0_22),

        .i_weight_00    ($signed(r_weight[0][15:0])),
        .i_weight_01    ($signed(r_weight[1][15:0])),
        .i_weight_02    ($signed(r_weight[2][15:0])),
        .i_weight_10    ($signed(r_weight[3][15:0])),
        .i_weight_11    ($signed(r_weight[4][15:0])),
        .i_weight_12    ($signed(r_weight[5][15:0])),
        .i_weight_20    ($signed(r_weight[6][15:0])),
        .i_weight_21    ($signed(r_weight[7][15:0])),
        .i_weight_22    ($signed(r_weight[8][15:0])),

        .o_output_data  (w_pe_output_ch0),
        .o_output_valid (w_pe_valid_ch0)
    );

    //--------------------------------------------------------------------------
    // Channel 1 PE: packed bits [31:16]
    //--------------------------------------------------------------------------

    pe #(
        .KERNEL_SIZE (KERNEL_SIZE),
        .DATA_WIDTH  (DATA_WIDTH)
    ) u_pe_ch1 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_mac_en       (r_mac_en),

        .i_window_00    (w_window_ch1_00),
        .i_window_01    (w_window_ch1_01),
        .i_window_02    (w_window_ch1_02),
        .i_window_10    (w_window_ch1_10),
        .i_window_11    (w_window_ch1_11),
        .i_window_12    (w_window_ch1_12),
        .i_window_20    (w_window_ch1_20),
        .i_window_21    (w_window_ch1_21),
        .i_window_22    (w_window_ch1_22),

        .i_weight_00    ($signed(r_weight[0][31:16])),
        .i_weight_01    ($signed(r_weight[1][31:16])),
        .i_weight_02    ($signed(r_weight[2][31:16])),
        .i_weight_10    ($signed(r_weight[3][31:16])),
        .i_weight_11    ($signed(r_weight[4][31:16])),
        .i_weight_12    ($signed(r_weight[5][31:16])),
        .i_weight_20    ($signed(r_weight[6][31:16])),
        .i_weight_21    ($signed(r_weight[7][31:16])),
        .i_weight_22    ($signed(r_weight[8][31:16])),

        .o_output_data  (w_pe_output_ch1),
        .o_output_valid (w_pe_valid_ch1)
    );

    //--------------------------------------------------------------------------
    // Channel 2 PE: packed bits [47:32]
    //--------------------------------------------------------------------------

    pe #(
        .KERNEL_SIZE (KERNEL_SIZE),
        .DATA_WIDTH  (DATA_WIDTH)
    ) u_pe_ch2 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_mac_en       (r_mac_en),

        .i_window_00    (w_window_ch2_00),
        .i_window_01    (w_window_ch2_01),
        .i_window_02    (w_window_ch2_02),
        .i_window_10    (w_window_ch2_10),
        .i_window_11    (w_window_ch2_11),
        .i_window_12    (w_window_ch2_12),
        .i_window_20    (w_window_ch2_20),
        .i_window_21    (w_window_ch2_21),
        .i_window_22    (w_window_ch2_22),

        .i_weight_00    ($signed(r_weight[0][47:32])),
        .i_weight_01    ($signed(r_weight[1][47:32])),
        .i_weight_02    ($signed(r_weight[2][47:32])),
        .i_weight_10    ($signed(r_weight[3][47:32])),
        .i_weight_11    ($signed(r_weight[4][47:32])),
        .i_weight_12    ($signed(r_weight[5][47:32])),
        .i_weight_20    ($signed(r_weight[6][47:32])),
        .i_weight_21    ($signed(r_weight[7][47:32])),
        .i_weight_22    ($signed(r_weight[8][47:32])),

        .o_output_data  (w_pe_output_ch2),
        .o_output_valid (w_pe_valid_ch2)
    );

endmodule
