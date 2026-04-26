`timescale 1ns / 1ps

// TOP prac1
// Single-channel 3x3 convolution engine for a 5x5 input image.
// The DUT buffers three input lines, slides a 3x3 window across them, and
// requests the next input line after each output row is produced.
module TOP_prac1 #(
    parameter INPUT_WIDTH = 5,
    parameter INPUT_HEIGHT = 5,
    parameter WEIGHT_WIDTH = 3,
    parameter WEIGHT_HEIGHT = 3
) (
    input               i_clk,
    input               i_rstn,
    input               i_line_done,
    input               i_input_valid,
    input [15:0]        i_input_data,
    input               i_weight_valid,
    input [15:0]        i_weight_data,

    output              o_output_valid,
    output [31:0]       o_output,
    output              o_line_rd_done
);

    // FSM states for initial fill, window computation, line refill, and done.
    localparam S_LOAD_FIRST = 2'd0;
    localparam S_CALC       = 2'd1;
    localparam S_LOAD_NEXT  = 2'd2;
    localparam S_DONE       = 2'd3;

    reg [1:0]  r_state;
    reg        r_output_valid;
    reg [31:0] r_output;
    reg        r_line_rd_done;

    // Three 5-pixel line buffers. Each pixel is 16 bits, so one line is 80 bits.
    reg [79:0] r_line [0:2];
    reg [3:0]  r_input_cnt;
    reg [1:0]  r_col_cnt;
    reg [1:0]  r_row_cnt;

    // Stored 3x3 kernel weights in row-major order.
    reg [15:0] r_weight [0:8];
    reg [3:0]  r_weight_cnt;

    assign o_output_valid = r_output_valid;
    assign o_output       = r_output;
    assign o_line_rd_done = r_line_rd_done;

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
                r_line[i] <= 80'd0;
            end

            for (i = 0; i < 9; i = i + 1) begin
                r_weight[i] <= 16'd0;
            end
        end
        else begin
            r_output_valid <= 1'b0;
            r_line_rd_done <= 1'b0;
            r_output       <= 32'd0;

            // Weight stream arrives before input data; capture all 9 weights.
            if (i_weight_valid && r_weight_cnt < 9) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt <= r_weight_cnt + 1'b1;
            end

            case (r_state)
                S_LOAD_FIRST: begin
                    if (i_input_valid) begin
                        // Fill the first three input rows before any convolution.
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
                        // Testbench has completed the current input burst.
                        r_state     <= S_CALC;
                        r_col_cnt   <= 2'd0;
                        r_input_cnt <= 4'd0;
                    end
                end

                S_CALC: begin
                    // Emit one output per cycle for the current output row.
                    r_output_valid <= 1'b1;

                    case (r_col_cnt)
                        2'd0: begin
                            r_output <=
                                r_line[0][79:64] * r_weight[0] +
                                r_line[0][63:48] * r_weight[1] +
                                r_line[0][47:32] * r_weight[2] +
                                r_line[1][79:64] * r_weight[3] +
                                r_line[1][63:48] * r_weight[4] +
                                r_line[1][47:32] * r_weight[5] +
                                r_line[2][79:64] * r_weight[6] +
                                r_line[2][63:48] * r_weight[7] +
                                r_line[2][47:32] * r_weight[8];
                        end
                        2'd1: begin
                            r_output <=
                                r_line[0][63:48] * r_weight[0] +
                                r_line[0][47:32] * r_weight[1] +
                                r_line[0][31:16] * r_weight[2] +
                                r_line[1][63:48] * r_weight[3] +
                                r_line[1][47:32] * r_weight[4] +
                                r_line[1][31:16] * r_weight[5] +
                                r_line[2][63:48] * r_weight[6] +
                                r_line[2][47:32] * r_weight[7] +
                                r_line[2][31:16] * r_weight[8];
                        end
                        default: begin
                            r_output <=
                                r_line[0][47:32] * r_weight[0] +
                                r_line[0][31:16] * r_weight[1] +
                                r_line[0][15:0]  * r_weight[2] +
                                r_line[1][47:32] * r_weight[3] +
                                r_line[1][31:16] * r_weight[4] +
                                r_line[1][15:0]  * r_weight[5] +
                                r_line[2][47:32] * r_weight[6] +
                                r_line[2][31:16] * r_weight[7] +
                                r_line[2][15:0]  * r_weight[8];
                        end
                    endcase

                    if (r_col_cnt == 2) begin
                        // End of one output row.
                        r_col_cnt <= 2'd0;

                        if (r_row_cnt == 2) begin
                            r_state <= S_DONE;
                        end
                        else begin
                            // Advance the line buffer and request one new input row.
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
                        // Load the new bottom row after the two older rows shift up.
                        r_line[2]   <= {r_line[2][63:0], i_input_data};
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
