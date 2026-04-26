`timescale 1ns / 1ps

// Top-level example that connects input/weight BRAMs to a DSP MAC and stores
// the accumulated result into an output BRAM.
module mac_with_bram #(
	parameter INPUT_WIDTH = 16,
	parameter WEIGHT_WIDTH = 16,
	parameter OUTPUT_WIDTH = 48,
	
	parameter INPUT_DEPTH = 1024,
	parameter WEIGHT_DEPTH = 1024,
	parameter OUTPUT_DEPTH = 1024,
	
	parameter INPUT_ADDR = $clog2(INPUT_DEPTH),
	parameter WEIGHT_ADDR = $clog2(WEIGHT_DEPTH),
	parameter OUTPUT_ADDR = $clog2(OUTPUT_DEPTH),
	
	parameter INPUT_INIT_FILE = "",
	parameter WEIGHT_INIT_FILE = ""
) (

	input 						i_clk,
	input 						i_rstn,
	// ============================================
	// Input BRAM PORT
	// ============================================
	input 						i_input_rd_en,
	input [INPUT_ADDR-1:0] 		i_input_rd_addr,
	
	input 						i_input_wr_en,
	input [INPUT_ADDR-1:0] 		i_input_wr_addr,
	input [INPUT_WIDTH-1:0] 	i_input_wr_din,
	
	// ============================================
	// Weight BRAM PORT
	// ============================================
	input 						i_weight_rd_en,
	input [WEIGHT_ADDR-1:0] 	i_weight_rd_addr,
	
	input 						i_weight_wr_en,
	input [WEIGHT_ADDR-1:0] 	i_weight_wr_addr,
	input [WEIGHT_WIDTH-1:0] 	i_weight_wr_din,
	
	// ============================================
	// Output BRAM PORT
	// ============================================
	input 						i_output_rd_en,
	input [OUTPUT_ADDR-1:0] 	i_output_rd_addr,
	output [OUTPUT_WIDTH-1:0]	o_output_rd_dout,
	output 						o_output_rd_valid,
	
	input 						i_output_wr_en,
	input [OUTPUT_ADDR-1:0] 	i_output_wr_addr,
	
	// ============================================
	// MAC
	// ============================================
	input 						i_mac_enable
);

	// BRAM read data feeds the MAC on enabled cycles.
	wire [INPUT_WIDTH-1:0] input_bram_dout;
	wire [WEIGHT_WIDTH-1:0] weight_bram_dout;
	wire [OUTPUT_WIDTH-1:0] mac_out;

	// Input BRAM: stores activation/input samples.
	simple_dual_port_bram #(
        .WIDTH(INPUT_WIDTH),
        .DEPTH(INPUT_DEPTH),
        .ADDR_WIDTH(INPUT_ADDR),
        .INIT_FILE(INPUT_INIT_FILE)
    ) u_input_bram (
        .clk(i_clk),
        .wr_en(i_input_wr_en),
        .rd_en(i_input_rd_en),
        .wr_addr(i_input_wr_addr),
        .rd_addr(i_input_rd_addr),
        .wr_din(i_input_wr_din),
        .rd_valid(),
        .rd_dout(input_bram_dout)
    );
	
	// Weight BRAM: stores coefficient/weight samples.
	simple_dual_port_bram #(
        .WIDTH(WEIGHT_WIDTH),
        .DEPTH(WEIGHT_DEPTH),
        .ADDR_WIDTH(WEIGHT_ADDR),
        .INIT_FILE(WEIGHT_INIT_FILE)
    ) u_weight_bram (
        .clk(i_clk),
        .wr_en(i_weight_wr_en),
        .rd_en(i_weight_rd_en),
        .wr_addr(i_weight_wr_addr),
        .rd_addr(i_weight_rd_addr),
        .wr_din(i_weight_wr_din),
        .rd_valid(),
        .rd_dout(weight_bram_dout)
    );
	
	// Output BRAM: writes the current MAC output and supports external reads.
	simple_dual_port_bram #(
        .WIDTH(OUTPUT_WIDTH),
        .DEPTH(OUTPUT_DEPTH),
        .ADDR_WIDTH(OUTPUT_ADDR),
        .INIT_FILE()
    ) u_output_bram (
        .clk(i_clk),
        .wr_en(i_output_wr_en),
        .rd_en(i_output_rd_en),
        .wr_addr(i_output_wr_addr),
        .rd_addr(i_output_rd_addr),
        .wr_din(mac_out),
        .rd_valid(o_output_rd_valid),
        .rd_dout(o_output_rd_dout)
    );
	
	// Accumulates input_bram_dout * weight_bram_dout while enabled.
	MAC u_MAC (
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_dsp_enable(i_mac_enable),
		.i_dsp_input(input_bram_dout),
		.i_dsp_weight(weight_bram_dout),
		.o_dsp_output(mac_out)
	);
	

endmodule
	
	
	
