//============================================================================
// Copyright (c) 2026 Seoul National University of Science and Technology
//                     (SEOULTECH)
//                     Intelligence Digital System Design Lab (IDSL)
//
// Course: Digital System Design, Spring 2026
//
// This source code is provided as educational material for the
// Digital System Design course at SEOULTECH. It is released under
// the MIT License to encourage learning and reuse.
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject
// to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//============================================================================
`timescale 1ns / 1ps

module tb_prob1_sc_pe3();

parameter INIT_INPUT_BRAM = "C:/Users/rlaqj/Project/Digital_Circuit/Digital_System_Design/Lab05/rtl/prob1/act.txt";
parameter INIT_WEIGHT_BRAM = "C:/Users/rlaqj/Project/Digital_Circuit/Digital_System_Design/Lab05/rtl/prob1/w.txt";

reg         i_clk;
reg         i_rstn;

reg         input_bram_rd_en;
reg [2:0]   input_bram_rd_addr;
wire        input_bram_rd_valid;
wire [15:0] input_bram_rd_dout;

simple_dual_port_bram #(
    .WIDTH(16),          // 16 Bit
    .DEPTH(5),          // 5
    .INIT_FILE(INIT_INPUT_BRAM)
) input_bram (
    // Not Used
    .wr_en      (1'b0),
    .wr_addr    (5'b0),
    .wr_din     (16'b0),
    
    // For Read Activation Data
    .clk        (i_clk),
    .rd_en      (input_bram_rd_en),
    .rd_addr    (input_bram_rd_addr),
    .rd_valid   (input_bram_rd_valid),
    .rd_dout    (input_bram_rd_dout) 
);

reg         weight_bram_rd_en;
reg [1:0]   weight_bram_rd_addr;
wire        weight_bram_rd_valid;
wire [15:0] weight_bram_rd_dout;

simple_dual_port_bram #(
    .WIDTH(16),          // 16 Bit
    .DEPTH(3),           // 3 
    .INIT_FILE(INIT_WEIGHT_BRAM)
) weight_bram (
    // Not Used
    .wr_en      (1'b0),
    .wr_addr    (2'b0),
    .wr_din     (16'b0),
    
    // For Read Weight Data
    .clk        (i_clk),
    .rd_en      (weight_bram_rd_en),
    .rd_addr    (weight_bram_rd_addr),
    .rd_valid   (weight_bram_rd_valid),
    .rd_dout    (weight_bram_rd_dout) 
);

reg         i_act_shift;
reg         i_w_shift;
reg         i_pu_en;
wire [15:0] o_output;
wire        o_output_valid;

prob1_sc_pe3 dut(
    .i_clk          (i_clk)                 ,
    .i_rstn         (i_rstn)                ,
    .i_act_shift    (i_act_shift)           ,
    .i_act          (input_bram_rd_dout)    ,
    .i_w_shift      (i_w_shift)             ,
    .i_w            (weight_bram_rd_dout)   ,
    .i_pu_en        (i_pu_en)               ,
    .o_output       (o_output)              ,
    .o_output_valid (o_output_valid)
);

reg [3:0]   output_bram_wr_addr;

simple_dual_port_bram #(
    .WIDTH(16),          // 16 Bit
    .DEPTH(3),          // 3
    .INIT_FILE()
)  output_bram (
    .clk        (i_clk),
    
    // Conv1d Output Write
    .wr_en      (o_output_valid),
    .wr_addr    (output_bram_wr_addr),
    .wr_din     (o_output),
    
    // Not Used
    .rd_en      (1'b0),
    .rd_addr    (3'b0),
    .rd_valid   (),
    .rd_dout    () 
);

initial begin
    i_clk = 0;
    forever #5 i_clk = ~i_clk;   // 100MHz
end

initial begin
    i_rstn             = 1'b0;

    input_bram_rd_en   = 1'b0;
    input_bram_rd_addr = 5'd0;

    weight_bram_rd_en   = 1'b0;
    weight_bram_rd_addr = 2'd0;

    output_bram_wr_addr = 4'd0;

    i_act_shift = 1'b0;
    i_w_shift   = 1'b0;
    i_pu_en     = 1'b0;

    repeat (4) @(posedge i_clk);
    i_rstn = 1'b1;
end

initial begin
    wait(i_rstn == 1'b1);
    @(posedge i_clk);

    // 1) 3 Weight Load
    read_and_shift_weight();

    // 2) Row-by-row Conv1d
    read_and_shift_and_compute_act();

    repeat (10) @(posedge i_clk);
    $finish;
end

always @(posedge i_clk) begin
    if (o_output_valid) output_bram_wr_addr <= output_bram_wr_addr + 1;
end
    

task read_and_shift_weight;
    begin
        @(posedge i_clk);   weight_bram_rd_en <= 1'b1; weight_bram_rd_addr <= 2'd0; i_w_shift <= 1'b0; 
        @(posedge i_clk);   weight_bram_rd_en <= 1'b1; weight_bram_rd_addr <= 2'd1; i_w_shift <= 1'b1; 
        @(posedge i_clk);   weight_bram_rd_en <= 1'b1; weight_bram_rd_addr <= 2'd2; i_w_shift <= 1'b1; 
        @(posedge i_clk);   weight_bram_rd_en <= 1'b0; weight_bram_rd_addr <= 2'd0; i_w_shift <= 1'b1; 
        @(posedge i_clk);   weight_bram_rd_en <= 1'b0; weight_bram_rd_addr <= 2'd0; i_w_shift <= 1'b0; 
    end
endtask



task read_and_shift_and_compute_act;
    integer i;
    begin
        @(posedge i_clk);   input_bram_rd_en = 1'b1; input_bram_rd_addr = 3'd0; i_act_shift = 1'b0; i_pu_en = 1'b0;
        @(posedge i_clk);   input_bram_rd_en = 1'b1; input_bram_rd_addr = 3'd1; i_act_shift = 1'b1; i_pu_en = 1'b0;
        @(posedge i_clk);   input_bram_rd_en = 1'b1; input_bram_rd_addr = 3'd2; i_act_shift = 1'b1; i_pu_en = 1'b0;
        @(posedge i_clk);   input_bram_rd_en = 1'b1; input_bram_rd_addr = 3'd3; i_act_shift = 1'b1; i_pu_en = 1'b1;
        @(posedge i_clk);   input_bram_rd_en = 1'b1; input_bram_rd_addr = 3'd4; i_act_shift = 1'b1; i_pu_en = 1'b1;
        @(posedge i_clk);   input_bram_rd_en = 1'b0; input_bram_rd_addr = 3'd0; i_act_shift = 1'b1; i_pu_en = 1'b1;
        @(posedge i_clk);   input_bram_rd_en = 1'b0; input_bram_rd_addr = 3'd0; i_act_shift = 1'b0; i_pu_en = 1'b0;
    end
endtask

endmodule