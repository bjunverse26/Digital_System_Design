`timescale 1ns / 1ps

module tb_MAC();

	//==============================================================================
	// Testbench Parameters And Signals
	//==============================================================================

	reg clk;
	reg rstn;
	reg dsp_enable;
	reg signed [15:0] dsp_input;
	reg signed [15:0] dsp_weight;
	wire signed [47:0] dsp_output;
	
	//==============================================================================
	// Clock Generation
	//==============================================================================

	initial begin
	clk = 1;
	forever
	#5 clk = ~clk;
	end
	
	//==============================================================================
	// Reset And Stimulus
	//==============================================================================
	initial begin
	
		rstn = 1;
		#20 rstn = 0;
		
		dsp_enable = 0; dsp_input = 0; dsp_weight = 0;
		
		#10 rstn = 1;
		#10
		#10 dsp_enable = 1; dsp_input = 1; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 2; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 3; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 4; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 5; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 6; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 7; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 8; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 9; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 10; dsp_weight = -1;
		#10 dsp_enable = 1; dsp_input = 1; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 2; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 3; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 4; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 5; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 6; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 7; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 8; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 9; dsp_weight = 1;
		#10 dsp_enable = 1; dsp_input = 10; dsp_weight = 1;
		#20 dsp_enable = 0; dsp_input = 0; dsp_weight = 0;

	end
	
	//==============================================================================
	// DUT Instantiation
	//==============================================================================

	MAC dut(
		.i_clk(clk),
		.i_rstn(rstn),
		.i_dsp_enable(dsp_enable),
		.i_dsp_input(dsp_input),
		.i_dsp_weight(dsp_weight),
		.o_dsp_output(dsp_output)
	);

endmodule