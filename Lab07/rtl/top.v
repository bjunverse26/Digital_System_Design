//==============================================================================
// File Name   : top.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Top-level wrapper for the Lab07 single-channel 3x3 convolution
//               system.
// Notes       : Instantiates the controller, activation BRAM, weight BRAM,
//               TOP_prac1 convolution datapath, and output BRAM.
//==============================================================================

`timescale 1ns / 1ps

module top #(
    parameter INPUT_WIDTH      = 5,
    parameter INPUT_HEIGHT     = 5,
    parameter WEIGHT_WIDTH     = 3,
    parameter WEIGHT_HEIGHT    = 3,
    parameter DATA_WIDTH       = 16,
    parameter OUTPUT_WIDTH     = INPUT_WIDTH - WEIGHT_WIDTH + 1,
    parameter OUTPUT_HEIGHT    = INPUT_HEIGHT - WEIGHT_HEIGHT + 1,
    parameter INPUT_SIZE       = INPUT_WIDTH * INPUT_HEIGHT,
    parameter WEIGHT_SIZE      = WEIGHT_WIDTH * WEIGHT_HEIGHT,
    parameter OUTPUT_SIZE      = OUTPUT_WIDTH * OUTPUT_HEIGHT,
    parameter INPUT_ADDR_WIDTH = $clog2(INPUT_SIZE),
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_SIZE),
    parameter OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_SIZE),
    parameter INIT_INPUT_BRAM  = "C:/Users/rlaqj/Project/Digital_System_Design/Lab07/rtl/init_file/act.txt",
    parameter INIT_WEIGHT_BRAM = "C:/Users/rlaqj/Project/Digital_System_Design/Lab07/rtl/init_file/w_L1.txt"
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,
    input  wire                         i_start,
    output wire                         o_done,
    output wire                         o_output_valid,
    output wire signed [(2*DATA_WIDTH)-1:0] o_output,
    output wire                         o_line_rd_done
);

    wire                         w_input_bram_rd_en;
    wire [INPUT_ADDR_WIDTH-1:0]  w_input_bram_rd_addr;
    wire                         w_input_bram_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_input_bram_rd_dout;
    wire                         w_input_bram_rd_line_done;

    wire                         w_weight_bram_rd_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] w_weight_bram_rd_addr;
    wire                         w_weight_bram_rd_valid;
    wire signed [DATA_WIDTH-1:0] w_weight_bram_rd_dout;

    reg  [OUTPUT_ADDR_WIDTH-1:0] r_output_bram_wr_addr;

    assign w_input_bram_rd_line_done = !w_input_bram_rd_en && w_input_bram_rd_valid;

    controller #(
        .INPUT_WIDTH       (INPUT_WIDTH),
        .INPUT_HEIGHT      (INPUT_HEIGHT),
        .WEIGHT_WIDTH      (WEIGHT_WIDTH),
        .WEIGHT_HEIGHT     (WEIGHT_HEIGHT),
        .INPUT_ADDR_WIDTH  (INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH (WEIGHT_ADDR_WIDTH)
    ) u_controller (
        .i_clk             (i_clk),
        .i_rstn            (i_rstn),
        .i_start           (i_start),
        .i_line_rd_done    (o_line_rd_done),
        .o_input_rd_en     (w_input_bram_rd_en),
        .o_input_rd_addr   (w_input_bram_rd_addr),
        .o_weight_rd_en    (w_weight_bram_rd_en),
        .o_weight_rd_addr  (w_weight_bram_rd_addr),
        .o_done            (o_done)
    );

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (INPUT_SIZE),
        .ADDR_WIDTH (INPUT_ADDR_WIDTH),
        .INIT_FILE  (INIT_INPUT_BRAM)
    ) u_input_bram (
        .clk        (i_clk),
        .wr_en      (1'b0),
        .rd_en      (w_input_bram_rd_en),
        .wr_addr    ({INPUT_ADDR_WIDTH{1'b0}}),
        .rd_addr    (w_input_bram_rd_addr),
        .wr_din     ({DATA_WIDTH{1'b0}}),
        .rd_valid   (w_input_bram_rd_valid),
        .rd_dout    (w_input_bram_rd_dout)
    );

    simple_dual_port_bram #(
        .WIDTH      (DATA_WIDTH),
        .DEPTH      (WEIGHT_SIZE),
        .ADDR_WIDTH (WEIGHT_ADDR_WIDTH),
        .INIT_FILE  (INIT_WEIGHT_BRAM)
    ) u_weight_bram (
        .clk        (i_clk),
        .wr_en      (1'b0),
        .rd_en      (w_weight_bram_rd_en),
        .wr_addr    ({WEIGHT_ADDR_WIDTH{1'b0}}),
        .rd_addr    (w_weight_bram_rd_addr),
        .wr_din     ({DATA_WIDTH{1'b0}}),
        .rd_valid   (w_weight_bram_rd_valid),
        .rd_dout    (w_weight_bram_rd_dout)
    );

    TOP_prac1 #(
        .INPUT_WIDTH   (INPUT_WIDTH),
        .INPUT_HEIGHT  (INPUT_HEIGHT),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .WEIGHT_HEIGHT (WEIGHT_HEIGHT),
        .DATA_WIDTH    (DATA_WIDTH)
    ) u_conv (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_line_done    (w_input_bram_rd_line_done),
        .i_input_valid  (w_input_bram_rd_valid),
        .i_input_data   (w_input_bram_rd_dout),
        .i_weight_valid (w_weight_bram_rd_valid),
        .i_weight_data  (w_weight_bram_rd_dout),
        .o_output_valid (o_output_valid),
        .o_output       (o_output),
        .o_line_rd_done (o_line_rd_done)
    );

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_output_bram_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
        end else if (o_output_valid) begin
            if (r_output_bram_wr_addr == OUTPUT_SIZE - 1) begin
                r_output_bram_wr_addr <= {OUTPUT_ADDR_WIDTH{1'b0}};
            end else begin
                r_output_bram_wr_addr <= r_output_bram_wr_addr + 1'b1;
            end
        end
    end

    simple_dual_port_bram #(
        .WIDTH      (2*DATA_WIDTH),
        .DEPTH      (OUTPUT_SIZE),
        .ADDR_WIDTH (OUTPUT_ADDR_WIDTH),
        .INIT_FILE  ("")
    ) u_output_bram (
        .clk        (i_clk),
        .wr_en      (o_output_valid),
        .rd_en      (1'b0),
        .wr_addr    (r_output_bram_wr_addr),
        .rd_addr    ({OUTPUT_ADDR_WIDTH{1'b0}}),
        .wr_din     (o_output),
        .rd_valid   (),
        .rd_dout    ()
    );

endmodule
