//==============================================================================
// File Name   : MAC.v
// Project     : Digital System Design - Lab02
// Author      : Beomjun Kim
// Description : DSP-based signed multiply-accumulate wrapper.
// Notes       : The previous DSP output is fed back through the C input while
//               i_dsp_enable is asserted.
//==============================================================================

`timescale 1ns / 1ps

module MAC (
    input  wire                    i_clk,
    input  wire                    i_rstn,
    input  wire                    i_dsp_enable,

    input  wire signed [15:0]     i_dsp_input,
    input  wire signed [15:0]     i_dsp_weight,

    output wire signed [47:0]       o_dsp_output
);
    
    reg signed [47:0] partial_sum;
    
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            partial_sum <= 48'd0;
        end else if (i_dsp_enable) begin
            partial_sum <= o_dsp_output;
        end
    end
    
    dsp_macro_0 u_dsp (
        .CLK (i_clk),
        .CE  (i_dsp_enable),
        .A   (i_dsp_input),
        .B   (i_dsp_weight),
        .C   (partial_sum),
        .P   (o_dsp_output)
    );

endmodule
