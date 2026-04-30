//==============================================================================
// File Name   : adder.v
// Project     : Digital System Design - Lab01
// Author      : Beomjun Kim
// Description : Registered 4-bit adder for the Lab01 Vivado debug design.
// Notes       : The output is clocked so VIO/ILA can observe a stable datapath.
//==============================================================================

`timescale 1ns / 1ps

module adder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg  [3:0] c
);

    always @(posedge clk) begin
        if (!rst_n) begin
            c <= 4'h0;
        end else begin
            c <= a + b;
        end
    end

endmodule
