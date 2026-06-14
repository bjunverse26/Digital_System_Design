`timescale 1ns / 1ps

module srcnn42_top #(
    parameter IN_ADDR_WIDTH = 17,
    parameter IN_WIDTH      = 16
) (
    input  wire                     i_clk,
    input  wire                     i_rstn,
    input  wire                     i_start,

    output reg                      o_done,
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
    localparam WORDS_PER_ROW    = IMAGE_WIDTH / 2;
    localparam IMAGE_WORDS      = IMAGE_HEIGHT * WORDS_PER_ROW;

    localparam NUM_IMAGES       = 3;
    localparam INPUT_DEPTH      = IMAGE_PIXELS * NUM_IMAGES;
    localparam INPUT_ADDR_WIDTH = $clog2(INPUT_DEPTH);
    localparam PIXEL_ADDR_WIDTH = $clog2(IMAGE_PIXELS);
    localparam WORD_ADDR_WIDTH  = $clog2(IMAGE_WORDS);

    localparam KERNEL_SIZE      = 3;

    // SRCNN channel configuration.
    // Layer 1: 1 input channel  -> 4 output channels
    // Layer 2: 4 input channels -> 2 output channels
    // Layer 3: 2 input channels -> 1 output channel
    localparam L1_OUT_CH        = 4;
    localparam L2_OUT_CH        = 2;

    // Maximum number of feature-map banks needed at any layer.
    localparam MAX_BANKS        = 4;

    // Two PE groups process two adjacent output columns in layer 1/2.
    // Layer 3 still uses one group because the final output port writes
    // one pixel per cycle.
    localparam PE_GROUPS        = 2;
    localparam BASE_PE_COUNT    = L2_OUT_CH * L1_OUT_CH;
    localparam PE_COUNT         = PE_GROUPS * BASE_PE_COUNT;
    localparam POST_COUNT       = PE_GROUPS * L1_OUT_CH;

    // Each activation word stores two horizontal pixels per channel.
    localparam ACT_PAIR_WIDTH   = 2 * DATA_WIDTH;
    localparam ACT_WIDTH        = L1_OUT_CH * ACT_PAIR_WIDTH;

    localparam LAYER_1          = 2'd0;
    localparam LAYER_2          = 2'd1;
    localparam LAYER_3          = 2'd2;

    //--------------------------------------------------------------------------
    // Global schedule from recursive controller
    //--------------------------------------------------------------------------

    wire [1:0] r_image_idx;
    wire [1:0] r_layer;

    // Write address for intermediate feature maps and final output.
    // Layer 1/2 advance by two pixels, while layer 3 advances by one pixel.
    reg [PIXEL_ADDR_WIDTH-1:0] r_write_addr;

    wire [IN_ADDR_WIDTH-1:0] w_image_base;

    // Each image occupies 150*150 = 22500 addresses.
    assign w_image_base = (r_image_idx == 2'd0) ? 17'd0 :
                          (r_image_idx == 2'd1) ? 17'd22500 : 17'd45000;

    //--------------------------------------------------------------------------
    // Recursive controller
    //--------------------------------------------------------------------------

    wire ctrl_input_rd_en;
    wire [PIXEL_ADDR_WIDTH-1:0] ctrl_input_rd_addr;
    wire ctrl_line_clear;
    wire ctrl_line_input_valid;
    wire ctrl_line_input_zero;
    wire [$clog2(IMAGE_WIDTH + KERNEL_SIZE)-1:0] ctrl_line_input_col;
    wire ctrl_line_shift;
    wire ctrl_mac_en;
    wire ctrl_window_shift;
    wire ctrl_done;
    wire ctrl_layer_start;

    // Controller generates the global layer/image schedule,
    // padded input read sequence, line-buffer control, and MAC enable.
    srcnn42_controller #(
        .IMAGE_WIDTH       (IMAGE_WIDTH),
        .IMAGE_HEIGHT      (IMAGE_HEIGHT),
        .KERNEL_SIZE       (KERNEL_SIZE),
        .NUM_IMAGES        (NUM_IMAGES),
        .INPUT_ADDR_WIDTH  (PIXEL_ADDR_WIDTH),
        .DRAIN_CYCLES      (3)
    ) u_srcnn42_controller (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        .i_start            (i_start),
        .o_layer            (r_layer),
        .o_image_idx        (r_image_idx),
        .o_layer_start      (ctrl_layer_start),
        .o_input_rd_en      (ctrl_input_rd_en),
        .o_input_rd_addr    (ctrl_input_rd_addr),
        .o_line_clear       (ctrl_line_clear),
        .o_line_input_valid (ctrl_line_input_valid),
        .o_line_input_zero  (ctrl_line_input_zero),
        .o_line_input_col   (ctrl_line_input_col),
        .o_line_shift       (ctrl_line_shift),
        .o_mac_en           (ctrl_mac_en),
        .o_window_shift     (ctrl_window_shift),
        .o_done             (ctrl_done)
    );

    //--------------------------------------------------------------------------
    // Input and feature-map buffers
    //--------------------------------------------------------------------------

    wire input_rd_en;
    wire [INPUT_ADDR_WIDTH-1:0] input_rd_addr;
    wire signed [DATA_WIDTH-1:0] input_rd_data;

    // Original input BRAM is used only during layer 1.
    assign input_rd_en   = ctrl_input_rd_en && (r_layer == LAYER_1);
    assign input_rd_addr = w_image_base + ctrl_input_rd_addr;

    srcnn42_simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (INPUT_DEPTH),
        .ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .INIT_FILE  ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/input_text1_2_3.txt")
    ) u_srcnn42_input_bram (
        .clk      (i_clk),
        .wr_en    (1'b0),
        .rd_en    (input_rd_en),
        .wr_addr  ({INPUT_ADDR_WIDTH{1'b0}}),
        .rd_addr  (input_rd_addr),
        .wr_din   ({DATA_WIDTH{1'b0}}),
        .rd_dout  (input_rd_data)
    );

    wire [L1_OUT_CH-1:0] l1_wr_en;
    wire [L2_OUT_CH-1:0] l2_wr_en;

    wire signed [ACT_PAIR_WIDTH-1:0] l1_rd_pair [0:L1_OUT_CH-1];
    wire signed [ACT_PAIR_WIDTH-1:0] l2_rd_pair [0:L2_OUT_CH-1];

    wire signed [DATA_WIDTH-1:0] post_l1_data [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] post_l2_data [0:L2_OUT_CH-1];
    wire signed [ACT_PAIR_WIDTH-1:0] post_l1_pair_data [0:L1_OUT_CH-1];
    wire signed [ACT_PAIR_WIDTH-1:0] post_l2_pair_data [0:L2_OUT_CH-1];

    wire act_wr_en;
    wire act_rd_en;
    wire [WORD_ADDR_WIDTH-1:0] act_wr_addr;
    wire [WORD_ADDR_WIDTH-1:0] act_rd_addr;
    wire [ACT_WIDTH-1:0] act_wr_data;
    wire [ACT_WIDTH-1:0] act_rd_data;

    // Single activation buffer shared by the intermediate feature maps.
    //
    // Layer 1 writes four output channels packed into one 128-bit word:
    //   4 channels * 2 horizontal pixels * 16 bits.
    // Layer 2 overwrites the same word address with two output channels
    // in the lower 64 bits. Layer 3 reads those lower channel pairs.
    assign act_wr_en   = ((r_layer == LAYER_1) && l1_wr_en[0]) ||
                         ((r_layer == LAYER_2) && l2_wr_en[0]);
    assign act_rd_en   = ctrl_input_rd_en &&
                         ((r_layer == LAYER_2) || (r_layer == LAYER_3));
    assign act_wr_addr = r_write_addr[PIXEL_ADDR_WIDTH-1:1];
    assign act_rd_addr = ctrl_input_rd_addr[PIXEL_ADDR_WIDTH-1:1];
    assign act_wr_data = (r_layer == LAYER_1) ?
                         {post_l1_pair_data[3], post_l1_pair_data[2],
                          post_l1_pair_data[1], post_l1_pair_data[0]} :
                         {{((L1_OUT_CH-L2_OUT_CH)*ACT_PAIR_WIDTH){1'b0}},
                          post_l2_pair_data[1], post_l2_pair_data[0]};

    srcnn42_simple_dual_port_bram #(
        .WIDTH      (ACT_WIDTH),
        .DEPTH      (IMAGE_WORDS),
        .ADDR_WIDTH (WORD_ADDR_WIDTH),
        .INIT_FILE  ("")
    ) u_srcnn42_activation_bram (
        .clk      (i_clk),
        .wr_en    (act_wr_en),
        .rd_en    (act_rd_en),
        .wr_addr  (act_wr_addr),
        .rd_addr  (act_rd_addr),
        .wr_din   (act_wr_data),
        .rd_dout  (act_rd_data)
    );

    genvar ch;
    generate
        // Unpack layer-1 feature-map channel pairs for layer-2 input.
        for (ch = 0; ch < L1_OUT_CH; ch = ch + 1) begin : gen_l1_unpack
            assign l1_rd_pair[ch] = act_rd_data[(ch*ACT_PAIR_WIDTH)+:ACT_PAIR_WIDTH];
        end

        // Unpack layer-2 feature-map channel pairs for layer-3 input.
        for (ch = 0; ch < L2_OUT_CH; ch = ch + 1) begin : gen_l2_unpack
            assign l2_rd_pair[ch] = act_rd_data[(ch*ACT_PAIR_WIDTH)+:ACT_PAIR_WIDTH];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Line-buffer banks
    //--------------------------------------------------------------------------

    wire signed [ACT_PAIR_WIDTH-1:0] lb_input_data [0:MAX_BANKS-1];
    wire [MAX_BANKS-1:0] lb_input_valid;

    wire linebuf_load_col_is_image;
    wire [$clog2(IMAGE_WIDTH)-1:0] linebuf_load_pixel_col;
    wire linebuf_load_pixel_even;
    wire linebuf_load_word_valid;
    wire signed [DATA_WIDTH-1:0] linebuf_load_pixel_data;

    reg signed [DATA_WIDTH-1:0] input_pack_lower;
    reg input_pack_phase;

    assign linebuf_load_col_is_image = (ctrl_line_input_col > 0) &&
                                       (ctrl_line_input_col <= IMAGE_WIDTH);
    assign linebuf_load_pixel_col    = ctrl_line_input_col - 1'b1;
    assign linebuf_load_pixel_even   = !linebuf_load_pixel_col[0];
    assign linebuf_load_word_valid   = ctrl_line_input_valid &&
                                       linebuf_load_col_is_image &&
                                       !linebuf_load_pixel_even;
    assign linebuf_load_pixel_data   = ctrl_line_input_zero ? 16'sd0 : input_rd_data;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            input_pack_lower <= 16'sd0;
            input_pack_phase <= 1'b0;
        end else if (ctrl_line_clear || ctrl_line_shift) begin
            input_pack_lower <= 16'sd0;
            input_pack_phase <= 1'b0;
        end else if ((r_layer == LAYER_1) && ctrl_line_input_valid && linebuf_load_col_is_image) begin
            if (linebuf_load_pixel_even) begin
                input_pack_lower <= linebuf_load_pixel_data;
                input_pack_phase <= 1'b1;
            end else begin
                input_pack_phase <= 1'b0;
            end
        end
    end

    wire signed [DATA_WIDTH-1:0] lb_w00 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w01 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w02 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w10 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w11 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w12 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w20 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w21 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w22 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w03 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w13 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w23 [0:MAX_BANKS-1];

    generate
        for (ch = 0; ch < MAX_BANKS; ch = ch + 1) begin : gen_line_buffer
            // Select input source for each line-buffer bank.
            //
            // Layer 1:
            //   only bank 0 receives original input image pairs.
            //
            // Layer 2:
            //   banks 0~3 receive layer-1 feature-map pairs.
            //
            // Layer 3:
            //   banks 0~1 receive layer-2 feature-map pairs.
            //
            // Padding positions are forced to zero.
            if (ch == 0) begin : gen_ch0_data
                assign lb_input_valid[ch] = (r_layer == LAYER_1) ? linebuf_load_word_valid :
                                            (ctrl_line_input_valid && linebuf_load_col_is_image &&
                                             linebuf_load_pixel_even &&
                                             ((r_layer == LAYER_2) || (r_layer == LAYER_3)));
                assign lb_input_data[ch] = (r_layer == LAYER_1) ? {linebuf_load_pixel_data, input_pack_lower} :
                                           ctrl_line_input_zero ? {ACT_PAIR_WIDTH{1'b0}} :
                                           (r_layer == LAYER_2) ? l1_rd_pair[ch] :
                                           (r_layer == LAYER_3) ? l2_rd_pair[ch] : {ACT_PAIR_WIDTH{1'b0}};
            end else if (ch < L2_OUT_CH) begin : gen_ch1_data
                assign lb_input_valid[ch] = ctrl_line_input_valid && linebuf_load_col_is_image &&
                                            linebuf_load_pixel_even &&
                                            ((r_layer == LAYER_2) || (r_layer == LAYER_3));
                assign lb_input_data[ch] = ctrl_line_input_zero ? {ACT_PAIR_WIDTH{1'b0}} :
                                           (r_layer == LAYER_2) ? l1_rd_pair[ch] :
                                           (r_layer == LAYER_3) ? l2_rd_pair[ch] : {ACT_PAIR_WIDTH{1'b0}};
            end else begin : gen_ch23_data
                assign lb_input_valid[ch] = ctrl_line_input_valid && linebuf_load_col_is_image &&
                                            linebuf_load_pixel_even && (r_layer == LAYER_2);
                assign lb_input_data[ch] = ctrl_line_input_zero ? {ACT_PAIR_WIDTH{1'b0}} :
                                           (r_layer == LAYER_2) ? l1_rd_pair[ch] : {ACT_PAIR_WIDTH{1'b0}};
            end

            // One line buffer per active input channel bank.
            srcnn42_line_buffer #(
                .DATA_WIDTH  (DATA_WIDTH),
                .IMAGE_WIDTH (IMAGE_WIDTH),
                .KERNEL_SIZE (KERNEL_SIZE)
            ) u_srcnn42_line_buffer (
                .i_clk           (i_clk),
                .i_rstn          (i_rstn),
                .i_clear         (ctrl_line_clear),
                .i_input_valid   (lb_input_valid[ch]),
                .i_input_data    (lb_input_data[ch]),
                .i_line_shift    (ctrl_line_shift),
                .i_window_shift  (ctrl_window_shift),
                .i_window_shift_two (r_layer != LAYER_3),
                .o_window_00     (lb_w00[ch]),
                .o_window_01     (lb_w01[ch]),
                .o_window_02     (lb_w02[ch]),
                .o_window_10     (lb_w10[ch]),
                .o_window_11     (lb_w11[ch]),
                .o_window_12     (lb_w12[ch]),
                .o_window_20     (lb_w20[ch]),
                .o_window_21     (lb_w21[ch]),
                .o_window_22     (lb_w22[ch]),
                .o_window_03     (lb_w03[ch]),
                .o_window_13     (lb_w13[ch]),
                .o_window_23     (lb_w23[ch])
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Shared PE array and writeback datapath
    //--------------------------------------------------------------------------

    wire signed [DATA_WIDTH-1:0] pe_w00 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w01 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w02 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w10 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w11 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w12 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w20 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w21 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_w22 [0:PE_COUNT-1];

    wire signed [DATA_WIDTH-1:0] pe_weight_00 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_01 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_02 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_10 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_11 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_12 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_20 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_21 [0:PE_COUNT-1];
    wire signed [DATA_WIDTH-1:0] pe_weight_22 [0:PE_COUNT-1];

    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_00_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_01_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_02_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_10_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_11_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_12_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_20_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_21_flat;
    wire signed [(BASE_PE_COUNT*DATA_WIDTH)-1:0] pe_weight_22_flat;

    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] post_bias_flat;

    wire signed [MAC_WIDTH-1:0] pe_data [0:PE_COUNT-1];
    wire [PE_COUNT-1:0] pe_valid;
    wire [PE_COUNT-1:0] pe_en;

    wire signed [MAC_WIDTH-1:0] l2_sum [0:(PE_GROUPS*L2_OUT_CH)-1];
    wire signed [MAC_WIDTH-1:0] l3_sum;

    wire signed [MAC_WIDTH-1:0] post_mac_data [0:POST_COUNT-1];
    wire signed [DATA_WIDTH-1:0] post_bias [0:POST_COUNT-1];
    wire signed [DATA_WIDTH-1:0] post_data [0:POST_COUNT-1];
    wire [POST_COUNT-1:0] post_valid;
    wire [POST_COUNT-1:0] post_in_valid;

    wire [L1_OUT_CH-1:0] post_l1_valid;
    wire [L2_OUT_CH-1:0] post_l2_valid;
    wire signed [DATA_WIDTH-1:0] post_l3_data;
    wire post_l3_valid;

    // ROM provides layer-dependent weights and biases.
    srcnn42_weight_bias_rom #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE),
        .L1_OUT_CH   (L1_OUT_CH),
        .L2_OUT_CH   (L2_OUT_CH),
        .W1_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_W1_hex.txt"),
        .B1_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_B1_hex.txt"),
        .W2_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_W2_hex.txt"),
        .B2_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_B2_hex.txt"),
        .W3_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_W3_hex.txt"),
        .B3_INIT     ("C:/DSD26_Termproject_Materials/04_SRCNN_42/init/fixed_point_B3_hex.txt")
    ) u_srcnn42_weight_bias_rom (
        .i_layer       (r_layer),
        .o_weight_00   (pe_weight_00_flat),
        .o_weight_01   (pe_weight_01_flat),
        .o_weight_02   (pe_weight_02_flat),
        .o_weight_10   (pe_weight_10_flat),
        .o_weight_11   (pe_weight_11_flat),
        .o_weight_12   (pe_weight_12_flat),
        .o_weight_20   (pe_weight_20_flat),
        .o_weight_21   (pe_weight_21_flat),
        .o_weight_22   (pe_weight_22_flat),
        .o_post_bias   (post_bias_flat)
    );

    genvar pe_idx;
    generate
        for (pe_idx = 0; pe_idx < PE_COUNT; pe_idx = pe_idx + 1) begin : gen_shared_pe
            localparam integer PE_GROUP = pe_idx / BASE_PE_COUNT;
            localparam integer BASE_IDX = pe_idx % BASE_PE_COUNT;
            localparam integer L2_IC    = BASE_IDX % L1_OUT_CH;

            // PE input-window routing.
            //
            // Layer 1:
            //   group 0 computes the current column.
            //   group 1 computes the adjacent column.
            //
            // Layer 2:
            //   both groups map to output/input-channel pairs.
            //
            // Layer 3:
            //   only group 0 is enabled for the final output pixel.
            if (BASE_IDX < L2_OUT_CH) begin : gen_l123_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w00[0] : lb_w01[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w00[L2_IC] : lb_w01[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w00[BASE_IDX] : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w01[0] : lb_w02[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w01[L2_IC] : lb_w02[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w01[BASE_IDX] : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w02[0] : lb_w03[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w02[L2_IC] : lb_w03[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w02[BASE_IDX] : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w10[0] : lb_w11[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w10[L2_IC] : lb_w11[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w10[BASE_IDX] : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w11[0] : lb_w12[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w11[L2_IC] : lb_w12[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w11[BASE_IDX] : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w12[0] : lb_w13[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w12[L2_IC] : lb_w13[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w12[BASE_IDX] : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w20[0] : lb_w21[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w20[L2_IC] : lb_w21[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w20[BASE_IDX] : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w21[0] : lb_w22[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w21[L2_IC] : lb_w22[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w21[BASE_IDX] : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w22[0] : lb_w23[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w22[L2_IC] : lb_w23[L2_IC]) :
                                        (r_layer == LAYER_3) ? lb_w22[BASE_IDX] : 16'sd0;

                assign pe_en[pe_idx] = ctrl_mac_en && ((r_layer != LAYER_3) || (PE_GROUP == 0));
            end else if (BASE_IDX < L1_OUT_CH) begin : gen_l12_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w00[0] : lb_w01[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w00[L2_IC] : lb_w01[L2_IC]) : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w01[0] : lb_w02[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w01[L2_IC] : lb_w02[L2_IC]) : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w02[0] : lb_w03[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w02[L2_IC] : lb_w03[L2_IC]) : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w10[0] : lb_w11[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w10[L2_IC] : lb_w11[L2_IC]) : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w11[0] : lb_w12[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w11[L2_IC] : lb_w12[L2_IC]) : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w12[0] : lb_w13[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w12[L2_IC] : lb_w13[L2_IC]) : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w20[0] : lb_w21[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w20[L2_IC] : lb_w21[L2_IC]) : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w21[0] : lb_w22[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w21[L2_IC] : lb_w22[L2_IC]) : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_1) ? ((PE_GROUP == 0) ? lb_w22[0] : lb_w23[0]) :
                                        (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w22[L2_IC] : lb_w23[L2_IC]) : 16'sd0;

                assign pe_en[pe_idx] = ctrl_mac_en && (r_layer != LAYER_3);
            end else begin : gen_l2_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w00[L2_IC] : lb_w01[L2_IC]) : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w01[L2_IC] : lb_w02[L2_IC]) : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w02[L2_IC] : lb_w03[L2_IC]) : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w10[L2_IC] : lb_w11[L2_IC]) : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w11[L2_IC] : lb_w12[L2_IC]) : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w12[L2_IC] : lb_w13[L2_IC]) : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w20[L2_IC] : lb_w21[L2_IC]) : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w21[L2_IC] : lb_w22[L2_IC]) : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_2) ? ((PE_GROUP == 0) ? lb_w22[L2_IC] : lb_w23[L2_IC]) : 16'sd0;

                assign pe_en[pe_idx] = ctrl_mac_en && (r_layer == LAYER_2);
            end

            // Reuse the base PE weights for both horizontal PE groups.
            assign pe_weight_00[pe_idx] = pe_weight_00_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_01[pe_idx] = pe_weight_01_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_02[pe_idx] = pe_weight_02_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_10[pe_idx] = pe_weight_10_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_11[pe_idx] = pe_weight_11_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_12[pe_idx] = pe_weight_12_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_20[pe_idx] = pe_weight_20_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_21[pe_idx] = pe_weight_21_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_22[pe_idx] = pe_weight_22_flat[(BASE_IDX*DATA_WIDTH)+:DATA_WIDTH];

            srcnn42_pe #(
                .DATA_WIDTH  (DATA_WIDTH)
            ) u_srcnn42_pe (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_mac_en       (pe_en[pe_idx]),
                .i_window_00    (pe_w00[pe_idx]),
                .i_window_01    (pe_w01[pe_idx]),
                .i_window_02    (pe_w02[pe_idx]),
                .i_window_10    (pe_w10[pe_idx]),
                .i_window_11    (pe_w11[pe_idx]),
                .i_window_12    (pe_w12[pe_idx]),
                .i_window_20    (pe_w20[pe_idx]),
                .i_window_21    (pe_w21[pe_idx]),
                .i_window_22    (pe_w22[pe_idx]),
                .i_weight_00    (pe_weight_00[pe_idx]),
                .i_weight_01    (pe_weight_01[pe_idx]),
                .i_weight_02    (pe_weight_02[pe_idx]),
                .i_weight_10    (pe_weight_10[pe_idx]),
                .i_weight_11    (pe_weight_11[pe_idx]),
                .i_weight_12    (pe_weight_12[pe_idx]),
                .i_weight_20    (pe_weight_20[pe_idx]),
                .i_weight_21    (pe_weight_21[pe_idx]),
                .i_weight_22    (pe_weight_22[pe_idx]),
                .o_output_data  (pe_data[pe_idx]),
                .o_output_valid (pe_valid[pe_idx])
            );
        end
    endgenerate

    // Layer 2 sums four input-channel PE results per output channel.
    assign l2_sum[0] = pe_data[0]  + pe_data[1]  + pe_data[2]  + pe_data[3];
    assign l2_sum[1] = pe_data[4]  + pe_data[5]  + pe_data[6]  + pe_data[7];
    assign l2_sum[2] = pe_data[8]  + pe_data[9]  + pe_data[10] + pe_data[11];
    assign l2_sum[3] = pe_data[12] + pe_data[13] + pe_data[14] + pe_data[15];

    // Layer 3 sums two input-channel PE results into one output channel.
    assign l3_sum    = pe_data[0] + pe_data[1];

    genvar post_idx;
    generate
        for (post_idx = 0; post_idx < POST_COUNT; post_idx = post_idx + 1) begin : gen_shared_post
            localparam integer POST_GROUP = post_idx / L1_OUT_CH;
            localparam integer POST_CH    = post_idx % L1_OUT_CH;
            localparam integer PE_BASE    = POST_GROUP * BASE_PE_COUNT;

            // Shared post-process units are reused across layers and
            // duplicated across the two horizontal PE groups.
            if (POST_CH < L2_OUT_CH) begin : gen_l123_post
                assign post_in_valid[post_idx] = (r_layer == LAYER_1) ? pe_valid[PE_BASE + POST_CH] :
                                                 (r_layer == LAYER_2) ? pe_valid[PE_BASE + (POST_CH*L1_OUT_CH)] :
                                                 ((r_layer == LAYER_3) && (POST_GROUP == 0) && (POST_CH == 0)) ? pe_valid[PE_BASE] : 1'b0;
                assign post_mac_data[post_idx] = (r_layer == LAYER_1) ? pe_data[PE_BASE + POST_CH] :
                                                 (r_layer == LAYER_2) ? l2_sum[(POST_GROUP*L2_OUT_CH)+POST_CH] :
                                                 ((r_layer == LAYER_3) && (POST_GROUP == 0) && (POST_CH == 0)) ? l3_sum : {MAC_WIDTH{1'b0}};
                assign post_bias[post_idx] = post_bias_flat[(POST_CH*DATA_WIDTH)+:DATA_WIDTH];
            end else begin : gen_l1_post
                assign post_in_valid[post_idx] = (r_layer == LAYER_1) ? pe_valid[PE_BASE + POST_CH] : 1'b0;
                assign post_mac_data[post_idx] = (r_layer == LAYER_1) ? pe_data[PE_BASE + POST_CH] : {MAC_WIDTH{1'b0}};
                assign post_bias[post_idx]     = post_bias_flat[(POST_CH*DATA_WIDTH)+:DATA_WIDTH];
            end

            srcnn42_post_process #(
                .DATA_WIDTH  (DATA_WIDTH),
                .FIXED_SHIFT (8)
            ) u_srcnn42_post (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_valid        (post_in_valid[post_idx]),
                .i_relu_en      (r_layer != LAYER_3),
                .i_mac_data     (post_mac_data[post_idx]),
                .i_bias         (post_bias[post_idx]),
                .o_output_data  (post_data[post_idx]),
                .o_output_valid (post_valid[post_idx])
            );

            if (POST_GROUP == 0) begin : gen_post_alias
                // Keep the existing visible layer-output signals as 16-bit
                // current-column values for testbench tracing.
                assign post_l1_data[POST_CH]  = post_data[POST_CH];
                assign post_l1_valid[POST_CH] = post_valid[POST_CH] &&
                                                post_valid[L1_OUT_CH + POST_CH] &&
                                                (r_layer == LAYER_1);
                assign l1_wr_en[POST_CH]      = post_l1_valid[POST_CH];
            end
        end
    endgenerate

    assign post_l1_pair_data[0] = {post_data[L1_OUT_CH + 0], post_data[0]};
    assign post_l1_pair_data[1] = {post_data[L1_OUT_CH + 1], post_data[1]};
    assign post_l1_pair_data[2] = {post_data[L1_OUT_CH + 2], post_data[2]};
    assign post_l1_pair_data[3] = {post_data[L1_OUT_CH + 3], post_data[3]};

    // Layer 2 post outputs overwrite the activation buffer for layer 3.
    assign post_l2_data[0]      = post_data[0];
    assign post_l2_data[1]      = post_data[1];
    assign post_l2_pair_data[0] = {post_data[L1_OUT_CH + 0], post_data[0]};
    assign post_l2_pair_data[1] = {post_data[L1_OUT_CH + 1], post_data[1]};
    assign post_l2_valid[0]     = post_valid[0] && post_valid[L1_OUT_CH + 0] && (r_layer == LAYER_2);
    assign post_l2_valid[1]     = post_valid[1] && post_valid[L1_OUT_CH + 1] && (r_layer == LAYER_2);
    assign l2_wr_en[0]          = post_l2_valid[0];
    assign l2_wr_en[1]          = post_l2_valid[1];

    // Layer 3 post output is the final output pixel.
    assign post_l3_data  = post_data[0];
    assign post_l3_valid = post_valid[0] && (r_layer == LAYER_3);

    //--------------------------------------------------------------------------
    // Writeback address and output interface
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_write_addr      <= {PIXEL_ADDR_WIDTH{1'b0}};
            o_done            <= 1'b0;
            output_bram_wen   <= 1'b0;
            output_bram_waddr <= {IN_ADDR_WIDTH{1'b0}};
            L3_p_out          <= {IN_WIDTH{1'b0}};
        end else begin
            o_done          <= ctrl_done;
            output_bram_wen <= 1'b0;

            if (ctrl_layer_start) begin
                // Each new layer writes from address 0 of its feature-map space.
                r_write_addr <= {PIXEL_ADDR_WIDTH{1'b0}};
            end else if ((r_layer == LAYER_1) && post_l1_valid[0]) begin
                // Layer 1 writes two pixels for four banks in parallel.
                // Address increments by two output pixels per activation word.
                r_write_addr <= r_write_addr + 2'd2;
            end else if ((r_layer == LAYER_2) && post_l2_valid[0]) begin
                // Layer 2 writes two pixels for two banks in parallel.
                // Address increments by two output pixels per activation word.
                r_write_addr <= r_write_addr + 2'd2;
            end else if ((r_layer == LAYER_3) && post_l3_valid) begin
                // Layer 3 writes the final image output.
                r_write_addr      <= r_write_addr + 1'b1;
                output_bram_wen   <= 1'b1;
                output_bram_waddr <= w_image_base + r_write_addr;
                L3_p_out          <= post_l3_data;
            end
        end
    end

endmodule
