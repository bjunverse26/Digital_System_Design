//==============================================================================
// File Name   : pe.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Parameterized 3x3 convolution processing element.
// Notes       : Performs nine parallel multiplications followed by a pipelined
//               adder tree. Output valid is delayed to match pipeline latency.
//==============================================================================

`timescale 1ns / 1ps

module pe #(
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH  = 16
)(
    input wire                          i_clk,
    input wire                          i_rstn,

    input wire                          i_line_done,

    input wire signed [DATA_WIDTH-1:0]  i_window_00,
    input wire signed [DATA_WIDTH-1:0]  i_window_01,
    input wire signed [DATA_WIDTH-1:0]  i_window_02,
    input wire signed [DATA_WIDTH-1:0]  i_window_10,
    input wire signed [DATA_WIDTH-1:0]  i_window_11,
    input wire signed [DATA_WIDTH-1:0]  i_window_12,
    input wire signed [DATA_WIDTH-1:0]  i_window_20,
    input wire signed [DATA_WIDTH-1:0]  i_window_21,
    input wire signed [DATA_WIDTH-1:0]  i_window_22,

    input wire signed [DATA_WIDTH-1:0]  i_weight_00,
    input wire signed [DATA_WIDTH-1:0]  i_weight_01,
    input wire signed [DATA_WIDTH-1:0]  i_weight_02,
    input wire signed [DATA_WIDTH-1:0]  i_weight_10,
    input wire signed [DATA_WIDTH-1:0]  i_weight_11,
    input wire signed [DATA_WIDTH-1:0]  i_weight_12,
    input wire signed [DATA_WIDTH-1:0]  i_weight_20,
    input wire signed [DATA_WIDTH-1:0]  i_weight_21,
    input wire signed [DATA_WIDTH-1:0]  i_weight_22,

    output reg signed [(2*DATA_WIDTH)-1:0] o_output_data,
    output reg                          o_output_valid
);

    // Multiplication stage.
    reg signed [(2*DATA_WIDTH)-1:0] r_calc [0:8];

    // Pipelined adder tree stages.
    reg signed [(2*DATA_WIDTH)-1:0] r_l1_adder [0:4];
    reg signed [(2*DATA_WIDTH)-1:0] r_l2_adder [0:2];
    reg signed [(2*DATA_WIDTH)-1:0] r_l3_adder [0:1];

    // Output valid delay shift register.
    reg [3:0] r_output_valid;

    integer i;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_data <= {(2*DATA_WIDTH){1'b0}};

            for (i = 0; i < 9; i = i + 1) begin
                r_calc[i] <= {(2*DATA_WIDTH){1'b0}};
            end

            for (i = 0; i < 5; i = i + 1) begin
                r_l1_adder[i] <= {(2*DATA_WIDTH){1'b0}};
            end

            for (i = 0; i < 3; i = i + 1) begin
                r_l2_adder[i] <= {(2*DATA_WIDTH){1'b0}};
            end

            for (i = 0; i < 2; i = i + 1) begin
                r_l3_adder[i] <= {(2*DATA_WIDTH){1'b0}};
            end
        end else begin
            // Stage 1: multiply each window value by its corresponding weight.
            r_calc[0] <= i_window_00 * i_weight_00;
            r_calc[1] <= i_window_01 * i_weight_01;
            r_calc[2] <= i_window_02 * i_weight_02;
            r_calc[3] <= i_window_10 * i_weight_10;
            r_calc[4] <= i_window_11 * i_weight_11;
            r_calc[5] <= i_window_12 * i_weight_12;
            r_calc[6] <= i_window_20 * i_weight_20;
            r_calc[7] <= i_window_21 * i_weight_21;
            r_calc[8] <= i_window_22 * i_weight_22;

            // Stage 2: first-level partial sums.
            r_l1_adder[0] <= r_calc[0] + r_calc[1];
            r_l1_adder[1] <= r_calc[2] + r_calc[3];
            r_l1_adder[2] <= r_calc[4] + r_calc[5];
            r_l1_adder[3] <= r_calc[6] + r_calc[7];
            r_l1_adder[4] <= r_calc[8];

            // Stage 3: second-level partial sums.
            r_l2_adder[0] <= r_l1_adder[0] + r_l1_adder[1];
            r_l2_adder[1] <= r_l1_adder[2] + r_l1_adder[3];
            r_l2_adder[2] <= r_l1_adder[4];

            // Stage 4: third-level partial sums.
            r_l3_adder[0] <= r_l2_adder[0] + r_l2_adder[1];
            r_l3_adder[1] <= r_l2_adder[2];

            // Stage 5: final accumulated convolution result.
            o_output_data <= r_l3_adder[0] + r_l3_adder[1];
        end
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_output_valid <= 4'b0;
            o_output_valid <= 1'b0;
        end else begin
            // Delay valid signal to align with the pipelined adder tree output.
            r_output_valid <= {r_output_valid[2:0], i_line_done};
            o_output_valid <= r_output_valid[3];
        end
    end

endmodule
