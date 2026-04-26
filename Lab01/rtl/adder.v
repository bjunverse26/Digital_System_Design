`timescale 1ns / 1ps

// Registered 4-bit adder used by the Lab01 top-level debug design.
// The sum is captured on the rising clock edge so ILA/VIO can observe a
// stable, clocked datapath instead of a purely combinational signal.
module adder(
    input wire clk,
    input wire rst_n,
    input wire [3:0] a,
    input wire [3:0] b,
    output reg [3:0] c
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            // Active-low synchronous reset for the output register.
            c <= 4'h0;
        end else begin
            c <= a + b;
        end
    end

endmodule
