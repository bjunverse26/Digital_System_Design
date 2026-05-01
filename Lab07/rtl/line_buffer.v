//==============================================================================
// File Name   : line_buffer.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : 3-line buffer for generating a sliding 3x3 window from
//               streaming input pixel data.
// Notes       : Input pixels are stored into three line buffers. The selected
//               3x3 window is extracted according to i_line_col, and the line
//               buffers are shifted when i_line_shift is asserted.
//==============================================================================

`timescale 1ns / 1ps

module line_buffer #(
    parameter DATA_WIDTH  = 16,
    parameter LINE_WIDTH  = 5,
    parameter KERNEL_SIZE = 3
) (
    input  wire                  i_clk,
    input  wire                  i_rstn,

    input  wire                  i_input_valid,
    input  wire signed [DATA_WIDTH-1:0] i_input_data,

    input  wire [1:0]            i_line_col,
    input  wire                  i_line_shift,

    output reg signed [DATA_WIDTH-1:0] o_window_00,
    output reg signed [DATA_WIDTH-1:0] o_window_01,
    output reg signed [DATA_WIDTH-1:0] o_window_02,
    output reg signed [DATA_WIDTH-1:0] o_window_10,
    output reg signed [DATA_WIDTH-1:0] o_window_11,
    output reg signed [DATA_WIDTH-1:0] o_window_12,
    output reg signed [DATA_WIDTH-1:0] o_window_20,
    output reg signed [DATA_WIDTH-1:0] o_window_21,
    output reg signed [DATA_WIDTH-1:0] o_window_22
);

    // Total bit width of one buffered image line.
    localparam LINE_BITS = DATA_WIDTH * LINE_WIDTH;
    localparam CNT_WIDTH = $clog2((LINE_WIDTH * KERNEL_SIZE) + 1);

    // Three line buffers used to build a 3x3 convolution window.
    reg [LINE_BITS-1:0] r_line [0:KERNEL_SIZE-1];

    // Counts how many input pixels have been stored into the line buffers.
    reg [CNT_WIDTH-1:0] r_cnt;

    integer i;

    //--------------------------------------------------------------------------
    // Return one pixel from a packed line buffer.
    // Column 0 corresponds to the leftmost pixel stored in the line.
    //--------------------------------------------------------------------------
    function signed [DATA_WIDTH-1:0] get_pixel;
        input [LINE_BITS-1:0] line;
        input [2:0]           col;
        begin
            get_pixel = line[((LINE_WIDTH - 1 - col) * DATA_WIDTH) +: DATA_WIDTH];
        end
    endfunction

    //--------------------------------------------------------------------------
    // Sequential line-buffer control.
    // - Reset clears all line buffers and the input counter.
    // - i_line_shift moves line 1 to line 0, line 2 to line 1, and clears line 2.
    // - i_input_valid shifts new input pixels into the selected line buffer.
    //--------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_cnt <= {CNT_WIDTH{1'b0}};

            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                r_line[i] <= {LINE_BITS{1'b0}};
            end
        end else begin
            if (i_line_shift) begin
                // Move the two lower rows upward and clear the new bottom row.
                r_line[0] <= r_line[1];
                r_line[1] <= r_line[2];
                r_line[2] <= {LINE_BITS{1'b0}};

                // Continue loading from the third line position after shift.
                r_cnt     <= LINE_WIDTH * (KERNEL_SIZE - 1);
            end else if (i_input_valid) begin
                // Fill the first input line.
                if (r_cnt < LINE_WIDTH) begin
                    r_line[0] <= {r_line[0][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end
                // Fill the second input line.
                else if (r_cnt < (LINE_WIDTH * 2)) begin
                    r_line[1] <= {r_line[1][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end
                // Fill the third input line.
                else if (r_cnt < (LINE_WIDTH * KERNEL_SIZE)) begin
                    r_line[2] <= {r_line[2][LINE_BITS-DATA_WIDTH-1:0], i_input_data};
                end

                // Stop incrementing after all three line buffers are full.
                if (r_cnt < (LINE_WIDTH * KERNEL_SIZE)) begin
                    r_cnt <= r_cnt + 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Combinational 3x3 window selection.
    // i_line_col selects which horizontal 3-pixel window is exposed from
    // the three buffered lines.
    //--------------------------------------------------------------------------
    always @(*) begin
        case (i_line_col)
            2'd0: begin
                // Window columns 0, 1, and 2.
                o_window_00 = get_pixel(r_line[0], 3'd0);
                o_window_01 = get_pixel(r_line[0], 3'd1);
                o_window_02 = get_pixel(r_line[0], 3'd2);
                o_window_10 = get_pixel(r_line[1], 3'd0);
                o_window_11 = get_pixel(r_line[1], 3'd1);
                o_window_12 = get_pixel(r_line[1], 3'd2);
                o_window_20 = get_pixel(r_line[2], 3'd0);
                o_window_21 = get_pixel(r_line[2], 3'd1);
                o_window_22 = get_pixel(r_line[2], 3'd2);
            end

            2'd1: begin
                // Window columns 1, 2, and 3.
                o_window_00 = get_pixel(r_line[0], 3'd1);
                o_window_01 = get_pixel(r_line[0], 3'd2);
                o_window_02 = get_pixel(r_line[0], 3'd3);
                o_window_10 = get_pixel(r_line[1], 3'd1);
                o_window_11 = get_pixel(r_line[1], 3'd2);
                o_window_12 = get_pixel(r_line[1], 3'd3);
                o_window_20 = get_pixel(r_line[2], 3'd1);
                o_window_21 = get_pixel(r_line[2], 3'd2);
                o_window_22 = get_pixel(r_line[2], 3'd3);
            end

            2'd2: begin
                // Window columns 2, 3, and 4.
                o_window_00 = get_pixel(r_line[0], 3'd2);
                o_window_01 = get_pixel(r_line[0], 3'd3);
                o_window_02 = get_pixel(r_line[0], 3'd4);
                o_window_10 = get_pixel(r_line[1], 3'd2);
                o_window_11 = get_pixel(r_line[1], 3'd3);
                o_window_12 = get_pixel(r_line[1], 3'd4);
                o_window_20 = get_pixel(r_line[2], 3'd2);
                o_window_21 = get_pixel(r_line[2], 3'd3);
                o_window_22 = get_pixel(r_line[2], 3'd4);
            end

            default: begin
                // Invalid column selection returns a zero-filled window.
                o_window_00 = {DATA_WIDTH{1'b0}};
                o_window_01 = {DATA_WIDTH{1'b0}};
                o_window_02 = {DATA_WIDTH{1'b0}};
                o_window_10 = {DATA_WIDTH{1'b0}};
                o_window_11 = {DATA_WIDTH{1'b0}};
                o_window_12 = {DATA_WIDTH{1'b0}};
                o_window_20 = {DATA_WIDTH{1'b0}};
                o_window_21 = {DATA_WIDTH{1'b0}};
                o_window_22 = {DATA_WIDTH{1'b0}};
            end
        endcase
    end

endmodule
