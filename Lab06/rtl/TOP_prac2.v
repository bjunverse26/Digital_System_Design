//==============================================================================
// File Name   : TOP_prac2.v
// Project     : Digital System Design - Lab06
// Author      : Beomjun Kim
// Description : Multi-channel output-stationary 3x3 convolution engine.
// Notes       : Each channel is streamed through the same spatial datapath;
//               partial sums are kept by output position and emitted on LAST_CH.
//==============================================================================

`timescale 1ns / 1ps

module TOP_prac2 #(
    parameter INPUT_WIDTH   = 5,
    parameter INPUT_HEIGHT  = 5,
    parameter WEIGHT_WIDTH  = 3,
    parameter WEIGHT_HEIGHT = 3
) (
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire [1:0]  i_ch,
    input  wire        i_line_done,
    input  wire        i_input_valid,
    input  wire [15:0] i_input_data,
    input  wire        i_weight_valid,
    input  wire [15:0] i_weight_data,

    output wire        o_output_valid,
    output wire [31:0] o_output,
    output wire        o_line_rd_done,
    output wire        o_ch_done
);

    // FSM states for channel input fill, compute, line refill, and channel done.
    localparam S_LOAD_FIRST = 2'd0;
    localparam S_CALC       = 2'd1;
    localparam S_LOAD_NEXT  = 2'd2;
    localparam S_CH_DONE    = 2'd3;

    localparam OUTPUT_WIDTH  = INPUT_WIDTH - WEIGHT_WIDTH + 1;
    localparam OUTPUT_HEIGHT = INPUT_HEIGHT - WEIGHT_HEIGHT + 1;
    localparam OUTPUT_SIZE   = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam LAST_CH       = 2'd2;

    reg [1:0]  r_state;
    reg        r_output_valid;
    reg [31:0] r_output;
    reg        r_line_rd_done;
    reg        r_ch_done;

    // Three single-channel input line buffers, five 16-bit pixels per row.
    reg [79:0] r_line [0:2];
    reg [3:0]  r_input_cnt;
    reg [1:0]  r_col_cnt;
    reg [1:0]  r_row_cnt;

    reg [15:0] r_weight [0:8];
    reg [3:0]  r_weight_cnt;
    // Output-stationary partial sums, one accumulator per output pixel.
    reg [31:0] r_psum [0:OUTPUT_SIZE-1];

    wire [3:0] w_out_idx;
    wire [31:0] w_mac;
    wire [31:0] w_accum;

    assign o_output_valid = r_output_valid;
    assign o_output       = r_output;
    assign o_line_rd_done = r_line_rd_done;
    assign o_ch_done      = r_ch_done;

    // Flatten the current output row/column into the partial-sum RAM index.
    assign w_out_idx = r_row_cnt * OUTPUT_WIDTH + r_col_cnt;

    // Current channel's 3x3 MAC result for the selected output column.
    assign w_mac =
        (r_col_cnt == 2'd0) ? (
            r_line[0][79:64] * r_weight[0] +
            r_line[0][63:48] * r_weight[1] +
            r_line[0][47:32] * r_weight[2] +
            r_line[1][79:64] * r_weight[3] +
            r_line[1][63:48] * r_weight[4] +
            r_line[1][47:32] * r_weight[5] +
            r_line[2][79:64] * r_weight[6] +
            r_line[2][63:48] * r_weight[7] +
            r_line[2][47:32] * r_weight[8]
        ) :
        (r_col_cnt == 2'd1) ? (
            r_line[0][63:48] * r_weight[0] +
            r_line[0][47:32] * r_weight[1] +
            r_line[0][31:16] * r_weight[2] +
            r_line[1][63:48] * r_weight[3] +
            r_line[1][47:32] * r_weight[4] +
            r_line[1][31:16] * r_weight[5] +
            r_line[2][63:48] * r_weight[6] +
            r_line[2][47:32] * r_weight[7] +
            r_line[2][31:16] * r_weight[8]
        ) : (
            r_line[0][47:32] * r_weight[0] +
            r_line[0][31:16] * r_weight[1] +
            r_line[0][15:0]  * r_weight[2] +
            r_line[1][47:32] * r_weight[3] +
            r_line[1][31:16] * r_weight[4] +
            r_line[1][15:0]  * r_weight[5] +
            r_line[2][47:32] * r_weight[6] +
            r_line[2][31:16] * r_weight[7] +
            r_line[2][15:0]  * r_weight[8]
        );

    // First channel initializes the psum; later channels accumulate into it.
    assign w_accum = (i_ch == 0) ? w_mac : r_psum[w_out_idx] + w_mac;

    integer i;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state        <= S_LOAD_FIRST;
            r_output_valid <= 1'b0;
            r_output       <= 32'd0;
            r_line_rd_done <= 1'b0;
            r_ch_done      <= 1'b0;
            r_input_cnt    <= 4'd0;
            r_col_cnt      <= 2'd0;
            r_row_cnt      <= 2'd0;
            r_weight_cnt   <= 4'd0;

            for (i = 0; i < 3; i = i + 1) begin
                r_line[i] <= 80'd0;
            end

            for (i = 0; i < 9; i = i + 1) begin
                r_weight[i] <= 16'd0;
                r_psum[i]   <= 32'd0;
            end
        end else begin
            r_output_valid <= 1'b0;
            r_output       <= 32'd0;
            r_line_rd_done <= 1'b0;
            r_ch_done      <= 1'b0;

            // Capture one channel's 3x3 weights.
            if (i_weight_valid && r_weight_cnt < 9) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt <= r_weight_cnt + 1'b1;
            end

            case (r_state)
                S_LOAD_FIRST: begin
                    if (i_input_valid) begin
                        // Fill the initial three rows for the current channel.
                        if (r_input_cnt < 5) begin
                            r_line[0] <= {r_line[0][63:0], i_input_data};
                        end
                        else if (r_input_cnt < 10) begin
                            r_line[1] <= {r_line[1][63:0], i_input_data};
                        end
                        else if (r_input_cnt < 15) begin
                            r_line[2] <= {r_line[2][63:0], i_input_data};
                        end

                        r_input_cnt <= r_input_cnt + 1'b1;
                    end

                    if (i_line_done) begin
                        r_state     <= S_CALC;
                        r_col_cnt   <= 2'd0;
                        r_row_cnt   <= 2'd0;
                        r_input_cnt <= 4'd0;
                    end
                end

                S_CALC: begin
                    // Keep the output pixel stationary while channel results accumulate.
                    r_psum[w_out_idx] <= w_accum;

                    if (i_ch == LAST_CH) begin
                        // Only the last channel produces externally visible output.
                        r_output_valid <= 1'b1;
                        r_output       <= w_accum;
                    end

                    if (r_col_cnt == OUTPUT_WIDTH - 1) begin
                        r_col_cnt <= 2'd0;

                        if (r_row_cnt == OUTPUT_HEIGHT - 1) begin
                            r_state <= S_CH_DONE;
                        end
                        else begin
                            // Request the next spatial input row for this channel.
                            r_row_cnt      <= r_row_cnt + 1'b1;
                            r_line_rd_done <= 1'b1;
                            r_input_cnt    <= 4'd0;
                            r_line[0]      <= r_line[1];
                            r_line[1]      <= r_line[2];
                            r_line[2]      <= 80'd0;
                            r_state        <= S_LOAD_NEXT;
                        end
                    end
                    else begin
                        r_col_cnt <= r_col_cnt + 1'b1;
                    end
                end

                S_LOAD_NEXT: begin
                    if (i_input_valid) begin
                        // Load the shifted-in bottom line.
                        r_line[2]   <= {r_line[2][63:0], i_input_data};
                        r_input_cnt <= r_input_cnt + 1'b1;
                    end

                    if (i_line_done) begin
                        r_state     <= S_CALC;
                        r_col_cnt   <= 2'd0;
                        r_input_cnt <= 4'd0;
                    end
                end

                S_CH_DONE: begin
                    // One-cycle pulse tells the testbench to advance i_ch.
                    r_ch_done    <= 1'b1;
                    r_state      <= S_LOAD_FIRST;
                    r_input_cnt  <= 4'd0;
                    r_col_cnt    <= 2'd0;
                    r_row_cnt    <= 2'd0;
                    r_weight_cnt <= 4'd0;

                    for (i = 0; i < 3; i = i + 1) begin
                        r_line[i] <= 80'd0;
                    end
                end

                default: begin
                    r_state <= S_LOAD_FIRST;
                end
            endcase
        end
    end

endmodule
