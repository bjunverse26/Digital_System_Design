`timescale 1ns / 1ps

module srcnn88_top #(
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

    localparam NUM_IMAGES       = 3;
    localparam INPUT_DEPTH      = IMAGE_PIXELS * NUM_IMAGES;
    localparam INPUT_ADDR_WIDTH = $clog2(INPUT_DEPTH);
    localparam PIXEL_ADDR_WIDTH = $clog2(IMAGE_PIXELS);

    localparam KERNEL_SIZE      = 3;

    // SRCNN channel configuration.
    // Layer 1: 1 input channel  -> 8 output channels
    // Layer 2: 8 input channels -> 8 output channels
    // Layer 3: 8 input channels -> 1 output channel
    localparam L1_OUT_CH        = 8;
    localparam L2_OUT_CH        = 8;

    // Maximum number of feature-map banks needed at any layer.
    localparam MAX_BANKS        = 8;

    // Shared PE count is sized for all layer-2 output/input-channel pairs:
    // L2_OUT_CH * L1_OUT_CH = 8 * 8 = 64.
    localparam PE_COUNT         = L2_OUT_CH * L1_OUT_CH;

    localparam LAYER_1          = 2'd0;
    localparam LAYER_2          = 2'd1;
    localparam LAYER_3          = 2'd2;

    //--------------------------------------------------------------------------
    // Global schedule from recursive controller
    //--------------------------------------------------------------------------

    wire [1:0] r_image_idx;
    wire [1:0] r_layer;

    // Write address for intermediate feature maps and final output.
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
    wire ctrl_line_shift;
    wire ctrl_mac_en;
    wire ctrl_window_shift;
    wire ctrl_done;
    wire ctrl_layer_start;

    // Controller generates the global layer/image schedule,
    // padded input read sequence, line-buffer control, and MAC enable.
    srcnn88_controller #(
        .IMAGE_WIDTH       (IMAGE_WIDTH),
        .IMAGE_HEIGHT      (IMAGE_HEIGHT),
        .KERNEL_SIZE       (KERNEL_SIZE),
        .NUM_IMAGES        (NUM_IMAGES),
        .INPUT_ADDR_WIDTH  (PIXEL_ADDR_WIDTH),
        .DRAIN_CYCLES      (3)
    ) u_srcnn88_controller (
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

    srcnn88_simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (INPUT_DEPTH),
        .ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .INIT_FILE  ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/input_text1_2_3.txt")
    ) u_srcnn88_input_bram (
        .clk      (i_clk),
        .wr_en    (1'b0),
        .rd_en    (input_rd_en),
        .wr_addr  ({INPUT_ADDR_WIDTH{1'b0}}),
        .rd_addr  (input_rd_addr),
        .wr_din   ({DATA_WIDTH{1'b0}}),
        .rd_dout  (input_rd_data)
    );

    localparam ACT_WIDTH = L1_OUT_CH * DATA_WIDTH;

    wire [L1_OUT_CH-1:0] l1_wr_en;
    wire [L2_OUT_CH-1:0] l2_wr_en;

    wire signed [DATA_WIDTH-1:0] l1_rd_data [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] l2_rd_data [0:L2_OUT_CH-1];

    wire signed [DATA_WIDTH-1:0] post_l1_data [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] post_l2_data [0:L2_OUT_CH-1];

    wire act_wr_en;
    wire act_rd_en;
    wire [ACT_WIDTH-1:0] act_wr_data;
    wire [ACT_WIDTH-1:0] act_rd_data;

    // Single activation buffer shared by the intermediate feature maps.
    //
    // Layer 1 writes eight output channels packed into one 128-bit word.
    // Layer 2 reads that packed word and overwrites the same pixel address
    // with its eight output channels.
    // Layer 3 reads the packed layer-2 feature-map input.
    assign act_wr_en   = ((r_layer == LAYER_1) && l1_wr_en[0]) ||
                         ((r_layer == LAYER_2) && l2_wr_en[0]);
    assign act_rd_en   = ctrl_input_rd_en &&
                         ((r_layer == LAYER_2) || (r_layer == LAYER_3));
    assign act_wr_data = (r_layer == LAYER_1) ?
                         {post_l1_data[7], post_l1_data[6],
                          post_l1_data[5], post_l1_data[4],
                          post_l1_data[3], post_l1_data[2],
                          post_l1_data[1], post_l1_data[0]} :
                         {post_l2_data[7], post_l2_data[6],
                          post_l2_data[5], post_l2_data[4],
                          post_l2_data[3], post_l2_data[2],
                          post_l2_data[1], post_l2_data[0]};

    srcnn88_simple_dual_port_bram #(
        .WIDTH      (ACT_WIDTH),
        .DEPTH      (IMAGE_PIXELS),
        .ADDR_WIDTH (PIXEL_ADDR_WIDTH),
        .INIT_FILE  ("")
    ) u_srcnn88_activation_bram (
        .clk      (i_clk),
        .wr_en    (act_wr_en),
        .rd_en    (act_rd_en),
        .wr_addr  (r_write_addr),
        .rd_addr  (ctrl_input_rd_addr),
        .wr_din   (act_wr_data),
        .rd_dout  (act_rd_data)
    );

    genvar ch;
    generate
        // Unpack layer-1 feature-map channels for layer-2 input.
        for (ch = 0; ch < L1_OUT_CH; ch = ch + 1) begin : gen_l1_unpack
            assign l1_rd_data[ch] = act_rd_data[(ch*DATA_WIDTH)+:DATA_WIDTH];
        end

        // Unpack layer-2 feature-map channels for layer-3 input.
        for (ch = 0; ch < L2_OUT_CH; ch = ch + 1) begin : gen_l2_unpack
            assign l2_rd_data[ch] = act_rd_data[(ch*DATA_WIDTH)+:DATA_WIDTH];
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Line-buffer banks
    //--------------------------------------------------------------------------

    wire signed [DATA_WIDTH-1:0] lb_input_data [0:MAX_BANKS-1];

    wire signed [DATA_WIDTH-1:0] lb_w00 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w01 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w02 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w10 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w11 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w12 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w20 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w21 [0:MAX_BANKS-1];
    wire signed [DATA_WIDTH-1:0] lb_w22 [0:MAX_BANKS-1];

    generate
        for (ch = 0; ch < MAX_BANKS; ch = ch + 1) begin : gen_line_buffer
            // Select input source for each line-buffer bank.
            //
            // Layer 1:
            //   only bank 0 receives original input image.
            //
            // Layer 2:
            //   banks 0~7 receive layer-1 feature maps.
            //
            // Layer 3:
            //   banks 0~7 receive layer-2 feature maps.
            //
            // Padding positions are forced to zero.
            if (ch == 0) begin : gen_ch0_data
                assign lb_input_data[ch] = ctrl_line_input_zero ? 16'sd0 :
                                           (r_layer == LAYER_1) ? input_rd_data :
                                           (r_layer == LAYER_2) ? l1_rd_data[ch] :
                                           (r_layer == LAYER_3) ? l2_rd_data[ch] : 16'sd0;
            end else if (ch < L2_OUT_CH) begin : gen_ch1_data
                assign lb_input_data[ch] = ctrl_line_input_zero ? 16'sd0 :
                                           (r_layer == LAYER_2) ? l1_rd_data[ch] :
                                           (r_layer == LAYER_3) ? l2_rd_data[ch] : 16'sd0;
            end else begin : gen_ch23_data
                assign lb_input_data[ch] = ctrl_line_input_zero ? 16'sd0 :
                                           (r_layer == LAYER_2) ? l1_rd_data[ch] : 16'sd0;
            end

            // One line buffer per active input channel bank.
            srcnn88_line_buffer #(
                .DATA_WIDTH  (DATA_WIDTH),
                .IMAGE_WIDTH (IMAGE_WIDTH),
                .KERNEL_SIZE (KERNEL_SIZE)
            ) u_srcnn88_line_buffer (
                .i_clk           (i_clk),
                .i_rstn          (i_rstn),
                .i_clear         (ctrl_line_clear),
                .i_input_valid   (ctrl_line_input_valid),
                .i_input_data    (lb_input_data[ch]),
                .i_line_shift    (ctrl_line_shift),
                .i_window_shift  (ctrl_window_shift),
                .o_window_00     (lb_w00[ch]),
                .o_window_01     (lb_w01[ch]),
                .o_window_02     (lb_w02[ch]),
                .o_window_10     (lb_w10[ch]),
                .o_window_11     (lb_w11[ch]),
                .o_window_12     (lb_w12[ch]),
                .o_window_20     (lb_w20[ch]),
                .o_window_21     (lb_w21[ch]),
                .o_window_22     (lb_w22[ch])
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

    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_00_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_01_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_02_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_10_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_11_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_12_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_20_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_21_flat;
    wire signed [(PE_COUNT*DATA_WIDTH)-1:0] pe_weight_22_flat;

    wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0] post_bias_flat;

    wire signed [MAC_WIDTH-1:0] pe_data [0:PE_COUNT-1];
    wire [PE_COUNT-1:0] pe_valid;
    wire [PE_COUNT-1:0] pe_en;

    wire signed [MAC_WIDTH-1:0] l2_sum [0:L2_OUT_CH-1];
    wire signed [MAC_WIDTH-1:0] l3_sum;

    wire signed [MAC_WIDTH-1:0] post_mac_data [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] post_bias [0:L1_OUT_CH-1];
    wire signed [DATA_WIDTH-1:0] post_data [0:L1_OUT_CH-1];
    wire [L1_OUT_CH-1:0] post_valid;
    wire [L1_OUT_CH-1:0] post_in_valid;

    wire [L1_OUT_CH-1:0] post_l1_valid;
    wire [L2_OUT_CH-1:0] post_l2_valid;
    wire signed [DATA_WIDTH-1:0] post_l3_data;
    wire post_l3_valid;

    // ROM provides layer-dependent weights and biases.
    srcnn88_weight_bias_rom #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE),
        .L1_OUT_CH   (L1_OUT_CH),
        .L2_OUT_CH   (L2_OUT_CH),
        .W1_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_W1_hex.txt"),
        .B1_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_B1_hex.txt"),
        .W2_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_W2_hex.txt"),
        .B2_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_B2_hex.txt"),
        .W3_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_W3_hex.txt"),
        .B3_INIT     ("C:/DSD26_Termproject_Materials/05_SRCNN_88/init/fixed_point_B3_hex.txt")
    ) u_srcnn88_weight_bias_rom (
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
            localparam integer L2_IC = pe_idx % L1_OUT_CH;

            // PE input-window routing.
            //
            // Layer 1:
            //   PE0~PE7 use the same input window from bank 0
            //   and produce 8 output channels.
            //
            // Layer 2:
            //   PE0~PE63 map to output/input-channel pairs.
            //   L2_IC = input channel index within layer 2.
            //
            // Layer 3:
            //   PE0~PE7 use layer-2 feature-map banks and are later summed.
            if (pe_idx < L2_OUT_CH) begin : gen_l123_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_1) ? lb_w00[0] :
                                        (r_layer == LAYER_2) ? lb_w00[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w00[pe_idx] : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_1) ? lb_w01[0] :
                                        (r_layer == LAYER_2) ? lb_w01[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w01[pe_idx] : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_1) ? lb_w02[0] :
                                        (r_layer == LAYER_2) ? lb_w02[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w02[pe_idx] : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_1) ? lb_w10[0] :
                                        (r_layer == LAYER_2) ? lb_w10[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w10[pe_idx] : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_1) ? lb_w11[0] :
                                        (r_layer == LAYER_2) ? lb_w11[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w11[pe_idx] : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_1) ? lb_w12[0] :
                                        (r_layer == LAYER_2) ? lb_w12[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w12[pe_idx] : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_1) ? lb_w20[0] :
                                        (r_layer == LAYER_2) ? lb_w20[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w20[pe_idx] : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_1) ? lb_w21[0] :
                                        (r_layer == LAYER_2) ? lb_w21[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w21[pe_idx] : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_1) ? lb_w22[0] :
                                        (r_layer == LAYER_2) ? lb_w22[L2_IC] :
                                        (r_layer == LAYER_3) ? lb_w22[pe_idx] : 16'sd0;

                assign pe_en[pe_idx] = ctrl_mac_en;
            end else if (pe_idx < L1_OUT_CH) begin : gen_l12_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_1) ? lb_w00[0] :
                                        (r_layer == LAYER_2) ? lb_w00[L2_IC] : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_1) ? lb_w01[0] :
                                        (r_layer == LAYER_2) ? lb_w01[L2_IC] : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_1) ? lb_w02[0] :
                                        (r_layer == LAYER_2) ? lb_w02[L2_IC] : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_1) ? lb_w10[0] :
                                        (r_layer == LAYER_2) ? lb_w10[L2_IC] : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_1) ? lb_w11[0] :
                                        (r_layer == LAYER_2) ? lb_w11[L2_IC] : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_1) ? lb_w12[0] :
                                        (r_layer == LAYER_2) ? lb_w12[L2_IC] : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_1) ? lb_w20[0] :
                                        (r_layer == LAYER_2) ? lb_w20[L2_IC] : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_1) ? lb_w21[0] :
                                        (r_layer == LAYER_2) ? lb_w21[L2_IC] : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_1) ? lb_w22[0] :
                                        (r_layer == LAYER_2) ? lb_w22[L2_IC] : 16'sd0;

                // These PEs are used in layer 1 and layer 2, not layer 3.
                assign pe_en[pe_idx] = ctrl_mac_en && (r_layer != LAYER_3);
            end else begin : gen_l2_window
                assign pe_w00[pe_idx] = (r_layer == LAYER_2) ? lb_w00[L2_IC] : 16'sd0;
                assign pe_w01[pe_idx] = (r_layer == LAYER_2) ? lb_w01[L2_IC] : 16'sd0;
                assign pe_w02[pe_idx] = (r_layer == LAYER_2) ? lb_w02[L2_IC] : 16'sd0;
                assign pe_w10[pe_idx] = (r_layer == LAYER_2) ? lb_w10[L2_IC] : 16'sd0;
                assign pe_w11[pe_idx] = (r_layer == LAYER_2) ? lb_w11[L2_IC] : 16'sd0;
                assign pe_w12[pe_idx] = (r_layer == LAYER_2) ? lb_w12[L2_IC] : 16'sd0;
                assign pe_w20[pe_idx] = (r_layer == LAYER_2) ? lb_w20[L2_IC] : 16'sd0;
                assign pe_w21[pe_idx] = (r_layer == LAYER_2) ? lb_w21[L2_IC] : 16'sd0;
                assign pe_w22[pe_idx] = (r_layer == LAYER_2) ? lb_w22[L2_IC] : 16'sd0;

                // Remaining PEs are only needed for layer 2.
                assign pe_en[pe_idx] = ctrl_mac_en && (r_layer == LAYER_2);
            end

            // Unpack layer-selected weights from flat buses.
            assign pe_weight_00[pe_idx] = pe_weight_00_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_01[pe_idx] = pe_weight_01_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_02[pe_idx] = pe_weight_02_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_10[pe_idx] = pe_weight_10_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_11[pe_idx] = pe_weight_11_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_12[pe_idx] = pe_weight_12_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_20[pe_idx] = pe_weight_20_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_21[pe_idx] = pe_weight_21_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];
            assign pe_weight_22[pe_idx] = pe_weight_22_flat[(pe_idx*DATA_WIDTH)+:DATA_WIDTH];

            srcnn88_pe #(
                .DATA_WIDTH  (DATA_WIDTH)
            ) u_srcnn88_pe (
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

    genvar sum_idx;
    generate
        // Layer 2:
        // Each output channel sums 8 input-channel PE results.
        for (sum_idx = 0; sum_idx < L2_OUT_CH; sum_idx = sum_idx + 1) begin : gen_l2_sum
            assign l2_sum[sum_idx] =
                pe_data[(sum_idx*L1_OUT_CH)+0] +
                pe_data[(sum_idx*L1_OUT_CH)+1] +
                pe_data[(sum_idx*L1_OUT_CH)+2] +
                pe_data[(sum_idx*L1_OUT_CH)+3] +
                pe_data[(sum_idx*L1_OUT_CH)+4] +
                pe_data[(sum_idx*L1_OUT_CH)+5] +
                pe_data[(sum_idx*L1_OUT_CH)+6] +
                pe_data[(sum_idx*L1_OUT_CH)+7];
        end
    endgenerate

    // Layer 3:
    // Final output channel sums 8 PE results from the 8 layer-2 feature maps.
    assign l3_sum =
        pe_data[0] +
        pe_data[1] +
        pe_data[2] +
        pe_data[3] +
        pe_data[4] +
        pe_data[5] +
        pe_data[6] +
        pe_data[7];

    genvar post_idx;
    generate
        for (post_idx = 0; post_idx < L1_OUT_CH; post_idx = post_idx + 1) begin : gen_shared_post
            // Shared post-process units are reused across layers.
            //
            // Layer 1:
            //   post_idx 0~7 process PE0~PE7 directly.
            //
            // Layer 2:
            //   post_idx 0~7 process summed PE groups.
            //
            // Layer 3:
            //   post_idx 0 processes final summed result.
            if (post_idx < L2_OUT_CH) begin : gen_l123_post
                assign post_in_valid[post_idx] = (r_layer == LAYER_1) ? pe_valid[post_idx] :
                                                 (r_layer == LAYER_2) ? pe_valid[post_idx*L1_OUT_CH] :
                                                 (r_layer == LAYER_3) && (post_idx == 0) ? pe_valid[0] : 1'b0;

                assign post_mac_data[post_idx] = (r_layer == LAYER_1) ? pe_data[post_idx] :
                                                 (r_layer == LAYER_2) ? l2_sum[post_idx] :
                                                 (r_layer == LAYER_3) && (post_idx == 0) ? l3_sum : {MAC_WIDTH{1'b0}};

                assign post_bias[post_idx] = post_bias_flat[(post_idx*DATA_WIDTH)+:DATA_WIDTH];
            end else begin : gen_l1_post
                assign post_in_valid[post_idx] = (r_layer == LAYER_1) ? pe_valid[post_idx] : 1'b0;
                assign post_mac_data[post_idx] = (r_layer == LAYER_1) ? pe_data[post_idx] : {MAC_WIDTH{1'b0}};
                assign post_bias[post_idx]     = post_bias_flat[(post_idx*DATA_WIDTH)+:DATA_WIDTH];
            end

            srcnn88_post_process #(
                .DATA_WIDTH  (DATA_WIDTH),
                .FIXED_SHIFT (8)
            ) u_srcnn88_post (
                .i_clk          (i_clk),
                .i_rstn         (i_rstn),
                .i_valid        (post_in_valid[post_idx]),
                .i_relu_en      (r_layer != LAYER_3),
                .i_mac_data     (post_mac_data[post_idx]),
                .i_bias         (post_bias[post_idx]),
                .o_output_data  (post_data[post_idx]),
                .o_output_valid (post_valid[post_idx])
            );

            // Layer 1 post outputs are packed into the activation buffer.
            assign post_l1_data[post_idx]  = post_data[post_idx];
            assign post_l1_valid[post_idx] = post_valid[post_idx] && (r_layer == LAYER_1);
            assign l1_wr_en[post_idx]      = post_l1_valid[post_idx];
        end
    endgenerate

    genvar l2_post_idx;
    generate
        // Layer 2 post outputs overwrite the activation buffer for layer 3.
        for (l2_post_idx = 0; l2_post_idx < L2_OUT_CH; l2_post_idx = l2_post_idx + 1) begin : gen_l2_post
            assign post_l2_data[l2_post_idx]  = post_data[l2_post_idx];
            assign post_l2_valid[l2_post_idx] = post_valid[l2_post_idx] && (r_layer == LAYER_2);
            assign l2_wr_en[l2_post_idx]      = post_l2_valid[l2_post_idx];
        end
    endgenerate

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
                // Layer 1 writes eight packed channels in parallel.
                // Address increments once per output pixel.
                r_write_addr <= r_write_addr + 1'b1;
            end else if ((r_layer == LAYER_2) && post_l2_valid[0]) begin
                // Layer 2 writes eight packed channels in parallel.
                // Address increments once per output pixel.
                r_write_addr <= r_write_addr + 1'b1;
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
