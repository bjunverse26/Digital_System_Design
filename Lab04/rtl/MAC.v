`timescale 1ns / 1ps

// DSP-based signed multiply-accumulate block used by the Lab04 GEMV designs.
// The previous DSP result is registered as partial_sum and fed back into C.
module MAC(
    input wire i_clk,
    input wire i_rstn,
    
    input wire i_dsp_enable,
    input wire signed [15:0] i_dsp_input,
    input wire signed [15:0] i_dsp_weight,

    output wire signed [47:0] o_dsp_output
    );

    reg signed [47:0] partial_sum;  
    
    always @(posedge i_clk) begin
        if (~i_rstn) begin
            // Clear the feedback accumulator.
            partial_sum <= 48'sd0;
        end 
        else if (i_dsp_enable) begin
            // Retain the latest DSP output for the next accumulation step.
            partial_sum <= o_dsp_output;
        end
    end

    // Vendor DSP macro configured for signed P = A*B + C.
    dsp_macro_0 dsp (
        .CLK(i_clk),  // input wire CLK
        .CE(i_dsp_enable),    // input wire CE
        .A(i_dsp_input),      // input wire [15 : 0] A
        .B(i_dsp_weight),      // input wire [15 : 0] B
        .C(partial_sum),      // input wire [47 : 0] C
        .P(o_dsp_output)      // output wire [47 : 0] P
    );

endmodule
