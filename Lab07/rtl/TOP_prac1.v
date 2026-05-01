//==============================================================================
// File Name   : TOP_prac1.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Single-channel 3x3 convolution engine for a 5x5 input image.
// Notes       : Three input lines are buffered, a 3x3 window is slid across
//               them, and the next line is requested after each output row.
//==============================================================================

`timescale 1ns / 1ps

module TOP_prac1 #(
    parameter INPUT_WIDTH   = 5,
    parameter INPUT_HEIGHT  = 5,
    parameter WEIGHT_WIDTH  = 3,
    parameter WEIGHT_HEIGHT = 3,
    parameter DATA_WIDTH    = 16,
    parameter LINE_WIDTH    = INPUT_WIDTH,
    parameter KERNEL_SIZE   = WEIGHT_HEIGHT
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,

    input  wire                         i_line_done,
    input  wire                         i_input_valid,
    input  wire signed [DATA_WIDTH-1:0] i_input_data,

    input  wire                         i_weight_valid,
    input  wire signed [DATA_WIDTH-1:0] i_weight_data,

    output wire                         o_output_valid,
    output wire signed [(2*DATA_WIDTH)-1:0] o_output,
    output wire                         o_line_rd_done
);

    localparam OUTPUT_WIDTH  = INPUT_WIDTH  - WEIGHT_WIDTH  + 1;
    localparam OUTPUT_HEIGHT = INPUT_HEIGHT - WEIGHT_HEIGHT + 1;
    localparam WEIGHT_SIZE   = WEIGHT_WIDTH * WEIGHT_HEIGHT;

    reg                         r_calc_run;
    reg [1:0]                   r_line_col;
    reg [1:0]                   r_out_row;
    reg [3:0]                   r_weight_cnt;
    reg signed [DATA_WIDTH-1:0] r_weight [0:WEIGHT_SIZE-1];

    wire                        w_last_col;
    wire                        w_last_row;
    wire                        w_calc_valid;
    wire                        w_line_shift;

    wire signed [DATA_WIDTH-1:0] w_window_00;
    wire signed [DATA_WIDTH-1:0] w_window_01;
    wire signed [DATA_WIDTH-1:0] w_window_02;
    wire signed [DATA_WIDTH-1:0] w_window_10;
    wire signed [DATA_WIDTH-1:0] w_window_11;
    wire signed [DATA_WIDTH-1:0] w_window_12;
    wire signed [DATA_WIDTH-1:0] w_window_20;
    wire signed [DATA_WIDTH-1:0] w_window_21;
    wire signed [DATA_WIDTH-1:0] w_window_22;

    assign w_last_col     = r_calc_run && (r_line_col == OUTPUT_WIDTH - 1);
    assign w_last_row     = (r_out_row == OUTPUT_HEIGHT - 1);
    assign w_calc_valid   = r_calc_run;
    assign w_line_shift   = w_last_col && !w_last_row;
    assign o_line_rd_done = w_line_shift;

    integer i;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_calc_run   <= 1'b0;
            r_line_col   <= 2'd0;
            r_out_row    <= 2'd0;
            r_weight_cnt <= 4'd0;

            for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin
                r_weight[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (i_weight_valid && (r_weight_cnt < WEIGHT_SIZE)) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt           <= r_weight_cnt + 1'b1;
            end

            if (!r_calc_run && i_line_done) begin
                r_calc_run <= 1'b1;
                r_line_col <= 2'd0;
            end else if (r_calc_run) begin
                if (r_line_col == OUTPUT_WIDTH - 1) begin
                    r_calc_run <= 1'b0;
                    r_line_col <= 2'd0;

                    if (r_out_row == OUTPUT_HEIGHT - 1) begin
                        r_out_row <= 2'd0;
                    end else begin
                        r_out_row <= r_out_row + 1'b1;
                    end
                end else begin
                    r_line_col <= r_line_col + 1'b1;
                end
            end
        end
    end

    line_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WIDTH (LINE_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE)
    ) u_line_buffer (
        .i_clk        (i_clk),
        .i_rstn       (i_rstn),
        .i_input_valid(i_input_valid),
        .i_input_data (i_input_data),
        .i_line_col   (r_line_col),
        .i_line_shift (w_line_shift),
        .o_window_00  (w_window_00),
        .o_window_01  (w_window_01),
        .o_window_02  (w_window_02),
        .o_window_10  (w_window_10),
        .o_window_11  (w_window_11),
        .o_window_12  (w_window_12),
        .o_window_20  (w_window_20),
        .o_window_21  (w_window_21),
        .o_window_22  (w_window_22)
    );

    pe #(
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_pe (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_line_done    (w_calc_valid),
        .i_window_00    (w_window_00),
        .i_window_01    (w_window_01),
        .i_window_02    (w_window_02),
        .i_window_10    (w_window_10),
        .i_window_11    (w_window_11),
        .i_window_12    (w_window_12),
        .i_window_20    (w_window_20),
        .i_window_21    (w_window_21),
        .i_window_22    (w_window_22),
        .i_weight_00    (r_weight[0]),
        .i_weight_01    (r_weight[1]),
        .i_weight_02    (r_weight[2]),
        .i_weight_10    (r_weight[3]),
        .i_weight_11    (r_weight[4]),
        .i_weight_12    (r_weight[5]),
        .i_weight_20    (r_weight[6]),
        .i_weight_21    (r_weight[7]),
        .i_weight_22    (r_weight[8]),
        .o_output_data  (o_output),
        .o_output_valid (o_output_valid)
    );

endmodule
