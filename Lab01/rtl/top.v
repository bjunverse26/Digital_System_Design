//==============================================================================
// File Name   : top.v
// Project     : Digital System Design - Lab01
// Author      : Beomjun Kim
// Description : FPGA debug top that connects VIO-driven inputs to an ILA-probed
//               registered adder datapath.
// Notes       : VIO provides the adder operands and ILA captures reset, inputs,
//               and registered sum output.
//==============================================================================

`timescale 1ns / 1ps

module top (
    input wire clk,
    input wire rst_n
);

    wire [3:0] a;
    wire [3:0] b;
    wire [3:0] adder_o;

    adder u_adder (
        .clk   (clk),
        .rst_n (rst_n),
        .a     (a),
        .b     (b),
        .c     (adder_o)
    );

    ila_0 u_ila_0 (
        .clk    (clk),
        .probe0 (rst_n),
        .probe1 (a),
        .probe2 (b),
        .probe3 (adder_o)
    );

    vio_0 u_vio_0 (
        .clk        (clk),
        .probe_in0  (adder_o),
        .probe_out0 (a),
        .probe_out1 (b)
    );

endmodule
