`timescale 1ns / 1ps

module top(
    input wire clk,
    input wire rst_n
    );

    wire [3:0] a;
    wire [3:0] b;
    wire [3:0] adder_o;

    adder adder_inst(
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .b(b),
        .c(adder_o)
    );

    ila_0 u_ila_0 (
	.clk(clk), // input wire clk


	.probe0(rst_n), // input wire [0:0]  probe0  
	.probe1(a), // input wire [3:0]  probe1 
	.probe2(b), // input wire [3:0]  probe2 
	.probe3(adder_o) // input wire [3:0]  probe3
    );

    vio_0 u_vio_0 (
    .clk(clk),                // input wire clk
    .probe_in0(adder_o),    // input wire [3 : 0] probe_in0
    .probe_out0(a),  // output wire [3 : 0] probe_out0
    .probe_out1(b)  // output wire [3 : 0] probe_out1
    );

endmodule