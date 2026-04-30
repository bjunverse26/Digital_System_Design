//==============================================================================
// File Name   : pu.v
// Project     : Digital System Design - Lab05
// Author      : Beomjun Kim
// Description : Processing unit for one 1-D convolution window.
// Notes       : Three activation samples and three weights are shifted in,
//               multiplied by DSP macros, and reduced to one 32-bit sum.
//==============================================================================

`timescale 1ns / 1ps

module pu (
    input  wire                 i_clk,
    input  wire                 i_rstn,
    input  wire                 i_act_shift,
    input  wire signed [15:0]   i_act,
    input  wire                 i_w_shift,
    input  wire signed [15:0]   i_w,
    input  wire                 i_pu_en,

    output reg signed [31:0]   o_output,
    output reg                 o_output_valid
);

    // Activation shift register holds the current 3-tap input window.
    reg signed [15:0] act0;
    reg signed [15:0] act1;
    reg signed [15:0] act2;

    // Weight shift register holds the matching 3-tap kernel window.
    reg signed [15:0] w0;
    reg signed [15:0] w1;
    reg signed [15:0] w2;

    // Parallel DSP products for each tap.
    wire signed [31:0] acc0;
    wire signed [31:0] acc1;
    wire signed [31:0] acc2;

    reg output_valid_delay1;
    reg output_valid_delay2;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            act0 <= 16'sd0;
            act1 <= 16'sd0;
            act2 <= 16'sd0;
        end else if (i_act_shift) begin
            // Shift newest activation into tap 0.
            act0 <= i_act;
            act1 <= act0;
            act2 <= act1;
        end
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            w0 <= 16'sd0;
            w1 <= 16'sd0;
            w2 <= 16'sd0;
        end else if (i_w_shift) begin
            // Shift newest weight into tap 0.
            w0 <= i_w;
            w1 <= w0;
            w2 <= w1;
        end
    end

    // One DSP per tap. The three products are added after DSP latency.
    dsp_macro_0 u_dsp0 (
        .CLK (i_clk),
        .CE  (i_pu_en),
        .A   (act0),
        .B   (w0),
        .P   (acc0)
    );

    dsp_macro_0 u_dsp1 (
        .CLK (i_clk),
        .CE  (i_pu_en),
        .A   (act1),
        .B   (w1),
        .P   (acc1)
    );

    dsp_macro_0 u_dsp2 (
        .CLK (i_clk),
        .CE  (i_pu_en),
        .A   (act2),
        .B   (w2),
        .P   (acc2)
    );

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output <= 32'sd0;
        end else begin
            // Final combinational reduction registered at the PU output.
            o_output <= acc0 + acc1 + acc2;
        end
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_valid     <= 1'b0;
            output_valid_delay1 <= 1'b0;
            output_valid_delay2 <= 1'b0;
        end else begin
            // Match valid timing to the DSP pipeline latency.
            output_valid_delay1 <= i_pu_en;
            output_valid_delay2 <= output_valid_delay1;
            o_output_valid <= output_valid_delay2;
        end
    end

endmodule
