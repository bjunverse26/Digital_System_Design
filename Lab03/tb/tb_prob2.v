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

module tb_prob2();

    parameter WIDTH      = 16;
    parameter DEPTH      = 4;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    reg                   clk;
    reg                   wr_en;
    reg                   rd_en;
    reg  [ADDR_WIDTH-1:0] wr_addr;
    reg  [ADDR_WIDTH-1:0] rd_addr;
    reg  [WIDTH-1:0]      wr_din;

    wire                  rd_valid;
    wire [WIDTH-1:0]      rd_dout;

    // bram_inst
    simple_dual_port_bram #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE("D:\\DSDTA\\bram_test\\input.txt")
    ) bram_inst (
        .clk(clk),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wr_addr(wr_addr),
        .rd_addr(rd_addr),
        .wr_din(wr_din),
        .rd_valid(rd_valid),
        .rd_dout(rd_dout)
    );

    // 10ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        // initial setting
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_addr = 0;
        rd_addr = 0;
        wr_din  = 0;

        #20;
        $display("==============================================");
        $display("       INIT FILE BRAM TEST START             ");
        $display("==============================================");

        // ==================================================
        // READ SECTION
        // ==================================================
        rd_en   = 1'b1;
        rd_addr = 0;
        #10;
        $display("[%0t] READ  : addr=%0d, rd_valid=%b, rd_dout=0x%04h",
                 $time, rd_addr, rd_valid, rd_dout);

        rd_addr = 1;
        #10;
        $display("[%0t] READ  : addr=%0d, rd_valid=%b, rd_dout=0x%04h",
                 $time, rd_addr, rd_valid, rd_dout);

        rd_addr = 2;
        #10;
        $display("[%0t] READ  : addr=%0d, rd_valid=%b, rd_dout=0x%04h",
                 $time, rd_addr, rd_valid, rd_dout);

        rd_addr = 3;
        #10;
        $display("[%0t] READ  : addr=%0d, rd_valid=%b, rd_dout=0x%04h",
                 $time, rd_addr, rd_valid, rd_dout);

        rd_en   = 1'b0;
        rd_addr = 0;
        #10;

        $display("==============================================");
        $display("             TEST FINISHED                    ");
        $display("==============================================");

        $finish;
    end

endmodule
