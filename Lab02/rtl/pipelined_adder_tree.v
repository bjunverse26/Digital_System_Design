`timescale 1ns / 1ps

module pipelined_adder_tree (
	input wire			i_clk,
	input wire			i_rstn,
	
	input wire			i_en,
	input wire [15:0] 	i_din1,
	input wire [15:0] 	i_din2,
	input wire [15:0] 	i_din3,
	input wire [15:0] 	i_din4,
	
	output wire [17:0]	o_dout
	);
	
	// Input stage registers. These isolate the adder tree from input timing.
	reg [15:0] din_tmp1;
	reg [15:0] din_tmp2;
	reg [15:0] din_tmp3;
	reg [15:0] din_tmp4;
	
	// First adder level. Width grows by one bit after each pairwise add.
	reg [16:0] sum_tmp1;
	reg [16:0] sum_tmp2;
	
	// Second adder level / registered output.
	reg [17:0] dout_o;
	
	always @ (posedge i_clk) begin
		if (!i_rstn) begin
			din_tmp1 <= 16'd0;
			din_tmp2 <= 16'd0;
			din_tmp3 <= 16'd0;
			din_tmp4 <= 16'd0;
			
			sum_tmp1 <= 17'd0;
			sum_tmp2 <= 17'd0;
			
			dout_o <= 18'd0;
		end else if (i_en) begin
			// Pipeline level 0: capture inputs.
			din_tmp1 <= i_din1;
			din_tmp2 <= i_din2;
			din_tmp3 <= i_din3;
			din_tmp4 <= i_din4;
			
			// Pipeline level 1: pairwise sums.
			sum_tmp1 <= din_tmp1 + din_tmp2;
			sum_tmp2 <= din_tmp3 + din_tmp4;
			
			// Pipeline level 2: final sum.
			dout_o <= sum_tmp1 + sum_tmp2;
		end
	end
	
	assign o_dout = dout_o;

endmodule
