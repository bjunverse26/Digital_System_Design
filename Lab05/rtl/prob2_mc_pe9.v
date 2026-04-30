//==============================================================================
// File Name   : prob2_mc_pe9.v
// Project     : Digital System Design - Lab05
// Author      : Beomjun Kim
// Description : Multi-channel PE using three parallel single-channel PUs.
// Notes       : Packed 48-bit activation and weight inputs carry three 16-bit
//               channels that are reduced after each PU output.
//==============================================================================

`timescale 1ns / 1ps

module prob2_mc_pe9 (
    input  wire                      i_clk,
    input  wire                      i_rstn,
    input  wire                      i_act_shift,
    input  wire signed [47:0]        i_act,
    input  wire                      i_w_shift,
    input  wire signed [47:0]        i_w,
    input  wire                      i_pu_en,

    output wire signed [15:0]        o_output,
    output reg                       o_output_valid
);

    wire signed [15:0] act0;
    wire signed [15:0] act1;
    wire signed [15:0] act2;

    wire signed [15:0] w0;
    wire signed [15:0] w1;
    wire signed [15:0] w2;

    wire signed [31:0] o_acc0;
    wire signed [31:0] o_acc1;
    wire signed [31:0] o_acc2;

    wire o_acc_valid0;
    wire o_acc_valid1;
    wire o_acc_valid2;

    reg signed [31:0] o_axis_sum;

    // Unpack channel data. Each channel is processed by its own PU.
    assign act0 = i_act[47:32];
    assign act1 = i_act[31:16];
    assign act2 = i_act[15:0];

    assign w0 = i_w[47:32];
    assign w1 = i_w[31:16];
    assign w2 = i_w[15:0];

    // Channel 0 PU.
    pu u_pu0 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_act_shift    (i_act_shift),
        .i_act          (act0),
        .i_w_shift      (i_w_shift),
        .i_w            (w0),
        .i_pu_en        (i_pu_en),

        .o_output       (o_acc0),
        .o_output_valid (o_acc_valid0)
    );

    // Channel 1 PU.
    pu u_pu1 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_act_shift    (i_act_shift),
        .i_act          (act1),
        .i_w_shift      (i_w_shift),
        .i_w            (w1),
        .i_pu_en        (i_pu_en),

        .o_output       (o_acc1),
        .o_output_valid (o_acc_valid1)
    );

    // Channel 2 PU.
    pu u_pu2 (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_act_shift    (i_act_shift),
        .i_act          (act2),
        .i_w_shift      (i_w_shift),
        .i_w            (w2),
        .i_pu_en        (i_pu_en),

        .o_output       (o_acc2),
        .o_output_valid (o_acc_valid2)
    );

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_axis_sum <= 32'sd0;
        end else begin
            // Sum across the three channel accumulations.
            o_axis_sum <= o_acc0 + o_acc1 + o_acc2;
        end
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_valid <= 1'b0;
        end else begin
            // Output is valid only when every channel PU has a valid result.
            o_output_valid <= o_acc_valid0 & o_acc_valid1 & o_acc_valid2;
        end
    end

    // Fixed-point down-conversion after channel reduction.
    assign o_output = {o_axis_sum[31], o_axis_sum[23:8]};

endmodule
