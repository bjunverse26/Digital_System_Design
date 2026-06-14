//==============================================================================
// File Name   : controller_2layer_relu_padding.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Controller for two zero-padded convolution layers.
// Notes       : - Keeps the same interface style as controller_padding.
//               - Layer 1 and layer 2 use the same read/weight ports.
//               - top.v selects act/ReLU BRAM and w_L1/w_L2 BRAM by layer.
//==============================================================================

`timescale 1ns / 1ps

module controller_2layer #(
    parameter INPUT_WIDTH       = 5,
    parameter INPUT_HEIGHT      = 5,
    parameter WEIGHT_WIDTH      = 3,
    parameter WEIGHT_HEIGHT     = 3,
    parameter INPUT_ADDR_WIDTH  = $clog2(INPUT_WIDTH * INPUT_HEIGHT),
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_WIDTH * WEIGHT_HEIGHT)
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,

    // Starts one complete padded convolution read sequence.
    input  wire                         i_start,

    // Pulse from datapath when one output row has been consumed.
    input  wire                         i_line_rd_done,

    // Input-image BRAM read interface for in-range pixels.
    output reg                          o_input_rd_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]  o_input_rd_addr,

    // One-cycle valid pulse for zero-padded pixels.
    output reg                          o_input_zero_valid,

    // One-cycle pulse aligned with the last streamed pixel of a line burst.
    output reg                          o_input_line_done,

    // Weight BRAM read interface.
    output reg                          o_weight_rd_en,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] o_weight_rd_addr,

    // Active layer select for top-level BRAM routing.
    output reg                          o_layer,

    // Asserted after all padded input pixels have been streamed.
    output reg                          o_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam PADDING             = 1;
    localparam PADDED_INPUT_WIDTH  = INPUT_WIDTH + (2 * PADDING);
    localparam PADDED_INPUT_HEIGHT = INPUT_HEIGHT + (2 * PADDING);
    localparam PADDED_INPUT_SIZE   = PADDED_INPUT_WIDTH * PADDED_INPUT_HEIGHT;
    localparam WEIGHT_SIZE         = WEIGHT_WIDTH * WEIGHT_HEIGHT;
    localparam INIT_LINE_SIZE      = PADDED_INPUT_WIDTH * WEIGHT_HEIGHT;

    localparam PAD_ROW_ADDR        = (PADDED_INPUT_HEIGHT > 1) ?
                                     $clog2(PADDED_INPUT_HEIGHT) : 1;
    localparam PAD_COL_ADDR        = (PADDED_INPUT_WIDTH > 1) ?
                                     $clog2(PADDED_INPUT_WIDTH) : 1;
    localparam PAD_CNT_WIDTH       = $clog2(PADDED_INPUT_SIZE);
    localparam BURST_CNT_WIDTH     = $clog2(INIT_LINE_SIZE);

    localparam LAYER_1             = 1'b0;
    localparam LAYER_2             = 1'b1;

    localparam S_IDLE              = 4'd0;
    localparam S_L1_W_READ         = 4'd1;
    localparam S_L1_I_READ_LINEx3  = 4'd2;
    localparam S_L1_I_WAIT         = 4'd3;
    localparam S_L1_I_READ_LINE_1  = 4'd4;
    localparam S_L1_DONE           = 4'd5;
    localparam S_L2_W_READ         = 4'd6;
    localparam S_L2_I_READ_LINEx3  = 4'd7;
    localparam S_L2_I_WAIT         = 4'd8;
    localparam S_L2_I_READ_LINE_1  = 4'd9;
    localparam S_L2_DONE           = 4'd10;

    //--------------------------------------------------------------------------
    // State and counters
    //--------------------------------------------------------------------------

    reg [3:0]                   r_state;
    reg [3:0]                   n_state;

    reg [PAD_ROW_ADDR-1:0]      r_padded_row;
    reg [PAD_COL_ADDR-1:0]      r_padded_col;

    reg [PAD_CNT_WIDTH-1:0]     r_cnt;
    reg [BURST_CNT_WIDTH-1:0]   r_line_col;
    reg [WEIGHT_ADDR_WIDTH-1:0] r_weight_cnt;

    reg                         r_wait_bram;

    //--------------------------------------------------------------------------
    // Current padded coordinate decode
    //--------------------------------------------------------------------------

    wire                        w_inside_input;
    wire [31:0]                 w_src_row;
    wire [31:0]                 w_src_col;
    wire [31:0]                 w_src_addr_calc;

    assign w_inside_input = (r_padded_row >= PADDING) &&
                            (r_padded_row < (INPUT_HEIGHT + PADDING)) &&
                            (r_padded_col >= PADDING) &&
                            (r_padded_col < (INPUT_WIDTH + PADDING));

    assign w_src_row       = r_padded_row - PADDING;
    assign w_src_col       = r_padded_col - PADDING;
    assign w_src_addr_calc = (w_src_row * INPUT_WIDTH) + w_src_col;

    //--------------------------------------------------------------------------
    // 1. State update always block
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state <= S_IDLE;
        end else begin
            r_state <= n_state;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Next state definition always block
    //--------------------------------------------------------------------------

    always @(*) begin
        n_state = r_state;

        case (r_state)
            S_IDLE: begin
                if (i_start) begin
                    n_state = S_L1_W_READ;
                end
            end

            S_L1_W_READ: begin
                if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                    n_state = S_L1_I_READ_LINEx3;
                end 
            end

            S_L1_I_READ_LINEx3: begin
                if (r_line_col == INIT_LINE_SIZE - 1) begin
                    n_state = S_L1_I_WAIT;
                end
            end

            S_L1_I_WAIT: begin
                if (i_line_rd_done) begin
                    n_state = S_L1_I_READ_LINE_1;
                end
            end

            S_L1_I_READ_LINE_1: begin
                if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                    if (r_cnt == PADDED_INPUT_SIZE - 1) begin
                        n_state = S_L1_DONE;
                    end else begin
                        n_state = S_L1_I_WAIT;
                    end
                end
            end

            S_L1_DONE: begin
                n_state = S_L2_W_READ;
            end

            S_L2_W_READ: begin
                if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                    n_state = S_L2_I_READ_LINEx3;
                end 
            end

            S_L2_I_READ_LINEx3: begin
                if (r_line_col == INIT_LINE_SIZE - 1) begin
                    n_state = S_L2_I_WAIT;
                end
            end

            S_L2_I_WAIT: begin
                if (i_line_rd_done) begin
                    n_state = S_L2_I_READ_LINE_1;
                end
            end

            S_L2_I_READ_LINE_1: begin
                if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                    if (r_cnt == PADDED_INPUT_SIZE - 1) begin
                        n_state = S_L2_DONE;
                    end else begin
                        n_state = S_L2_I_WAIT;
                    end
                end
            end

            S_L2_DONE: begin
                n_state = S_IDLE;
            end

            default: begin
                n_state = S_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // 3. Output logic definition always block
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_padded_row       <= {PAD_ROW_ADDR{1'b0}};
            r_padded_col       <= {PAD_COL_ADDR{1'b0}};
            r_cnt              <= {PAD_CNT_WIDTH{1'b0}};
            r_line_col         <= {BURST_CNT_WIDTH{1'b0}};
            r_weight_cnt       <= {WEIGHT_ADDR_WIDTH{1'b0}};
            r_wait_bram        <= 1'b0;

            o_input_rd_en      <= 1'b0;
            o_input_rd_addr    <= {INPUT_ADDR_WIDTH{1'b0}};
            o_input_zero_valid <= 1'b0;
            o_input_line_done  <= 1'b0;
            o_weight_rd_en     <= 1'b0;
            o_weight_rd_addr   <= {WEIGHT_ADDR_WIDTH{1'b0}};
            o_layer            <= LAYER_1;
            o_done             <= 1'b0;
        end else begin
            o_input_rd_en      <= 1'b0;
            o_input_zero_valid <= 1'b0;
            o_input_line_done  <= 1'b0;
            o_weight_rd_en     <= 1'b0;
            o_layer            <= ((r_state == S_L2_W_READ) ||
                                   (r_state == S_L2_I_READ_LINEx3) ||
                                   (r_state == S_L2_I_WAIT) ||
                                   (r_state == S_L2_I_READ_LINE_1) ||
                                   (r_state == S_L2_DONE)) ? LAYER_2 : LAYER_1;

            case (r_state)
                S_IDLE: begin
                    r_padded_row     <= {PAD_ROW_ADDR{1'b0}};
                    r_padded_col     <= {PAD_COL_ADDR{1'b0}};
                    r_cnt            <= {PAD_CNT_WIDTH{1'b0}};
                    r_line_col       <= {BURST_CNT_WIDTH{1'b0}};
                    r_weight_cnt     <= {WEIGHT_ADDR_WIDTH{1'b0}};
                    r_wait_bram      <= 1'b0;

                    o_input_rd_addr  <= {INPUT_ADDR_WIDTH{1'b0}};
                    o_weight_rd_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
                    o_done           <= 1'b0;
                end

                S_L1_W_READ: begin
                    o_weight_rd_en   <= 1'b1;
                    o_weight_rd_addr <= r_weight_cnt;

                    if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                        r_weight_cnt <= {(WEIGHT_ADDR_WIDTH){1'b0}};
                    end else begin
                        r_weight_cnt <= r_weight_cnt + 1'b1;
                    end
                end

                S_L1_I_READ_LINEx3: begin
                    if (r_wait_bram) begin
                        r_wait_bram <= 1'b0;
                        r_cnt       <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == INIT_LINE_SIZE - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end else if (w_inside_input) begin
                        o_input_rd_en   <= 1'b1;
                        o_input_rd_addr <= w_src_addr_calc[INPUT_ADDR_WIDTH-1:0];
                        r_wait_bram     <= 1'b1;
                    end else begin
                        o_input_zero_valid <= 1'b1;
                        r_cnt              <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == INIT_LINE_SIZE - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end
                end

                S_L1_I_WAIT: begin
                    
                end

                S_L1_I_READ_LINE_1: begin
                    if (r_wait_bram) begin
                        r_wait_bram <= 1'b0;
                        r_cnt       <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end else if (w_inside_input) begin
                        o_input_rd_en   <= 1'b1;
                        o_input_rd_addr <= w_src_addr_calc[INPUT_ADDR_WIDTH-1:0];
                        r_wait_bram     <= 1'b1;
                    end else begin
                        o_input_zero_valid <= 1'b1;
                        r_cnt              <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end
                end

                S_L1_DONE: begin
                    r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                    r_padded_col <= {PAD_COL_ADDR{1'b0}};
                    r_cnt        <= {PAD_CNT_WIDTH{1'b0}};
                    r_line_col   <= {BURST_CNT_WIDTH{1'b0}};
                    r_weight_cnt <= {WEIGHT_ADDR_WIDTH{1'b0}};
                    r_wait_bram  <= 1'b0;
                    o_done       <= 1'b0;
                end

                S_L2_W_READ: begin
                    o_weight_rd_en   <= 1'b1;
                    o_weight_rd_addr <= r_weight_cnt;

                    if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                        r_weight_cnt <= {(WEIGHT_ADDR_WIDTH){1'b0}};
                    end else begin
                        r_weight_cnt <= r_weight_cnt + 1'b1;
                    end
                end

                S_L2_I_READ_LINEx3: begin
                    if (r_wait_bram) begin
                        r_wait_bram <= 1'b0;
                        r_cnt       <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == INIT_LINE_SIZE - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end else if (w_inside_input) begin
                        o_input_rd_en   <= 1'b1;
                        o_input_rd_addr <= w_src_addr_calc[INPUT_ADDR_WIDTH-1:0];
                        r_wait_bram     <= 1'b1;
                    end else begin
                        o_input_zero_valid <= 1'b1;
                        r_cnt              <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == INIT_LINE_SIZE - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end
                end

                S_L2_I_WAIT: begin
                    
                end

                S_L2_I_READ_LINE_1: begin
                    if (r_wait_bram) begin
                        r_wait_bram <= 1'b0;
                        r_cnt       <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end else if (w_inside_input) begin
                        o_input_rd_en   <= 1'b1;
                        o_input_rd_addr <= w_src_addr_calc[INPUT_ADDR_WIDTH-1:0];
                        r_wait_bram     <= 1'b1;
                    end else begin
                        o_input_zero_valid <= 1'b1;
                        r_cnt              <= r_cnt + 1'b1;

                        if (r_padded_col == PADDED_INPUT_WIDTH - 1) begin
                            r_padded_col <= {PAD_COL_ADDR{1'b0}};

                            if (r_padded_row == PADDED_INPUT_HEIGHT - 1) begin
                                r_padded_row <= {PAD_ROW_ADDR{1'b0}};
                            end else begin
                                r_padded_row <= r_padded_row + 1'b1;
                            end
                        end else begin
                            r_padded_col <= r_padded_col + 1'b1;
                        end

                        if (r_line_col == PADDED_INPUT_WIDTH - 1) begin
                            r_line_col        <= {BURST_CNT_WIDTH{1'b0}};
                            o_input_line_done <= 1'b1;
                        end else begin
                            r_line_col <= r_line_col + 1'b1;
                        end
                    end
                end

                S_L2_DONE: begin
                    o_done <= 1'b1;
                end
            endcase
        end
    end

endmodule
