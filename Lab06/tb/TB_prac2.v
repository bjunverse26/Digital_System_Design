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

module TB_prac2 ();

    //==============================================================================
    // Parameter Define
    //==============================================================================
    // Model dimensions
    parameter INPUT_WIDTH    = 5                                                    ;
    parameter INPUT_HEIGHT   = 5                                                    ;
    parameter WEIGHT_WIDTH   = 3                                                    ;
    parameter WEIGHT_HEIGHT  = 3                                                    ;
    parameter OUTPUT_WIDTH   = 3                                                    ;
    parameter OUTPUT_HEIGHT  = 3                                                    ;
    parameter LP_CHANNELS    = 3                                                    ;
    
    // Per-channel derived sizes
    localparam LP_INPUT_SIZE_CH  = INPUT_WIDTH  * INPUT_HEIGHT                      ; // 25
    localparam LP_WEIGHT_SIZE_CH = WEIGHT_WIDTH * WEIGHT_HEIGHT                     ; // 9
    localparam LP_INPUT_SIZE     = LP_INPUT_SIZE_CH  * LP_CHANNELS                  ; // 75
    localparam LP_WEIGHT_SIZE    = LP_WEIGHT_SIZE_CH * LP_CHANNELS                  ; // 27
    localparam LP_OUTPUT_SIZE    = OUTPUT_WIDTH * OUTPUT_HEIGHT                     ; // 9

    // FSM state encoding
    localparam LP_IDLE              = 3'd0                                          ;
    localparam LP_W_READ            = 3'd1                                          ;
    localparam LP_DELAY             = 3'd2                                          ;
    localparam LP_I_READ_LINEx3     = 3'd3                                          ;
    localparam LP_I_WAIT            = 3'd4                                          ;
    localparam LP_I_READ_LINE_1     = 3'd5                                          ;
    localparam LP_WAIT_OUTPUT       = 3'd6                                          ;
    localparam LP_DONE              = 3'd7                                          ;

    // BRAM initialization files
    parameter INIT_INPUT_BRAM  = "C:/Users/rlaqj/Project/Digital_System_Design/Lecture/Lab06/rtl/prob2/act.txt";
    parameter INIT_WEIGHT_BRAM = "C:/Users/rlaqj/Project/Digital_System_Design/Lecture/Lab06/rtl/prob2/w.txt";
    
    //==============================================================================
    // System Signals
    //==============================================================================
    reg         i_clk;
    reg         i_rstn;
    reg         i_start;

    initial
        i_clk = 1'b0;
    always #5 i_clk = !i_clk;

    //==============================================================================
    // Register Declarations
    //==============================================================================
    // FSM
    reg [2:0]   r_state                                                             ;

    // WEIGHT BRAM CONTROL
    reg         r_weight_bram_rd_en                                                 ;
    reg [4:0]   r_weight_bram_rd_addr                                               ;

    // INPUT BRAM CONTROL
    reg         r_input_bram_rd_en                                                  ;
    reg [6:0]   r_input_bram_rd_addr                                                ;

    // STATE COUNTER
    reg [4:0]   r_cnt                                                               ;
    reg [2:0]   r_line_col                                                          ;

    // CHANNEL
                                                                                     
    reg [1:0]   r_ch                                                                ;

                                         
                                                                                     

    // DELAY COUNTER
    reg [3:0]   r_delay_cnt                                                         ;

    // OUTPUT BRAM WRITE ADDR
    reg [4:0]   r_output_bram_wr_addr                                               ;

    //==============================================================================
    // Wire Declarations
    //==============================================================================
    // WEIGHT BRAM
    wire            w_weight_bram_rd_valid                                          ;
    wire [15:0]     w_weight_bram_rd_dout                                           ;

    // INPUT BRAM
    wire            w_input_bram_rd_valid                                           ;
    wire [15:0]     w_input_bram_rd_dout                                            ;
    wire            w_input_bram_rd_line_done                                       ;

    //==============================================================================
    // DUT Output Signals
    //==============================================================================
    wire            w_output_valid                                                  ;
    wire [31:0]     w_output                                                        ;
    wire            w_line_rd_done                                                  ;
    wire            w_ch_done                                                       ;
    
    //==============================================================================
    // Continuous Assignments
    //==============================================================================
    assign w_input_bram_rd_line_done = !r_input_bram_rd_en & w_input_bram_rd_valid  ;

    //==============================================================================
    // Reset And Start Stimulus
    //==============================================================================
    initial begin
        i_rstn  = 1'b0;
        i_start = 1'b0;
        #50;
        i_rstn  = 1'b1;
        #10;
        i_start = 1'b1;
    end

    //==============================================================================
    // Stimulus FSM And Address Generation
    //==============================================================================
    always @ ( posedge i_clk ) begin
        if ( !i_rstn ) begin
            r_state                 <= LP_IDLE;
            r_cnt                   <= 'd0;
            r_line_col              <= 'd0;
            r_delay_cnt             <= 'd0;
            r_weight_bram_rd_en     <= 'd0;
            r_weight_bram_rd_addr   <= 'd0;
            r_input_bram_rd_en      <= 'd0;
            r_input_bram_rd_addr    <= 'd0;
        end
        else begin
            case ( r_state )
                LP_IDLE: begin
                    r_weight_bram_rd_en <= 'd0;
                    r_input_bram_rd_en  <= 'd0;
                    if ( i_start ) begin
                        r_state <= LP_W_READ;
                    end
                end
                // READ WEIGHT (9 per channel)
                LP_W_READ: begin
                    r_weight_bram_rd_en   <= 'd1;
                    r_weight_bram_rd_addr <= r_ch * LP_WEIGHT_SIZE_CH + r_cnt;
                    if ( r_cnt >= LP_WEIGHT_SIZE_CH - 1 ) begin
                        r_cnt               <= 'd0;
                        r_state             <= LP_DELAY;
                    end
                    else begin
                        r_cnt <= r_cnt + 'd1;
                    end
                end
                // DELAY for DBG
                LP_DELAY: begin
                    r_weight_bram_rd_en <= 'd0;
                    r_input_bram_rd_en  <= 'd0;
                    if ( r_delay_cnt >= 3 ) begin
                        r_delay_cnt <= 'd0;
                        r_state     <= LP_I_READ_LINEx3;
                    end
                    else begin
                        r_delay_cnt <= r_delay_cnt + 'd1;
                    end
                end
                // READ INPUT - first 3 lines (15 pixels)
                LP_I_READ_LINEx3: begin
                    r_input_bram_rd_en   <= 'd1;
                    r_input_bram_rd_addr <= r_ch * LP_INPUT_SIZE_CH + r_cnt;
                    if ( r_cnt >= ( INPUT_WIDTH * 3 ) - 1 ) begin
                        r_cnt   <= r_cnt + 'd1;
                        r_state <= LP_I_WAIT;
                    end
                    else begin
                        r_cnt <= r_cnt + 'd1;
                    end
                end
                // WAIT LINE_FULL
                LP_I_WAIT: begin
                    r_input_bram_rd_en <= 'd0;
                    if ( r_cnt >= LP_INPUT_SIZE_CH ) begin
                        r_cnt   <= 'd0;
                        r_state <= LP_WAIT_OUTPUT;
                    end
                    else if ( w_line_rd_done ) begin
                        r_line_col <= 'd0;
                        r_state    <= LP_I_READ_LINE_1;
                    end
                end
                // READ INPUT - 1 line (5 pixels)
                LP_I_READ_LINE_1: begin
                    r_input_bram_rd_en   <= 'd1;
                    r_input_bram_rd_addr <= r_ch * LP_INPUT_SIZE_CH + r_cnt;
                    if ( r_line_col >= INPUT_WIDTH - 1 ) begin
                        r_line_col <= 'd0;
                        r_cnt      <= r_cnt + 'd1;
                        r_state    <= LP_I_WAIT;
                    end
                    else begin
                        r_line_col <= r_line_col + 'd1;
                        r_cnt      <= r_cnt + 'd1;
                    end
                end
                // WAIT CH_DONE
                LP_WAIT_OUTPUT: begin
                    r_input_bram_rd_en <= 'd0;
                    if ( w_ch_done ) begin
                        if ( r_ch >= LP_CHANNELS - 1 ) begin
                            r_state <= LP_DONE;
                        end
                        else begin
                            r_state <= LP_W_READ;
                        end
                    end
                end
                // DONE
                LP_DONE: begin
                    r_weight_bram_rd_en <= 'd0;
                    r_input_bram_rd_en  <= 'd0;
                end
                default: r_state <= LP_IDLE;
            endcase
        end
    end
    
    // CHANNEL
    always @ ( posedge i_clk ) begin
        if ( !i_rstn ) begin
            r_ch    <= 'd0;
        end
        else begin
            if ( w_ch_done ) begin
                r_ch    <= r_ch + 'd1;
            end
            else begin
                r_ch    <= r_ch;
            end
        end
    end
    
    //==============================================================================
    // OUTPUT BRAM WRITE ADDR
    //==============================================================================
    always @ ( posedge i_clk ) begin
        if ( !i_rstn ) begin
            r_output_bram_wr_addr <= 'd0;
        end
        else begin
            if ( w_output_valid ) begin
                r_output_bram_wr_addr <= r_output_bram_wr_addr + 'd1;
            end
        end
    end

    //==============================================================================
    // Component Instantiation
    //==============================================================================
    // WEIGHT BRAM
    simple_dual_port_bram #(
        .WIDTH      ( 16                            ),
        .DEPTH      ( LP_WEIGHT_SIZE                ),
        .INIT_FILE  ( INIT_WEIGHT_BRAM              )
    ) weight_bram (
        .clk        ( i_clk                         ),
        // Not Used (Write Side)
        .wr_en      ( 0                             ),
        .wr_addr    ( 0                             ),
        .wr_din     ( 0                             ),
        // Read Side
        .rd_en      ( r_weight_bram_rd_en           ),
        .rd_addr    ( r_weight_bram_rd_addr[4:0]    ),
        .rd_valid   ( w_weight_bram_rd_valid        ),
        .rd_dout    ( w_weight_bram_rd_dout         )
    );

    // INPUT BRAM
    simple_dual_port_bram #(
        .WIDTH      ( 16                            ),
        .DEPTH      ( LP_INPUT_SIZE                 ),
        .INIT_FILE  ( INIT_INPUT_BRAM               )
    ) input_bram (
        .clk        ( i_clk                         ),
        // Not Used (Write Side)
        .wr_en      ( 0                             ),
        .wr_addr    ( 0                             ),
        .wr_din     ( 0                             ),
        // Read Side
        .rd_en      ( r_input_bram_rd_en            ),
        .rd_addr    ( r_input_bram_rd_addr[6:0]     ),
        .rd_valid   ( w_input_bram_rd_valid         ),
        .rd_dout    ( w_input_bram_rd_dout          )
    );

    // TOP prac2
    TOP_prac2 #(
        .INPUT_WIDTH    ( INPUT_WIDTH               ),
        .INPUT_HEIGHT   ( INPUT_HEIGHT              ),
        .WEIGHT_WIDTH   ( WEIGHT_WIDTH              ),
        .WEIGHT_HEIGHT  ( WEIGHT_HEIGHT             )
    ) dut (
        .i_clk          ( i_clk                     ),
        .i_rstn         ( i_rstn                    ),
        .i_ch           ( r_ch                      ),
        .i_line_done    ( w_input_bram_rd_line_done ),
        .i_input_valid  ( w_input_bram_rd_valid     ),
        .i_input_data   ( w_input_bram_rd_dout      ),
        .i_weight_valid ( w_weight_bram_rd_valid    ),
        .i_weight_data  ( w_weight_bram_rd_dout     ),
        .o_output_valid ( w_output_valid            ),
        .o_output       ( w_output                  ),
        .o_line_rd_done ( w_line_rd_done            ),
        .o_ch_done      ( w_ch_done                 )
    );

    // OUTPUT BRAM
    simple_dual_port_bram #(
        .WIDTH      ( 32                            ),
        .DEPTH      ( 1024                          ),
        .INIT_FILE  (                               )
    ) output_bram (
        .clk        ( i_clk                         ),
        // Write Side
        .wr_en      ( w_output_valid                ),
        .wr_addr    ( r_output_bram_wr_addr[3:0]    ),
        .wr_din     ( w_output                      ),
        // Not Used (Read Side)
        .rd_en      ( 0                             ),
        .rd_addr    ( 0                             ),
        .rd_valid   (                               ),
        .rd_dout    (                               )
    );

    //==============================================================================
    // Simulation Control
    //==============================================================================
    initial begin
        #2000
        $finish();
    end

endmodule
