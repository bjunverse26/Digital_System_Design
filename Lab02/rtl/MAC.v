`timescale 1ns / 1ps

// DSP-based multiply-accumulate wrapper.
// Each enabled cycle feeds the previous DSP output back through C, so the DSP
// computes P = A*B + partial_sum.
module MAC (
    input wire                      i_clk,
    input wire                      i_rstn,
    input wire                      i_dsp_enable,

    input wire signed [15:0]        i_dsp_input,
    input wire signed [15:0]        i_dsp_weight,

    output wire signed [47:0]       o_dsp_output
    );
    
    reg signed [47:0] partial_sum;
    
    always @(posedge i_clk) begin
        if (!i_rstn) begin
            // Clear the accumulator feedback path.
            partial_sum <= 48'd0;
        end else if (i_dsp_enable) begin
            // Capture the current DSP result for use as the next partial sum.
            partial_sum <= o_dsp_output;
        end
    end
    
    // Xilinx DSP macro configured as a signed MAC.
    dsp_macro_0 your_instance_name (
      .CLK(i_clk),          // input wire CLK
      .CE(i_dsp_enable),    // input wire CE
      .A(i_dsp_input),      // input wire [15 : 0] A
      .B(i_dsp_weight),     // input wire [15 : 0] B
      .C(partial_sum),      // input wire [47 : 0] C
      .P(o_dsp_output)      // output wire [47 : 0] P
    );

endmodule
