`timescale 1ns / 1ps

module Adder_tree_fixed_point (
	input wire							i_clk,
	input wire							i_rstn,
	
	input wire							i_dsp_enable,
	input wire signed [15:0] 			i_din1,
	input wire signed [15:0] 			i_din2,
	input wire signed [15:0] 			i_weight1,
	input wire signed [15:0]			i_weight2,
	
	output wire signed [15:0] 			o_dout
);

	// Two parallel MAC lanes produce wide fixed-point accumulated results.
	wire signed [47:0] mac_out1;
	wire signed [47:0] mac_out2;
	wire mac_done;
	
	// Counts the input samples that belong to one accumulation window.
	reg [2:0] sample_cnt;
	reg add_done;
	
	// Pipeline registers between MAC completion and final add.
	reg signed [15:0] mac_out1_ff;
	reg signed [15:0] mac_out2_ff;
	reg signed [15:0] sum_ff;
	
	assign mac_done = i_dsp_enable && (sample_cnt == 3'd4);
	assign o_dout = sum_ff;
	
	// MAC lane 0.
	MAC MAC_inst1 (
	.i_clk(i_clk),
	.i_rstn(i_rstn),
	.i_dsp_enable(i_dsp_enable),
	.i_dsp_input(i_din1),
	.i_dsp_weight(i_weight1),
	.o_dsp_output(mac_out1)
	);
	
	// MAC lane 1.
	MAC MAC_inst2 (
	.i_clk(i_clk),
	.i_rstn(i_rstn),
	.i_dsp_enable(i_dsp_enable),
	.i_dsp_input(i_din2),
	.i_dsp_weight(i_weight2),
	.o_dsp_output(mac_out2)
	);
	
	always @ (posedge i_clk) begin
		if (!i_rstn) begin
			sample_cnt <= 3'd0;
			add_done <= 1'd0;
			mac_out1_ff <= 16'd0;
			mac_out2_ff <= 16'd0;
			sum_ff <= 16'd0;
		end else begin
			if (i_dsp_enable) begin
				// Wrap after five enabled samples.
				if (sample_cnt == 3'd4) begin
					sample_cnt <= 3'd0;
				end else begin
					sample_cnt <= sample_cnt + 3'd1;
				end
			end
			
			if (mac_done) begin
				// Convert the 48-bit MAC result back to the 16-bit fixed-point format.
				mac_out1_ff <= mac_out1 >>> 8;
				mac_out2_ff <= mac_out2 >>> 8;
			end
			
			add_done <= mac_done;
			
			if (add_done) begin
				// Final two-input adder stage.
				sum_ff <= $signed(mac_out1_ff) + $signed(mac_out2_ff);
			end
		end
	end
			
endmodule
