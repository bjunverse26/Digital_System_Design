//==============================================================================
// File Name   : prob1_sc_pe3.v
// Project     : Digital System Design - Lab05
// Author      : Beomjun Kim
// Description : Single-channel 3-tap PE wrapper.
// Notes       : The PU produces a 32-bit accumulation and this wrapper returns
//               the 16-bit fixed-point slice expected by the lab testbench.
//==============================================================================

`timescale 1ns / 1ps

module prob1_sc_pe3 (
    input  wire                      i_clk,
    input  wire                      i_rstn,
    input  wire                      i_act_shift,
    input  wire signed [15:0]        i_act,
    input  wire                      i_w_shift,
    input  wire signed [15:0]        i_w,
    input  wire                      i_pu_en,

    output wire signed [15:0]        o_output,
    output wire                      o_output_valid
);

    wire [31:0] o_acc;

    // One PU handles the single input channel.
    pu u_pu (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_act_shift    (i_act_shift),
        .i_act          (i_act),
        .i_w_shift      (i_w_shift),
        .i_w            (i_w),
        .i_pu_en        (i_pu_en),

        .o_output       (o_acc),
        .o_output_valid (o_output_valid)
    );

    // Fixed-point down-conversion: keep sign and the selected middle bits.
    assign o_output = {o_acc[31], o_acc[23:8]};

endmodule
