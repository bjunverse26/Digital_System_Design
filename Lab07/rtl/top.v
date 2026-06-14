//==============================================================================
// File Name   : top.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Top-level wrapper for two 3x3 convolution layers with ReLU and
//               zero padding.
// Notes       : - Layer 1 reads act.txt and w_L1.txt.
//               - Layer 1 output is passed through ReLU and stored in an
//                 intermediate BRAM.
//               - Layer 2 reads the intermediate BRAM and w_L2.txt.
//               - Both layers use the same padding-capable controller interface.
//==============================================================================

`timescale 1ns / 1ps

module top #(
    parameter INPUT_WIDTH       = 5,
    parameter INPUT_HEIGHT      = 5,
    parameter WEIGHT_WIDTH      = 3,
    parameter WEIGHT_HEIGHT     = 3,
    parameter PADDING           = 1,
    parameter DATA_WIDTH        = 16,

    parameter PADDED_INPUT_WIDTH  = INPUT_WIDTH + (2 * PADDING),
    parameter PADDED_INPUT_HEIGHT = INPUT_HEIGHT + (2 * PADDING),

    parameter OUTPUT_WIDTH      = PADDED_INPUT_WIDTH - WEIGHT_WIDTH + 1,
    parameter OUTPUT_HEIGHT     = PADDED_INPUT_HEIGHT - WEIGHT_HEIGHT + 1,

    parameter INPUT_SIZE        = INPUT_WIDTH * INPUT_HEIGHT,
    parameter WEIGHT_SIZE       = WEIGHT_WIDTH * WEIGHT_HEIGHT,
    parameter OUTPUT_SIZE       = OUTPUT_WIDTH * OUTPUT_HEIGHT,

    parameter INPUT_ADDR_WIDTH  = $clog2(INPUT_SIZE),
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_SIZE),
    parameter OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_SIZE),

    parameter INIT_INPUT_BRAM     = "C:/Users/rlaqj/Project/Digital_System_Design/Lab07/rtl/init_file/act.txt",
    parameter INIT_WEIGHT_BRAM    = "C:/Users/rlaqj/Project/Digital_System_Design/Lab07/rtl/init_file/w_L1.txt",
    parameter INIT_WEIGHT_L2_BRAM = "C:/Users/rlaqj/Project/Digital_System_Design/Lab07/rtl/init_file/w_L2.txt"
) (
    input  wire                              i_clk,
    input  wire                              i_rstn,
    input  wire                              i_start,

    output wire                              o_done,
    output wire                              o_output_valid,
    output wire signed [(2*DATA_WIDTH)-1:0]  o_output,
    output wire                              o_line_rd_done
);

    //--------------------------------------------------------------------------
    // Layer select
    //--------------------------------------------------------------------------

    localparam LAYER_1 = 1'b0;
    localparam LAYER_2 = 1'b1;

    //--------------------------------------------------------------------------
    // Controller interface
    //--------------------------------------------------------------------------

    wire                         w_ctrl_input_rd_en;
    wire [INPUT_ADDR_WIDTH-1:0]  w_ctrl_input_rd_addr;
    wire                         w_ctrl_input_zero_valid;
    wire                         w_ctrl_input_line_done;

    wire                         w_ctrl_weight_rd_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] w_ctrl_weight_rd_addr;
    wire                         w_ctrl_layer;
    wire                         w_ctrl_done;

    //--------------------------------------------------------------------------
    // Layer 1 BRAM and stream wires
    //--------------------------------------------------------------------------

    wire                         w_l1_input_rd_en;
    wire [INPUT_ADDR_WIDTH-1:0]  w_l1_input_rd_addr;
    wire                         w_l1_input_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_l1_input_rd_dout;
    wire                         w_l1_input_valid;
    wire signed [DATA_WIDTH-1:0] w_l1_input_data;

    wire                         w_l1_weight_rd_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] w_l1_weight_rd_addr;
    wire                         w_l1_weight_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_l1_weight_rd_dout;

    wire                         w_l1_output_valid;
    wire signed [(2*DATA_WIDTH)-1:0] w_l1_output;
    wire                         w_l1_line_rd_done;
    wire signed [DATA_WIDTH-1:0] w_l1_relu_output;

    //--------------------------------------------------------------------------
    // Layer 2 BRAM and stream wires
    //--------------------------------------------------------------------------

    wire                         w_l2_input_rd_en;
    wire [INPUT_ADDR_WIDTH-1:0]  w_l2_input_rd_addr;
    wire                         w_l2_input_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_l2_input_rd_dout;
    wire                         w_l2_input_valid;
    wire signed [DATA_WIDTH-1:0] w_l2_input_data;

    wire                         w_l2_weight_rd_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] w_l2_weight_rd_addr;
    wire                         w_l2_weight_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_l2_weight_rd_dout;

    wire                         w_l2_output_valid;
    wire signed [(2*DATA_WIDTH)-1:0] w_l2_output;
    wire                         w_l2_line_rd_done;

    //--------------------------------------------------------------------------
    // Output and intermediate write tracking
    //--------------------------------------------------------------------------

    reg [OUTPUT_ADDR_WIDTH-1:0] r_l1_relu_wr_addr;
    reg [OUTPUT_ADDR_WIDTH:0]   r_l1_output_cnt;
    reg                         r_l1_output_done;
    reg [OUTPUT_ADDR_WIDTH-1:0] r_output_bram_wr_addr;
    reg [OUTPUT_ADDR_WIDTH:0]   r_l2_output_cnt;
    reg                         r_done;

    assign o_done         = r_done;
    assign o_output_valid = w_l2_output_valid;
    assign o_output       = w_l2_output;
    assign o_line_rd_done = (w_ctrl_layer == LAYER_1) ? w_l1_line_rd_done
                                                      : w_l2_line_rd_done;

    assign w_l1_relu_output = w_l1_output[(2*DATA_WIDTH)-1] ? {DATA_WIDTH{1'b0}}
                                                            : w_l1_output[DATA_WIDTH-1:0];

    assign w_l1_input_rd_en   = (w_ctrl_layer == LAYER_1) ? w_ctrl_input_rd_en : 1'b0;
    assign w_l1_input_rd_addr = w_ctrl_input_rd_addr;
    assign w_l1_input_valid   = (w_ctrl_layer == LAYER_1) &&
                                (w_l1_input_rd_valid || w_ctrl_input_zero_valid);
    assign w_l1_input_data    = w_ctrl_input_zero_valid ? {DATA_WIDTH{1'b0}}
                                                        : w_l1_input_rd_dout;

    assign w_l2_input_rd_en   = (w_ctrl_layer == LAYER_2) ? w_ctrl_input_rd_en : 1'b0;
    assign w_l2_input_rd_addr = w_ctrl_input_rd_addr;
    assign w_l2_input_valid   = (w_ctrl_layer == LAYER_2) &&
                                (w_l2_input_rd_valid || w_ctrl_input_zero_valid);
    assign w_l2_input_data    = w_ctrl_input_zero_valid ? {DATA_WIDTH{1'b0}}
                                                        : w_l2_input_rd_dout;

    assign w_l1_weight_rd_en   = (w_ctrl_layer == LAYER_1) ? w_ctrl_weight_rd_en : 1'b0;
    assign w_l1_weight_rd_addr = w_ctrl_weight_rd_addr;
    assign w_l2_weight_rd_en   = (w_ctrl_layer == LAYER_2) ? w_ctrl_weight_rd_en : 1'b0;
    assign w_l2_weight_rd_addr = w_ctrl_weight_rd_addr;

    //--------------------------------------------------------------------------
    // Two-layer read controller
    //--------------------------------------------------------------------------

    controller_2layer #(
        .INPUT_WIDTH       (INPUT_WIDTH),
        .INPUT_HEIGHT      (INPUT_HEIGHT),
        .WEIGHT_WIDTH      (WEIGHT_WIDTH),
        .WEIGHT_HEIGHT     (WEIGHT_HEIGHT),
        .INPUT_ADDR_WIDTH  (INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH (WEIGHT_ADDR_WIDTH)
    ) u_controller (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        .i_start            (i_start),

        .i_line_rd_done     (o_line_rd_done),

        .o_input_rd_en      (w_ctrl_input_rd_en),
        .o_input_rd_addr    (w_ctrl_input_rd_addr),
        .o_input_zero_valid (w_ctrl_input_zero_valid),
        .o_input_line_done  (w_ctrl_input_line_done),

        .o_weight_rd_en     (w_ctrl_weight_rd_en),
        .o_weight_rd_addr   (w_ctrl_weight_rd_addr),

        .o_layer            (w_ctrl_layer),
        .o_done             (w_ctrl_done)
    );

    //--------------------------------------------------------------------------
    // Layer 1 activation BRAM
    //--------------------------------------------------------------------------

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (INPUT_SIZE),
        .ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .INIT_FILE  (INIT_INPUT_BRAM)
    ) u_input_bram (
        .clk        (i_clk),

        .wr_en      (1'b0),
        .wr_addr    ({INPUT_ADDR_WIDTH{1'b0}}),
        .wr_din     ({DATA_WIDTH{1'b0}}),

        .rd_en      (w_l1_input_rd_en),
        .rd_addr    (w_l1_input_rd_addr),
        .rd_valid   (w_l1_input_rd_valid),
        .rd_dout    (w_l1_input_rd_dout)
    );

    //--------------------------------------------------------------------------
    // Layer 1 weight BRAM: w_L1.txt
    //--------------------------------------------------------------------------

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (WEIGHT_SIZE),
        .ADDR_WIDTH (WEIGHT_ADDR_WIDTH),
        .INIT_FILE  (INIT_WEIGHT_BRAM)
    ) u_weight_l1_bram (
        .clk        (i_clk),

        .wr_en      (1'b0),
        .wr_addr    ({WEIGHT_ADDR_WIDTH{1'b0}}),
        .wr_din     ({DATA_WIDTH{1'b0}}),

        .rd_en      (w_l1_weight_rd_en),
        .rd_addr    (w_l1_weight_rd_addr),
        .rd_valid   (w_l1_weight_rd_valid),
        .rd_dout    (w_l1_weight_rd_dout)
    );

    //--------------------------------------------------------------------------
    // Intermediate ReLU BRAM: ReLU(layer 1 output)
    //--------------------------------------------------------------------------

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (OUTPUT_SIZE),
        .ADDR_WIDTH (OUTPUT_ADDR_WIDTH),
        .INIT_FILE  ("")
    ) u_relu_bram (
        .clk        (i_clk),

        .wr_en      (w_l1_output_valid),
        .wr_addr    (r_l1_relu_wr_addr),
        .wr_din     (w_l1_relu_output),

        .rd_en      (w_l2_input_rd_en),
        .rd_addr    (w_l2_input_rd_addr),
        .rd_valid   (w_l2_input_rd_valid),
        .rd_dout    (w_l2_input_rd_dout)
    );

    //--------------------------------------------------------------------------
    // Layer 2 weight BRAM: w_L2.txt
    //--------------------------------------------------------------------------

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (WEIGHT_SIZE),
        .ADDR_WIDTH (WEIGHT_ADDR_WIDTH),
        .INIT_FILE  (INIT_WEIGHT_L2_BRAM)
    ) u_weight_l2_bram (
        .clk        (i_clk),

        .wr_en      (1'b0),
        .wr_addr    ({WEIGHT_ADDR_WIDTH{1'b0}}),
        .wr_din     ({DATA_WIDTH{1'b0}}),

        .rd_en      (w_l2_weight_rd_en),
        .rd_addr    (w_l2_weight_rd_addr),
        .rd_valid   (w_l2_weight_rd_valid),
        .rd_dout    (w_l2_weight_rd_dout)
    );

    //--------------------------------------------------------------------------
    // Layer 1 convolution datapath
    //--------------------------------------------------------------------------

    TOP_prac1 #(
        .INPUT_WIDTH   (PADDED_INPUT_WIDTH),
        .INPUT_HEIGHT  (PADDED_INPUT_HEIGHT),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .WEIGHT_HEIGHT (WEIGHT_HEIGHT),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WIDTH    (PADDED_INPUT_WIDTH)
    ) u_conv_l1 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_line_done    ((w_ctrl_layer == LAYER_1) ? w_ctrl_input_line_done : 1'b0),

        .i_input_valid  (w_l1_input_valid),
        .i_input_data   (w_l1_input_data),

        .i_weight_valid (w_l1_weight_rd_valid),
        .i_weight_data  (w_l1_weight_rd_dout),

        .o_output_valid (w_l1_output_valid),
        .o_output       (w_l1_output),
        .o_line_rd_done (w_l1_line_rd_done)
    );

    //--------------------------------------------------------------------------
    // Layer 2 convolution datapath
    //--------------------------------------------------------------------------

    TOP_prac1 #(
        .INPUT_WIDTH   (PADDED_INPUT_WIDTH),
        .INPUT_HEIGHT  (PADDED_INPUT_HEIGHT),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .WEIGHT_HEIGHT (WEIGHT_HEIGHT),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WIDTH    (PADDED_INPUT_WIDTH)
    ) u_conv_l2 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_line_done    ((w_ctrl_layer == LAYER_2) ? w_ctrl_input_line_done : 1'b0),

        .i_input_valid  (w_l2_input_valid),
        .i_input_data   (w_l2_input_data),

        .i_weight_valid (w_l2_weight_rd_valid),
        .i_weight_data  (w_l2_weight_rd_dout),

        .o_output_valid (w_l2_output_valid),
        .o_output       (w_l2_output),
        .o_line_rd_done (w_l2_line_rd_done)
    );

    //--------------------------------------------------------------------------
    // Layer state, ReLU BRAM write address, and done tracking
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_l1_relu_wr_addr     <= {OUTPUT_ADDR_WIDTH{1'b0}};
            r_l1_output_cnt       <= {(OUTPUT_ADDR_WIDTH+1){1'b0}};
            r_l1_output_done      <= 1'b0;
            r_output_bram_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
            r_l2_output_cnt       <= {(OUTPUT_ADDR_WIDTH+1){1'b0}};
            r_done                <= 1'b0;
        end else begin
            if (!i_start) begin
                r_l1_relu_wr_addr     <= {OUTPUT_ADDR_WIDTH{1'b0}};
                r_l1_output_cnt       <= {(OUTPUT_ADDR_WIDTH+1){1'b0}};
                r_l1_output_done      <= 1'b0;
                r_output_bram_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
                r_l2_output_cnt       <= {(OUTPUT_ADDR_WIDTH+1){1'b0}};
                r_done                <= 1'b0;
            end else begin
                r_done <= 1'b0;
                
                if (w_l1_output_valid && !r_l1_output_done) begin
                    if (r_l1_relu_wr_addr == OUTPUT_SIZE - 1) begin
                        r_l1_relu_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
                    end else begin
                        r_l1_relu_wr_addr <= r_l1_relu_wr_addr + 1'b1;
                    end

                    if (r_l1_output_cnt == OUTPUT_SIZE - 1) begin
                        r_l1_output_cnt <= r_l1_output_cnt + 1'b1;
                        r_l1_output_done <= 1'b1;
                    end else begin
                        r_l1_output_cnt <= r_l1_output_cnt + 1'b1;
                    end
                end

                if (w_l2_output_valid && !r_done) begin
                    if (r_output_bram_wr_addr == OUTPUT_SIZE - 1) begin
                        r_output_bram_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
                    end else begin
                        r_output_bram_wr_addr <= r_output_bram_wr_addr + 1'b1;
                    end

                    if (r_l2_output_cnt == OUTPUT_SIZE - 1) begin
                        r_l2_output_cnt <= r_l2_output_cnt + 1'b1;
                        r_done          <= 1'b1;
                    end else begin
                        r_l2_output_cnt <= r_l2_output_cnt + 1'b1;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Final output BRAM
    //--------------------------------------------------------------------------

    simple_dual_port_bram #(
        .WIDTH      (2*DATA_WIDTH),
        .DEPTH      (OUTPUT_SIZE),
        .ADDR_WIDTH (OUTPUT_ADDR_WIDTH),
        .INIT_FILE  ("")
    ) u_output_bram (
        .clk        (i_clk),

        .wr_en      (w_l2_output_valid),
        .wr_addr    (r_output_bram_wr_addr),
        .wr_din     (w_l2_output),

        .rd_en      (1'b0),
        .rd_addr    ({OUTPUT_ADDR_WIDTH{1'b0}}),
        .rd_valid   (),
        .rd_dout    ()
    );

endmodule
