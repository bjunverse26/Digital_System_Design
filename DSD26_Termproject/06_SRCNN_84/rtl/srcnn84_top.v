`timescale 1ns / 1ps

module srcnn84_top #(
    parameter IN_ADDR_WIDTH = 17,
    parameter IN_WIDTH      = 16
) (
    input  wire                     i_clk,
    input  wire                     i_rstn,
    input  wire                     i_start,

    output wire                     o_done,
    output reg                      output_bram_wen,
    output reg  [IN_ADDR_WIDTH-1:0] output_bram_waddr,
    output reg  [IN_WIDTH-1:0]      L3_p_out
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam DATA_WIDTH       = 16;
    localparam MAC_WIDTH        = 2 * DATA_WIDTH;

    localparam IMAGE_WIDTH      = 150;
    localparam IMAGE_HEIGHT     = 150;
    localparam IMAGE_PIXELS     = IMAGE_WIDTH * IMAGE_HEIGHT;

    localparam NUM_IMAGES       = 3;
    localparam INPUT_DEPTH      = IMAGE_PIXELS * NUM_IMAGES;
    localparam INPUT_ADDR_WIDTH = $clog2(INPUT_DEPTH);
    localparam PIXEL_ADDR_WIDTH = $clog2(IMAGE_PIXELS);

    // Padded-stream coordinate widths.
    // For a 3x3 kernel, the stream has one-pixel padding on each side.
    localparam PADDED_COL_WIDTH = $clog2(IMAGE_WIDTH + 2);
    localparam PADDED_ROW_WIDTH = $clog2(IMAGE_HEIGHT + 2);

    localparam KERNEL_SIZE      = 3;

    // SRCNN channel configuration.
    // Layer 1: 1 input channel  -> 8 output channels
    // Layer 2: 8 input channels -> 4 output channels
    // Layer 3: 4 input channels -> 1 output channel
    localparam L1_OUT_CH        = 8;
    localparam L2_OUT_CH        = 4;

    // Layer 2 uses one PE per output-channel/input-channel pair.
    localparam L2_PE_COUNT      = L1_OUT_CH * L2_OUT_CH;

    //--------------------------------------------------------------------------
    // Global stream control
    //--------------------------------------------------------------------------

    // Counts final output pixels written for the current image.
    reg [PIXEL_ADDR_WIDTH-1:0] r_output_count;

    wire [1:0] r_image_idx;
    wire [PADDED_ROW_WIDTH-1:0] r_stream_row;
    wire [PADDED_COL_WIDTH-1:0] r_stream_col;

    wire w_clear;
    wire w_stage_start;
    wire w_stream_active;
    wire w_stream_real;

    // Current image is complete when the last final output pixel is written.
    wire w_image_output_done =
        output_bram_wen && (r_output_count == IMAGE_PIXELS - 1);

    // Each image occupies 150*150 = 22500 addresses.
    wire [IN_ADDR_WIDTH-1:0] w_image_base =
        (r_image_idx == 2'd0) ? 17'd0 :
        (r_image_idx == 2'd1) ? 17'd22500 : 17'd45000;

    // Convert padded-stream coordinate to input BRAM address.
    // Only valid when w_stream_real is high.
    wire [INPUT_ADDR_WIDTH-1:0] input_rd_addr =
        w_image_base + ((r_stream_row - 1'b1) * IMAGE_WIDTH) + (r_stream_col - 1'b1);

    wire signed [DATA_WIDTH-1:0] input_rd_data;

    // BRAM read latency alignment registers.
    reg r_stream_issue_valid_d;
    reg r_stream_real_d;

    // Layer 1 padded input after BRAM alignment.
    reg signed [DATA_WIDTH-1:0] r_l1_pad_data;
    reg r_l1_pad_valid;

    //--------------------------------------------------------------------------
    // Input image BRAM
    //--------------------------------------------------------------------------

    // Original input image memory.
    // Read only for real image positions; padding positions are generated as zero.
    srcnn84_simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (INPUT_DEPTH),
        .ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .INIT_FILE  ("C:/DSD26_Termproject_Materials/06_SRCNN_84/init/input_text1_2_3.txt")
    ) u_srcnn84_input_bram (
        .clk      (i_clk),
        .wr_en    (1'b0),
        .rd_en    (w_stream_real),
        .wr_addr  ({INPUT_ADDR_WIDTH{1'b0}}),
        .rd_addr  (input_rd_addr),
        .wr_din   ({DATA_WIDTH{1'b0}}),
        .rd_valid (),
        .rd_dout  (input_rd_data)
    );

    // Generates padded raster coordinates for each image.
    srcnn84_controller #(
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .NUM_IMAGES   (NUM_IMAGES)
    ) u_srcnn84_controller (
        .i_clk               (i_clk),
        .i_rstn              (i_rstn),
        .i_start             (i_start),
        .i_image_output_done (w_image_output_done),
        .o_clear             (w_clear),
        .o_stage_start       (w_stage_start),
        .o_stream_active     (w_stream_active),
        .o_stream_real       (w_stream_real),
        .o_image_idx         (r_image_idx),
        .o_stream_row        (r_stream_row),
        .o_stream_col        (r_stream_col),
        .o_done              (o_done)
    );

    //--------------------------------------------------------------------------
    // Align synchronous input BRAM data with the padded stream
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_stream_issue_valid_d <= 1'b0;
            r_stream_real_d        <= 1'b0;
            r_l1_pad_valid         <= 1'b0;
            r_l1_pad_data          <= {DATA_WIDTH{1'b0}};
        end else begin
            // Delay stream valid/real by one cycle to match BRAM read data.
            r_l1_pad_valid         <= r_stream_issue_valid_d;
            r_l1_pad_data          <= r_stream_real_d ? input_rd_data : {DATA_WIDTH{1'b0}};
            r_stream_issue_valid_d <= w_stream_active;
            r_stream_real_d        <= w_stream_real;

            if (w_clear) begin
                r_stream_issue_valid_d <= 1'b0;
                r_stream_real_d        <= 1'b0;
                r_l1_pad_valid         <= 1'b0;
                r_l1_pad_data          <= {DATA_WIDTH{1'b0}};
            end
        end
    end

    //--------------------------------------------------------------------------
    // Weight and bias ROM
    //--------------------------------------------------------------------------

    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_b1;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_b2;
    wire signed [DATA_WIDTH-1:0] w_b3;

    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w00;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w01;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w02;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w10;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w11;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w12;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w20;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w21;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] w_l1_w22;

    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w00;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w01;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w02;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w10;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w11;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w12;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w20;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w21;
    wire signed [(L2_PE_COUNT*DATA_WIDTH)-1:0] w_l2_w22;

    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w00;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w01;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w02;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w10;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w11;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w12;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w20;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w21;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] w_l3_w22;

    // Provides all layer weights and biases as flattened buses.
    srcnn84_weight_bias_rom #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE),
        .L1_OUT_CH   (L1_OUT_CH),
        .L2_OUT_CH   (L2_OUT_CH)
    ) u_srcnn84_weight_bias_rom (
        .o_b1      (w_b1),
        .o_b2      (w_b2),
        .o_b3      (w_b3),
        .o_l1_w00  (w_l1_w00),
        .o_l1_w01  (w_l1_w01),
        .o_l1_w02  (w_l1_w02),
        .o_l1_w10  (w_l1_w10),
        .o_l1_w11  (w_l1_w11),
        .o_l1_w12  (w_l1_w12),
        .o_l1_w20  (w_l1_w20),
        .o_l1_w21  (w_l1_w21),
        .o_l1_w22  (w_l1_w22),
        .o_l2_w00  (w_l2_w00),
        .o_l2_w01  (w_l2_w01),
        .o_l2_w02  (w_l2_w02),
        .o_l2_w10  (w_l2_w10),
        .o_l2_w11  (w_l2_w11),
        .o_l2_w12  (w_l2_w12),
        .o_l2_w20  (w_l2_w20),
        .o_l2_w21  (w_l2_w21),
        .o_l2_w22  (w_l2_w22),
        .o_l3_w00  (w_l3_w00),
        .o_l3_w01  (w_l3_w01),
        .o_l3_w02  (w_l3_w02),
        .o_l3_w10  (w_l3_w10),
        .o_l3_w11  (w_l3_w11),
        .o_l3_w12  (w_l3_w12),
        .o_l3_w20  (w_l3_w20),
        .o_l3_w21  (w_l3_w21),
        .o_l3_w22  (w_l3_w22)
    );

    //--------------------------------------------------------------------------
    // Layer 1: 1 input channel to 8 output channels
    //--------------------------------------------------------------------------

    wire l1_window_valid;
    wire [$clog2(IMAGE_WIDTH)-1:0] l1_window_col;

    wire signed [DATA_WIDTH-1:0] l1_w00;
    wire signed [DATA_WIDTH-1:0] l1_w01;
    wire signed [DATA_WIDTH-1:0] l1_w02;
    wire signed [DATA_WIDTH-1:0] l1_w10;
    wire signed [DATA_WIDTH-1:0] l1_w11;
    wire signed [DATA_WIDTH-1:0] l1_w12;
    wire signed [DATA_WIDTH-1:0] l1_w20;
    wire signed [DATA_WIDTH-1:0] l1_w21;
    wire signed [DATA_WIDTH-1:0] l1_w22;

    // Layer 1 line buffer directly consumes the padded original input stream.
    srcnn84_line_buffer #(
        .DATA_WIDTH   (DATA_WIDTH),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .KERNEL_SIZE  (KERNEL_SIZE)
    ) u_srcnn84_l1_line_buffer (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_clear        (w_clear),
        .i_input_valid  (r_l1_pad_valid),
        .i_input_data   (r_l1_pad_data),
        .o_window_valid (l1_window_valid),
        .o_out_col      (l1_window_col),
        .o_window_00    (l1_w00),
        .o_window_01    (l1_w01),
        .o_window_02    (l1_w02),
        .o_window_10    (l1_w10),
        .o_window_11    (l1_w11),
        .o_window_12    (l1_w12),
        .o_window_20    (l1_w20),
        .o_window_21    (l1_w21),
        .o_window_22    (l1_w22)
    );

    wire signed [MAC_WIDTH-1:0] l1_pe_data [0:L1_OUT_CH-1];
    wire [L1_OUT_CH-1:0] l1_pe_valid;
    wire signed [DATA_WIDTH-1:0] l1_post_data [0:L1_OUT_CH-1];
    wire [L1_OUT_CH-1:0] l1_post_valid;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] l1_post_flat;

    genvar l1_idx;
    generate
        // Eight parallel PEs produce eight layer-1 output channels
        // from the same input window but different kernels.
        for (l1_idx = 0; l1_idx < L1_OUT_CH; l1_idx = l1_idx + 1) begin : gen_l1_pe
            srcnn84_pe #(
                .DATA_WIDTH  (DATA_WIDTH)
            ) u_srcnn84_l1_pe (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_mac_en       (l1_window_valid),
                .i_window_00    (l1_w00),
                .i_window_01    (l1_w01),
                .i_window_02    (l1_w02),
                .i_window_10    (l1_w10),
                .i_window_11    (l1_w11),
                .i_window_12    (l1_w12),
                .i_window_20    (l1_w20),
                .i_window_21    (l1_w21),
                .i_window_22    (l1_w22),
                .i_weight_00    (w_l1_w00[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_01    (w_l1_w01[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_02    (w_l1_w02[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_10    (w_l1_w10[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_11    (w_l1_w11[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_12    (w_l1_w12[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_20    (w_l1_w20[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_21    (w_l1_w21[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_22    (w_l1_w22[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .o_output_data  (l1_pe_data[l1_idx]),
                .o_output_valid (l1_pe_valid[l1_idx])
            );

            srcnn84_post_process #(
                .DATA_WIDTH  (DATA_WIDTH),
                .FIXED_SHIFT (8)
            ) u_srcnn84_l1_post (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_valid        (l1_pe_valid[l1_idx]),
                .i_relu_en      (1'b1),
                .i_mac_data     (l1_pe_data[l1_idx]),
                .i_bias         (w_b1[(l1_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .o_output_data  (l1_post_data[l1_idx]),
                .o_output_valid (l1_post_valid[l1_idx])
            );

            assign l1_post_flat[(l1_idx*DATA_WIDTH)+:DATA_WIDTH] = l1_post_data[l1_idx];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Layer 2 padding and line buffers
    //--------------------------------------------------------------------------

    wire l2_pad_valid;
    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] l2_pad_data;

    // Layer 1 output stream is re-padded before entering layer 2.
    // All 8 layer-1 channels are packed and padded together.
    srcnn84_pad_insert #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CHANNELS     (L1_OUT_CH),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT)
    ) u_srcnn84_l2_pad_insert (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn),
        .i_clear      (w_clear),
        .i_start      (w_stage_start),
        .i_data_valid (l1_post_valid[0]),
        .i_data       (l1_post_flat),
        .o_pad_valid  (l2_pad_valid),
        .o_pad_data   (l2_pad_data),
        .o_done       ()
    );

    wire [L1_OUT_CH-1:0] l2_window_valid_ch;

    wire signed [DATA_WIDTH-1:0] l2_w00 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w01 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w02 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w10 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w11 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w12 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w20 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w21 [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_w22 [0:L1_OUT_CH-1];

    // All layer-2 line buffers receive the same valid timing.
    wire l2_window_valid = l2_window_valid_ch[0];

    genvar l2_ic;
    generate
        // One line buffer per layer-1 output channel.
        for (l2_ic = 0; l2_ic < L1_OUT_CH; l2_ic = l2_ic + 1) begin : gen_l2_line_buffer
            srcnn84_line_buffer #(
                .DATA_WIDTH   (DATA_WIDTH),
                .IMAGE_WIDTH  (IMAGE_WIDTH),
                .IMAGE_HEIGHT (IMAGE_HEIGHT),
                .KERNEL_SIZE  (KERNEL_SIZE)
            ) u_srcnn84_l2_line_buffer (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_clear        (w_clear),
                .i_input_valid  (l2_pad_valid),
                .i_input_data   (l2_pad_data[(l2_ic*DATA_WIDTH)+:DATA_WIDTH]),
                .o_window_valid (l2_window_valid_ch[l2_ic]),
                .o_out_col      (),
                .o_window_00    (l2_w00[l2_ic]),
                .o_window_01    (l2_w01[l2_ic]),
                .o_window_02    (l2_w02[l2_ic]),
                .o_window_10    (l2_w10[l2_ic]),
                .o_window_11    (l2_w11[l2_ic]),
                .o_window_12    (l2_w12[l2_ic]),
                .o_window_20    (l2_w20[l2_ic]),
                .o_window_21    (l2_w21[l2_ic]),
                .o_window_22    (l2_w22[l2_ic])
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Layer 2: 8 input channels to 4 output channels
    //--------------------------------------------------------------------------

    wire signed [MAC_WIDTH-1:0] l2_pe_data [0:L2_PE_COUNT-1];
    wire [L2_PE_COUNT-1:0] l2_pe_valid;
    wire signed [MAC_WIDTH-1:0] l2_sum [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_post_data [0:L2_OUT_CH-1];
    wire [L2_OUT_CH-1:0] l2_post_valid;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] l2_post_flat;

    genvar l2_pe_idx;
    generate
        // Layer 2 uses 32 PEs.
        // Each PE corresponds to one output-channel/input-channel pair.
        for (l2_pe_idx = 0; l2_pe_idx < L2_PE_COUNT; l2_pe_idx = l2_pe_idx + 1) begin : gen_l2_pe
            localparam integer L2_IC = l2_pe_idx % L1_OUT_CH;

            srcnn84_pe #(
                .DATA_WIDTH  (DATA_WIDTH)
            ) u_srcnn84_l2_pe (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_mac_en       (l2_window_valid),
                .i_window_00    (l2_w00[L2_IC]),
                .i_window_01    (l2_w01[L2_IC]),
                .i_window_02    (l2_w02[L2_IC]),
                .i_window_10    (l2_w10[L2_IC]),
                .i_window_11    (l2_w11[L2_IC]),
                .i_window_12    (l2_w12[L2_IC]),
                .i_window_20    (l2_w20[L2_IC]),
                .i_window_21    (l2_w21[L2_IC]),
                .i_window_22    (l2_w22[L2_IC]),
                .i_weight_00    (w_l2_w00[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_01    (w_l2_w01[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_02    (w_l2_w02[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_10    (w_l2_w10[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_11    (w_l2_w11[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_12    (w_l2_w12[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_20    (w_l2_w20[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_21    (w_l2_w21[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_22    (w_l2_w22[(l2_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .o_output_data  (l2_pe_data[l2_pe_idx]),
                .o_output_valid (l2_pe_valid[l2_pe_idx])
            );
        end
    endgenerate

    // Layer 2 channel accumulation.
    // Each output channel sums 8 input-channel PE results.
    assign l2_sum[0] =
        l2_pe_data[0] + l2_pe_data[1] + l2_pe_data[2] + l2_pe_data[3] +
        l2_pe_data[4] + l2_pe_data[5] + l2_pe_data[6] + l2_pe_data[7];

    assign l2_sum[1] =
        l2_pe_data[8] + l2_pe_data[9] + l2_pe_data[10] + l2_pe_data[11] +
        l2_pe_data[12] + l2_pe_data[13] + l2_pe_data[14] + l2_pe_data[15];

    assign l2_sum[2] =
        l2_pe_data[16] + l2_pe_data[17] + l2_pe_data[18] + l2_pe_data[19] +
        l2_pe_data[20] + l2_pe_data[21] + l2_pe_data[22] + l2_pe_data[23];

    assign l2_sum[3] =
        l2_pe_data[24] + l2_pe_data[25] + l2_pe_data[26] + l2_pe_data[27] +
        l2_pe_data[28] + l2_pe_data[29] + l2_pe_data[30] + l2_pe_data[31];

    genvar l2_oc;
    generate
        // Bias/ReLU/post-processing for each layer-2 output channel.
        for (l2_oc = 0; l2_oc < L2_OUT_CH; l2_oc = l2_oc + 1) begin : gen_l2_post
            srcnn84_post_process #(
                .DATA_WIDTH  (DATA_WIDTH),
                .FIXED_SHIFT (8)
            ) u_srcnn84_l2_post (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_valid        (l2_pe_valid[l2_oc*L1_OUT_CH]),
                .i_relu_en      (1'b1),
                .i_mac_data     (l2_sum[l2_oc]),
                .i_bias         (w_b2[(l2_oc*DATA_WIDTH)+:DATA_WIDTH]),
                .o_output_data  (l2_post_data[l2_oc]),
                .o_output_valid (l2_post_valid[l2_oc])
            );

            assign l2_post_flat[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = l2_post_data[l2_oc];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Layer 3 padding and line buffers
    //--------------------------------------------------------------------------

    wire l3_pad_valid;
    wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0] l3_pad_data;

    // Layer 2 output stream is re-padded before entering layer 3.
    // All 4 layer-2 channels are packed and padded together.
    srcnn84_pad_insert #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CHANNELS     (L2_OUT_CH),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT)
    ) u_srcnn84_l3_pad_insert (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn),
        .i_clear      (w_clear),
        .i_start      (w_stage_start),
        .i_data_valid (l2_post_valid[0]),
        .i_data       (l2_post_flat),
        .o_pad_valid  (l3_pad_valid),
        .o_pad_data   (l3_pad_data),
        .o_done       ()
    );

    wire [L2_OUT_CH-1:0] l3_window_valid_ch;

    wire signed [DATA_WIDTH-1:0] l3_w00 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w01 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w02 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w10 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w11 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w12 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w20 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w21 [0:L2_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l3_w22 [0:L2_OUT_CH-1];

    // All layer-3 line buffers receive the same valid timing.
    wire l3_window_valid = l3_window_valid_ch[0];

    genvar l3_ic;
    generate
        // One line buffer per layer-2 output channel.
        for (l3_ic = 0; l3_ic < L2_OUT_CH; l3_ic = l3_ic + 1) begin : gen_l3_line_buffer
            srcnn84_line_buffer #(
                .DATA_WIDTH   (DATA_WIDTH),
                .IMAGE_WIDTH  (IMAGE_WIDTH),
                .IMAGE_HEIGHT (IMAGE_HEIGHT),
                .KERNEL_SIZE  (KERNEL_SIZE)
            ) u_srcnn84_l3_line_buffer (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_clear        (w_clear),
                .i_input_valid  (l3_pad_valid),
                .i_input_data   (l3_pad_data[(l3_ic*DATA_WIDTH)+:DATA_WIDTH]),
                .o_window_valid (l3_window_valid_ch[l3_ic]),
                .o_out_col      (),
                .o_window_00    (l3_w00[l3_ic]),
                .o_window_01    (l3_w01[l3_ic]),
                .o_window_02    (l3_w02[l3_ic]),
                .o_window_10    (l3_w10[l3_ic]),
                .o_window_11    (l3_w11[l3_ic]),
                .o_window_12    (l3_w12[l3_ic]),
                .o_window_20    (l3_w20[l3_ic]),
                .o_window_21    (l3_w21[l3_ic]),
                .o_window_22    (l3_w22[l3_ic])
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Layer 3: 4 input channels to 1 output channel
    //--------------------------------------------------------------------------

    wire signed [MAC_WIDTH-1:0] l3_pe_data [0:L2_OUT_CH-1];
    wire [L2_OUT_CH-1:0] l3_pe_valid;

    // Final layer sums 4 input-channel PE results.
    wire signed [MAC_WIDTH-1:0] l3_sum =
        l3_pe_data[0] + l3_pe_data[1] + l3_pe_data[2] + l3_pe_data[3];

    wire signed [DATA_WIDTH-1:0] l3_post_data;
    wire l3_post_valid;

    genvar l3_pe_idx;
    generate
        // Four PEs compute convolution over the 4 layer-2 feature maps.
        for (l3_pe_idx = 0; l3_pe_idx < L2_OUT_CH; l3_pe_idx = l3_pe_idx + 1) begin : gen_l3_pe
            srcnn84_pe #(
                .DATA_WIDTH  (DATA_WIDTH)
            ) u_srcnn84_l3_pe (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_mac_en       (l3_window_valid),
                .i_window_00    (l3_w00[l3_pe_idx]),
                .i_window_01    (l3_w01[l3_pe_idx]),
                .i_window_02    (l3_w02[l3_pe_idx]),
                .i_window_10    (l3_w10[l3_pe_idx]),
                .i_window_11    (l3_w11[l3_pe_idx]),
                .i_window_12    (l3_w12[l3_pe_idx]),
                .i_window_20    (l3_w20[l3_pe_idx]),
                .i_window_21    (l3_w21[l3_pe_idx]),
                .i_window_22    (l3_w22[l3_pe_idx]),
                .i_weight_00    (w_l3_w00[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_01    (w_l3_w01[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_02    (w_l3_w02[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_10    (w_l3_w10[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_11    (w_l3_w11[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_12    (w_l3_w12[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_20    (w_l3_w20[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_21    (w_l3_w21[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .i_weight_22    (w_l3_w22[(l3_pe_idx*DATA_WIDTH)+:DATA_WIDTH]),
                .o_output_data  (l3_pe_data[l3_pe_idx]),
                .o_output_valid (l3_pe_valid[l3_pe_idx])
            );
        end
    endgenerate

    // Final layer post-processing.
    // ReLU is disabled for the final output layer.
    srcnn84_post_process #(
        .DATA_WIDTH  (DATA_WIDTH),
        .FIXED_SHIFT (8)
    ) u_srcnn84_l3_post (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_valid        (l3_pe_valid[0]),
        .i_relu_en      (1'b0),
        .i_mac_data     (l3_sum),
        .i_bias         (w_b3),
        .o_output_data  (l3_post_data),
        .o_output_valid (l3_post_valid)
    );

    //--------------------------------------------------------------------------
    // Final output writeback
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_output_count    <= {PIXEL_ADDR_WIDTH{1'b0}};
            output_bram_wen   <= 1'b0;
            output_bram_waddr <= {IN_ADDR_WIDTH{1'b0}};
            L3_p_out          <= {IN_WIDTH{1'b0}};
        end else begin
            output_bram_wen <= 1'b0;

            if (w_clear) begin
                // Start each image output from address 0 within its image region.
                r_output_count <= {PIXEL_ADDR_WIDTH{1'b0}};
            end else if (l3_post_valid) begin
                // Write only final layer output pixels to output BRAM.
                output_bram_wen   <= 1'b1;
                output_bram_waddr <= w_image_base + r_output_count;
                L3_p_out          <= l3_post_data;
                r_output_count    <= r_output_count + 1'b1;
            end
        end
    end

endmodule
