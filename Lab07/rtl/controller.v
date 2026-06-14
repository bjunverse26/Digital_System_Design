//==============================================================================
// File Name   : controller.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : Read-control FSM for BRAM-backed 3x3 convolution top.
// Notes       : - Issues BRAM read requests for kernel and input image data.
//               - Reads all 3x3 kernel values first.
//               - Reads the first three input lines before convolution starts.
//               - Reads one additional input line whenever the datapath
//                 completes one output row.
//               - Assumes synchronous BRAM read; read data is consumed in top
//                 through BRAM rd_valid.
//==============================================================================

`timescale 1ns / 1ps

module controller #(
    parameter INPUT_WIDTH       = 5,
    parameter INPUT_HEIGHT      = 5,
    parameter WEIGHT_WIDTH      = 3,
    parameter WEIGHT_HEIGHT     = 3,
    parameter INPUT_ADDR_WIDTH  = 5,
    parameter WEIGHT_ADDR_WIDTH = 4
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,

    // Starts one complete convolution read sequence.
    input  wire                         i_start,

    // Pulse from datapath when one output row has been consumed.
    input  wire                         i_line_rd_done,

    // Input-image BRAM read interface.
    output reg                          o_input_rd_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]  o_input_rd_addr,

    // Weight BRAM read interface.
    output reg                          o_weight_rd_en,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] o_weight_rd_addr,

    // Asserted after all required input pixels have been requested.
    output reg                          o_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam INPUT_SIZE      = INPUT_WIDTH * INPUT_HEIGHT;
    localparam WEIGHT_SIZE     = WEIGHT_WIDTH * WEIGHT_HEIGHT;
    localparam INIT_LINE_SIZE  = INPUT_WIDTH * WEIGHT_HEIGHT;

    localparam S_IDLE          = 3'd0;
    localparam S_W_READ        = 3'd1;
    localparam S_I_READ_LINEx3 = 3'd2;
    localparam S_I_WAIT        = 3'd3;
    localparam S_I_READ_LINE_1 = 3'd4;
    localparam S_DONE          = 3'd5;

    //--------------------------------------------------------------------------
    // State and counters
    //--------------------------------------------------------------------------

    reg [2:0]                 r_state;
    reg [2:0]                 w_next_state;

    // Number of input-image read requests issued.
    reg [INPUT_ADDR_WIDTH:0]  r_cnt;

    // Number of pixels requested in the current one-line refill.
    reg [INPUT_ADDR_WIDTH:0]  r_line_col;

    // Number of weight read requests issued.
    reg [WEIGHT_ADDR_WIDTH:0] r_weight_cnt;

    //--------------------------------------------------------------------------
    // 1. State update always block
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state <= S_IDLE;
        end else begin
            r_state <= w_next_state;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Next state definition always block
    //--------------------------------------------------------------------------

    always @(*) begin
        w_next_state = r_state;

        case (r_state)
            S_IDLE: begin
                if (i_start) begin
                    w_next_state = S_W_READ;
                end
            end

            S_W_READ: begin
                if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                    w_next_state = S_I_READ_LINEx3;
                end
            end

            S_I_READ_LINEx3: begin
                if (r_cnt >= INIT_LINE_SIZE - 1) begin
                    w_next_state = S_I_WAIT;
                end
            end

            S_I_WAIT: begin
                if (r_cnt >= INPUT_SIZE) begin
                    w_next_state = S_DONE;
                end else if (i_line_rd_done) begin
                    w_next_state = S_I_READ_LINE_1;
                end
            end

            S_I_READ_LINE_1: begin
                if (r_line_col >= INPUT_WIDTH - 1) begin
                    w_next_state = S_I_WAIT;
                end
            end

            S_DONE: begin
                w_next_state = S_DONE;
            end

            default: begin
                w_next_state = S_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // 3. Output logic definition always block
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_cnt            <= {(INPUT_ADDR_WIDTH+1){1'b0}};
            r_line_col       <= {(INPUT_ADDR_WIDTH+1){1'b0}};
            r_weight_cnt     <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};

            o_input_rd_en    <= 1'b0;
            o_input_rd_addr  <= {INPUT_ADDR_WIDTH{1'b0}};
            o_weight_rd_en   <= 1'b0;
            o_weight_rd_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
            o_done           <= 1'b0;
        end else begin
            o_input_rd_en    <= 1'b0;
            o_weight_rd_en   <= 1'b0;
            o_done           <= 1'b0;

            case (r_state)
                S_IDLE: begin
                    r_cnt            <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_line_col       <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_weight_cnt     <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
                    o_input_rd_addr  <= {INPUT_ADDR_WIDTH{1'b0}};
                    o_weight_rd_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
                end

                S_W_READ: begin
                    o_weight_rd_en   <= 1'b1;
                    o_weight_rd_addr <= r_weight_cnt[WEIGHT_ADDR_WIDTH-1:0];

                    if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                        r_weight_cnt <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
                    end else begin
                        r_weight_cnt <= r_weight_cnt + 1'b1;
                    end
                end

                S_I_READ_LINEx3: begin
                    o_input_rd_en   <= 1'b1;
                    o_input_rd_addr <= r_cnt[INPUT_ADDR_WIDTH-1:0];
                    r_cnt           <= r_cnt + 1'b1;
                end

                S_I_WAIT: begin
                    if (i_line_rd_done) begin
                        r_line_col <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    end
                end

                S_I_READ_LINE_1: begin
                    o_input_rd_en   <= 1'b1;
                    o_input_rd_addr <= r_cnt[INPUT_ADDR_WIDTH-1:0];
                    r_cnt           <= r_cnt + 1'b1;

                    if (r_line_col >= INPUT_WIDTH - 1) begin
                        r_line_col <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    end else begin
                        r_line_col <= r_line_col + 1'b1;
                    end
                end

                S_DONE: begin
                    o_done <= 1'b1;
                end

                default: begin
                    r_cnt        <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_line_col   <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_weight_cnt <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
                end
            endcase
        end
    end

endmodule
