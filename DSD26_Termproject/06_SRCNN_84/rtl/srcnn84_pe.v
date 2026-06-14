`timescale 1ns / 1ps

module srcnn84_pe #(
    parameter DATA_WIDTH = 16
) (
    input wire                             i_clk,
    input wire                             i_rstn,

    // Enables one valid 3x3 MAC operation.
    input wire                             i_mac_en,

    // 3x3 input window.
    input wire signed [DATA_WIDTH-1:0]     i_window_00,
    input wire signed [DATA_WIDTH-1:0]     i_window_01,
    input wire signed [DATA_WIDTH-1:0]     i_window_02,
    input wire signed [DATA_WIDTH-1:0]     i_window_10,
    input wire signed [DATA_WIDTH-1:0]     i_window_11,
    input wire signed [DATA_WIDTH-1:0]     i_window_12,
    input wire signed [DATA_WIDTH-1:0]     i_window_20,
    input wire signed [DATA_WIDTH-1:0]     i_window_21,
    input wire signed [DATA_WIDTH-1:0]     i_window_22,

    // 3x3 kernel weights.
    input wire signed [DATA_WIDTH-1:0]     i_weight_00,
    input wire signed [DATA_WIDTH-1:0]     i_weight_01,
    input wire signed [DATA_WIDTH-1:0]     i_weight_02,
    input wire signed [DATA_WIDTH-1:0]     i_weight_10,
    input wire signed [DATA_WIDTH-1:0]     i_weight_11,
    input wire signed [DATA_WIDTH-1:0]     i_weight_12,
    input wire signed [DATA_WIDTH-1:0]     i_weight_20,
    input wire signed [DATA_WIDTH-1:0]     i_weight_21,
    input wire signed [DATA_WIDTH-1:0]     i_weight_22,

    // Accumulated 3x3 convolution result.
    output reg signed [(2*DATA_WIDTH)-1:0] o_output_data,
    output reg                             o_output_valid
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    // Multiplying two DATA_WIDTH signed values produces a 2*DATA_WIDTH result.
    localparam MUL_WIDTH = 2 * DATA_WIDTH;

    //--------------------------------------------------------------------------
    // Pipeline registers
    //--------------------------------------------------------------------------

    // Multiplication stage.
    // r_mac[0:8] stores element-wise products of window and weight values.
    reg signed [MUL_WIDTH-1:0] r_mac [0:8];

    // Valid pipeline.
    // It aligns o_output_valid with the final output data after the pipeline delay.
    reg r_mac_en_d;

    integer i;

    //--------------------------------------------------------------------------
    // MAC datapath
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_data <= {MUL_WIDTH{1'b0}};

            for (i = 0; i < 9; i = i + 1) begin
                r_mac[i] <= {MUL_WIDTH{1'b0}};
            end
        end else begin
            // Stage 0: multiply each window pixel by its corresponding weight.
            if (i_mac_en) begin
                r_mac[0] <= i_window_00 * i_weight_00;
                r_mac[1] <= i_window_01 * i_weight_01;
                r_mac[2] <= i_window_02 * i_weight_02;
                r_mac[3] <= i_window_10 * i_weight_10;
                r_mac[4] <= i_window_11 * i_weight_11;
                r_mac[5] <= i_window_12 * i_weight_12;
                r_mac[6] <= i_window_20 * i_weight_20;
                r_mac[7] <= i_window_21 * i_weight_21;
                r_mac[8] <= i_window_22 * i_weight_22;
            end

            // Stage 1: final accumulated 3x3 MAC result.
            if (r_mac_en_d) begin
                o_output_data <= r_mac[0] + r_mac[1] + r_mac[2] +
                                 r_mac[3] + r_mac[4] + r_mac[5] +
                                 r_mac[6] + r_mac[7] + r_mac[8];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Output valid generation
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_mac_en_d     <= 1'b0;
            o_output_valid <= 1'b0;
        end else begin
            // Shift i_mac_en through the same number of pipeline stages
            // as the MAC datapath.
            r_mac_en_d     <= i_mac_en;
            o_output_valid <= r_mac_en_d;
        end
    end

endmodule
