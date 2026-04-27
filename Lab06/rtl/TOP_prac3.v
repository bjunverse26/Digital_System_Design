`timescale 1ns / 1ps

// TOP prac3
// Channel-parallel 3x3 convolution engine.
// Each 48-bit input/weight word packs three 16-bit channels, so the channel
// reduction is performed in the same cycle as the spatial 3x3 MAC.
module TOP_prac3 #(
    parameter INPUT_WIDTH = 5,
    parameter INPUT_HEIGHT = 5,
    parameter WEIGHT_WIDTH = 3,
    parameter WEIGHT_HEIGHT = 3
) (
    input wire               i_clk,
    input wire               i_rstn,
    input wire               i_line_done,
    input wire               i_input_valid,
    input wire [47:0]        i_input_data,
    input wire               i_weight_valid,
    input wire [47:0]        i_weight_data,

    output wire              o_output_valid,
    output wire [31:0]       o_output,
    output wire              o_line_rd_done
);

    // FSM states mirror TOP_prac1, but each pixel contains three channels.
    localparam S_LOAD_FIRST = 2'd0;
    localparam S_CALC       = 2'd1;
    localparam S_LOAD_NEXT  = 2'd2;
    localparam S_DONE       = 2'd3;

    localparam OUTPUT_WIDTH  = INPUT_WIDTH - WEIGHT_WIDTH + 1;
    localparam OUTPUT_HEIGHT = INPUT_HEIGHT - WEIGHT_HEIGHT + 1;

    reg [1:0]  r_state;
    reg        r_output_valid;
    reg [31:0] r_output;
    reg        r_line_rd_done;

    // Three packed line buffers. Each row stores 5 pixels x 48 bits.
    reg [239:0] r_line [0:2];
    reg [3:0]   r_input_cnt;
    reg [1:0]   r_col_cnt;
    reg [1:0]   r_row_cnt;

    // Packed 3x3 weights in row-major order, three channels per entry.
    reg [47:0] r_weight [0:8];
    reg [3:0]  r_weight_cnt;

    assign o_output_valid = r_output_valid;
    assign o_output       = r_output;
    assign o_line_rd_done = r_line_rd_done;

    function [47:0] get_pixel;
        input [239:0] line;
        input [2:0]   col;
        begin
            case (col)
                // Pixel 0 is kept in the most-significant slice after shift-in.
                3'd0: get_pixel = line[239:192];
                3'd1: get_pixel = line[191:144];
                3'd2: get_pixel = line[143:96];
                3'd3: get_pixel = line[95:48];
                default: get_pixel = line[47:0];
            endcase
        end
    endfunction

    function [31:0] dot3;
        input [47:0] act;
        input [47:0] weight;
        begin
            // Channel-wise dot product for one spatial kernel position.
            dot3 =
                act[15:0]  * weight[15:0] +
                act[31:16] * weight[31:16] +
                act[47:32] * weight[47:32];
        end
    endfunction

    wire [2:0] w_col0 = r_col_cnt;
    wire [2:0] w_col1 = r_col_cnt + 1'b1;
    wire [2:0] w_col2 = r_col_cnt + 2'd2;

    // Full 3x3x3 MAC: nine spatial positions, three channels each.
    wire [31:0] w_mac =
        dot3(get_pixel(r_line[0], w_col0), r_weight[0]) +
        dot3(get_pixel(r_line[0], w_col1), r_weight[1]) +
        dot3(get_pixel(r_line[0], w_col2), r_weight[2]) +
        dot3(get_pixel(r_line[1], w_col0), r_weight[3]) +
        dot3(get_pixel(r_line[1], w_col1), r_weight[4]) +
        dot3(get_pixel(r_line[1], w_col2), r_weight[5]) +
        dot3(get_pixel(r_line[2], w_col0), r_weight[6]) +
        dot3(get_pixel(r_line[2], w_col1), r_weight[7]) +
        dot3(get_pixel(r_line[2], w_col2), r_weight[8]);

    integer i;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state        <= S_LOAD_FIRST;
            r_output_valid <= 1'b0;
            r_output       <= 32'd0;
            r_line_rd_done <= 1'b0;
            r_input_cnt    <= 4'd0;
            r_col_cnt      <= 2'd0;
            r_row_cnt      <= 2'd0;
            r_weight_cnt   <= 4'd0;

            for (i = 0; i < 3; i = i + 1) begin
                r_line[i] <= 240'd0;
            end

            for (i = 0; i < 9; i = i + 1) begin
                r_weight[i] <= 48'd0;
            end
        end
        else begin
            r_output_valid <= 1'b0;
            r_line_rd_done <= 1'b0;
            r_output       <= 32'd0;

            // Capture the packed 3-channel kernel.
            if (i_weight_valid && r_weight_cnt < 9) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt <= r_weight_cnt + 1'b1;
            end

            case (r_state)
                S_LOAD_FIRST: begin
                    if (i_input_valid) begin
                        // Fill the first three packed input rows.
                        if (r_input_cnt < 5) begin
                            r_line[0] <= {r_line[0][191:0], i_input_data};
                        end
                        else if (r_input_cnt < 10) begin
                            r_line[1] <= {r_line[1][191:0], i_input_data};
                        end
                        else if (r_input_cnt < 15) begin
                            r_line[2] <= {r_line[2][191:0], i_input_data};
                        end

                        r_input_cnt <= r_input_cnt + 1'b1;
                    end

                    if (i_line_done) begin
                        r_state     <= S_CALC;
                        r_col_cnt   <= 2'd0;
                        r_input_cnt <= 4'd0;
                    end
                end

                S_CALC: begin
                    // Emit one spatial output per cycle; channel sum is already inside w_mac.
                    r_output_valid <= 1'b1;
                    r_output       <= w_mac;

                    if (r_col_cnt == OUTPUT_WIDTH - 1) begin
                        r_col_cnt <= 2'd0;

                        if (r_row_cnt == OUTPUT_HEIGHT - 1) begin
                            r_state <= S_DONE;
                        end
                        else begin
                            // Shift the line buffer and request one new packed row.
                            r_row_cnt      <= r_row_cnt + 1'b1;
                            r_line_rd_done <= 1'b1;
                            r_input_cnt    <= 4'd0;
                            r_line[0]      <= r_line[1];
                            r_line[1]      <= r_line[2];
                            r_line[2]      <= 240'd0;
                            r_state        <= S_LOAD_NEXT;
                        end
                    end
                    else begin
                        r_col_cnt <= r_col_cnt + 1'b1;
                    end
                end

                S_LOAD_NEXT: begin
                    if (i_input_valid) begin
                        // Load the next packed bottom row.
                        r_line[2]   <= {r_line[2][191:0], i_input_data};
                        r_input_cnt <= r_input_cnt + 1'b1;
                    end

                    if (i_line_done) begin
                        r_state     <= S_CALC;
                        r_col_cnt   <= 2'd0;
                        r_input_cnt <= 4'd0;
                    end
                end

                S_DONE: begin
                    r_state <= S_DONE;
                end

                default: begin
                    r_state <= S_LOAD_FIRST;
                end
            endcase
        end
    end

endmodule
