//==============================================================================
// File Name   : pe.v
// Project     : Digital System Design - Lab06
// Author      : Beomjun Kim
// Description : Signed 3x3 convolution processing element.
// Notes       : - Performs nine signed multiplications in parallel.
//               - Uses a pipelined adder tree for MAC accumulation.
//               - Each pipeline stage updates only when valid data is present.
//               - Output valid is aligned to the final output register.
//==============================================================================

`timescale 1ns / 1ps

module pe #(
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH  = 16
)(
    input wire                              i_clk,
    input wire                              i_rstn,

    // Enables one valid MAC input sample.
    input wire                              i_mac_en,

    input wire signed [DATA_WIDTH-1:0]      i_window_00,
    input wire signed [DATA_WIDTH-1:0]      i_window_01,
    input wire signed [DATA_WIDTH-1:0]      i_window_02,
    input wire signed [DATA_WIDTH-1:0]      i_window_10,
    input wire signed [DATA_WIDTH-1:0]      i_window_11,
    input wire signed [DATA_WIDTH-1:0]      i_window_12,
    input wire signed [DATA_WIDTH-1:0]      i_window_20,
    input wire signed [DATA_WIDTH-1:0]      i_window_21,
    input wire signed [DATA_WIDTH-1:0]      i_window_22,

    input wire signed [DATA_WIDTH-1:0]      i_weight_00,
    input wire signed [DATA_WIDTH-1:0]      i_weight_01,
    input wire signed [DATA_WIDTH-1:0]      i_weight_02,
    input wire signed [DATA_WIDTH-1:0]      i_weight_10,
    input wire signed [DATA_WIDTH-1:0]      i_weight_11,
    input wire signed [DATA_WIDTH-1:0]      i_weight_12,
    input wire signed [DATA_WIDTH-1:0]      i_weight_20,
    input wire signed [DATA_WIDTH-1:0]      i_weight_21,
    input wire signed [DATA_WIDTH-1:0]      i_weight_22,

    output reg signed [(2*DATA_WIDTH)-1:0]  o_output_data,
    output reg                              o_output_valid
);

    //--------------------------------------------------------------------------
    // Pipeline registers
    //--------------------------------------------------------------------------

    // Multiplier output stage.
    reg signed [(2*DATA_WIDTH)-1:0] r_mac [0:8];

    // Adder tree stages.
    reg signed [(2*DATA_WIDTH)-1:0] r_l1_adder [0:4];
    reg signed [(2*DATA_WIDTH)-1:0] r_l2_adder [0:2];
    reg signed [(2*DATA_WIDTH)-1:0] r_l3_adder [0:1];

    // Valid pipeline for stage-level enable control.
    // r_mac_en_d[0] enables L1 adders.
    // r_mac_en_d[1] enables L2 adders.
    // r_mac_en_d[2] enables L3 adders.
    // r_mac_en_d[3] enables final output register.
    reg [3:0] r_mac_en_d;

    integer i;

    //--------------------------------------------------------------------------
    // MAC datapath
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_data <= {(2*DATA_WIDTH){1'b0}};

            for (i = 0; i < 9; i = i + 1) begin
                r_mac[i] <= {(2*DATA_WIDTH){1'b0}};
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
            // Input multiplication stage.
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

            // L1 adder stage.
            if (r_mac_en_d[0]) begin
                r_l1_adder[0] <= r_mac[0] + r_mac[1];
                r_l1_adder[1] <= r_mac[2] + r_mac[3];
                r_l1_adder[2] <= r_mac[4] + r_mac[5];
                r_l1_adder[3] <= r_mac[6] + r_mac[7];
                r_l1_adder[4] <= r_mac[8];
            end

            // L2 adder stage.
            if (r_mac_en_d[1]) begin
                r_l2_adder[0] <= r_l1_adder[0] + r_l1_adder[1];
                r_l2_adder[1] <= r_l1_adder[2] + r_l1_adder[3];
                r_l2_adder[2] <= r_l1_adder[4];
            end

            // L3 adder stage.
            if (r_mac_en_d[2]) begin
                r_l3_adder[0] <= r_l2_adder[0] + r_l2_adder[1];
                r_l3_adder[1] <= r_l2_adder[2];
            end

            // Final output stage.
            if (r_mac_en_d[3]) begin
                o_output_data <= r_l3_adder[0] + r_l3_adder[1];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Output valid generation
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_mac_en_d     <= 4'b0;
            o_output_valid <= 1'b0;
        end else begin
            r_mac_en_d     <= {r_mac_en_d[2:0], i_mac_en};
            o_output_valid <= r_mac_en_d[3];
        end
    end

endmodule
