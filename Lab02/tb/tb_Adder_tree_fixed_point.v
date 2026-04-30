`timescale 1ns / 1ps

module tb_Adder_tree_fixed_point();

    //==============================================================================
    // Testbench Parameters And Signals
    //==============================================================================

		reg clk;
		reg rstn;
		reg dsp_enable;
		
		reg signed [15:0] din1;
		reg signed [15:0] din2;
		reg signed [15:0] weight1;
		reg signed [15:0] weight2;
		wire signed [15:0] dout;
		
		//==============================================================================
		// DUT Instantiation
		//==============================================================================

		Adder_tree_fixed_point dut (
		.i_clk(clk),
		.i_rstn(rstn),
		.i_dsp_enable(dsp_enable),
		.i_din1(din1),
		.i_din2(din2),
		.i_weight1(weight1),
		.i_weight2(weight2),
		.o_dout(dout)
		);
		
		initial begin
			clk = 0;
			forever #5 clk = ~clk;
		end
		
		initial begin
			rstn = 1'b0;
			dsp_enable = 1'b0;
			din1 = 16'sd0;
			din2 = 16'sd0;
			weight1 = 16'sd0;
			weight2 = 16'sd0;
			#20;
			rstn = 1'b1;
			#5;
			dsp_enable = 1'b1;
			
			// cycle 1
			din1 = 16'h0324; // 3.1415926 (Q8.8: 3.140625)
			weight1 = 16'hFD48; // -2.7182818 (Q8.8: -2.71875)
			// exp product(hex): 16'hF776, exp(real): -8.5390625
			din2 = 16'h0180; // 1.5
			weight2 = 16'h0200; // 2.0
			// exp product(hex): 16'h0300, exp(real): 3.0
			#10;
			
			// cycle 2
			din1 = 16'hFE80; // -1.5
			weight1 = 16'h0200; // 2.0
			din2 = 16'h0058; // 0.3418556 (Q8.8: 0.34375)
			weight2 = 16'h01CA; // 1.789321 (Q8.8: 1.7890625)
			#10;
			
			// cycle 3
			din1 = 16'hFF62; // -0.6172839 (Q8.8: -0.6171875)
			weight1 = 16'h0058; // 0.3418556 (Q8.8: 0.34375)
			din2 = 16'h0324; // 3.1415926 (Q8.8: 3.140625)
			weight2 = 16'hFD48; // -2.7182818 (Q8.8: -2.71875)
			#10;
			din1 = 16'sd0;
			din2 = 16'sd0;
			weight1 = 16'sd0;
			weight2 = 16'sd0;
			#20;
			dsp_enable = 1'b0;
			
			// Expected answer: EF52
			#60;
			$finish;
		end

endmodule