//==============================================================================
// File Name   : line_buffer.v
// Project     : Digital System Design - Lab06
// Author      : Beomjun Kim
// Description : 3-line sliding window buffer for 3x3 convolution.
// Notes       : - Accepts one signed pixel per valid cycle.
//               - Maintains three packed image rows.
//               - Exposes a combinational 3x3 window selected by i_line_col.
//               - i_line_shift and i_input_valid must not overlap.
//==============================================================================

`timescale 1ns / 1ps

module line_buffer #(
    parameter DATA_WIDTH  = 16,
    parameter LINE_WIDTH  = 5,
    parameter KERNEL_SIZE = 3,
    parameter LINE_COL_WIDTH = (LINE_WIDTH > KERNEL_SIZE) ?
                               $clog2(LINE_WIDTH - KERNEL_SIZE + 1) : 1
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,
    input  wire                         i_clear,

    // Input pixel stream.
    input  wire                         i_input_valid,
    input  wire signed [DATA_WIDTH-1:0] i_input_data,

    // Window column selector and row-shift control.
    input  wire [LINE_COL_WIDTH-1:0]    i_line_col,
    input  wire                         i_line_shift,

    // Current 3x3 window. Outputs are combinational from internal row buffers.
    output reg signed [DATA_WIDTH-1:0]  o_window_00,
    output reg signed [DATA_WIDTH-1:0]  o_window_01,
    output reg signed [DATA_WIDTH-1:0]  o_window_02,
    output reg signed [DATA_WIDTH-1:0]  o_window_10,
    output reg signed [DATA_WIDTH-1:0]  o_window_11,
    output reg signed [DATA_WIDTH-1:0]  o_window_12,
    output reg signed [DATA_WIDTH-1:0]  o_window_20,
    output reg signed [DATA_WIDTH-1:0]  o_window_21,
    output reg signed [DATA_WIDTH-1:0]  o_window_22
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam LINE_BITS = DATA_WIDTH * LINE_WIDTH;
    localparam CNT_WIDTH = $clog2((LINE_WIDTH * KERNEL_SIZE) + 1);

    //--------------------------------------------------------------------------
    // Internal storage
    //--------------------------------------------------------------------------

    // Packed line buffers. r_line[0] is the top row of the active window.
    reg [LINE_BITS-1:0] r_line [0:KERNEL_SIZE-1];

    // Pixel count within the active 3-line buffer context.
    reg [CNT_WIDTH-1:0] r_cnt;

    integer i;

    //--------------------------------------------------------------------------
    // Packed-row pixel extraction
    //--------------------------------------------------------------------------

    function signed [DATA_WIDTH-1:0] get_pixel;
        input [LINE_BITS-1:0] line;
        input integer         col;
        begin
            get_pixel = line[((LINE_WIDTH - 1 - col) * DATA_WIDTH) +: DATA_WIDTH];
        end
    endfunction

    //--------------------------------------------------------------------------
    // Line-buffer update
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_cnt <= {CNT_WIDTH{1'b0}};

            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                r_line[i] <= {LINE_BITS{1'b0}};
            end
        end else begin
            if (i_clear) begin
                r_cnt <= {CNT_WIDTH{1'b0}};

                for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    r_line[i] <= {LINE_BITS{1'b0}};
                end
            end
            // Shift active 3-line window up by one row.
            // New pixels are loaded into r_line[2] after this cycle.
            else if (i_line_shift) begin
                r_line[0] <= r_line[1];
                r_line[1] <= r_line[2];
                r_line[2] <= {LINE_BITS{1'b0}};

                r_cnt <= LINE_WIDTH * (KERNEL_SIZE - 1);
            end

            // Load one pixel into the row selected by r_cnt.
            else if (i_input_valid) begin
                if (r_cnt < LINE_WIDTH) begin
                    r_line[0] <= {r_line[0][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end else if (r_cnt < (LINE_WIDTH * 2)) begin
                    r_line[1] <= {r_line[1][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end else if (r_cnt < (LINE_WIDTH * KERNEL_SIZE)) begin
                    r_line[2] <= {r_line[2][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end

                if (r_cnt < (LINE_WIDTH * KERNEL_SIZE)) begin
                    r_cnt <= r_cnt + 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // 3x3 window selection
    //--------------------------------------------------------------------------

    always @(*) begin
        o_window_00 = get_pixel(r_line[0], i_line_col + 0);
        o_window_01 = get_pixel(r_line[0], i_line_col + 1);
        o_window_02 = get_pixel(r_line[0], i_line_col + 2);

        o_window_10 = get_pixel(r_line[1], i_line_col + 0);
        o_window_11 = get_pixel(r_line[1], i_line_col + 1);
        o_window_12 = get_pixel(r_line[1], i_line_col + 2);

        o_window_20 = get_pixel(r_line[2], i_line_col + 0);
        o_window_21 = get_pixel(r_line[2], i_line_col + 1);
        o_window_22 = get_pixel(r_line[2], i_line_col + 2);
    end

endmodule
