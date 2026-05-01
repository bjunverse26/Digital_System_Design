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

module tb_top ();

    //-------------------------------------------------------------------------------
    // SYSTEM SIGNALS
    //-------------------------------------------------------------------------------

    reg     i_clk                                                                   ;
    reg     i_rstn                                                                  ;
    reg     i_start                                                                 ;

    //-------------------------------------------------------------------------------
    // Clock
    //-------------------------------------------------------------------------------

    initial
        i_clk = 1'b0;

    always #5 i_clk = !i_clk;

    //-------------------------------------------------------------------------------
    // Reset / Start
    //-------------------------------------------------------------------------------

    initial begin
        i_rstn  = 1'b0;
        i_start = 1'b0;
        #50;
        i_rstn  = 1'b1;
        #10;
        i_start = 1'b1;
    end

    //-------------------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------------------

    top dut (
        .i_clk          ( i_clk     ),
        .i_rstn         ( i_rstn    ),
        .i_start        ( i_start   ),
        .o_done         (           ),
        .o_output_valid (           ),
        .o_output       (           ),
        .o_line_rd_done (           )
    );

    //-------------------------------------------------------------------------------
    // SYSTEM
    //-------------------------------------------------------------------------------

    initial begin
        #2000
        $finish();
    end

endmodule
