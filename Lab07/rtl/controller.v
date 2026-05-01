//==============================================================================
// File Name   : controller.v
// Project     : Digital System Design - Lab07
// Author      : Beomjun Kim
// Description : FSM controller for the Lab07 BRAM-backed convolution top.
// Notes       : Implements the six-state FSM shown in the Lab07 material:
//               IDLE -> W_READ -> I_READ_LINEx3 -> I_WAIT ->
//               I_READ_LINE_1 -> DONE.
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
    input  wire                         i_start,

    input  wire                         i_line_rd_done,

    output reg                          o_input_rd_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]  o_input_rd_addr,
    output reg                          o_weight_rd_en,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] o_weight_rd_addr,
    output reg                          o_done
);

    localparam INPUT_SIZE      = INPUT_WIDTH * INPUT_HEIGHT;
    localparam WEIGHT_SIZE     = WEIGHT_WIDTH * WEIGHT_HEIGHT;
    localparam INIT_LINE_SIZE  = INPUT_WIDTH * WEIGHT_HEIGHT;

    localparam S_IDLE          = 3'd0;
    localparam S_W_READ        = 3'd1;
    localparam S_I_READ_LINEx3 = 3'd2;
    localparam S_I_WAIT        = 3'd3;
    localparam S_I_READ_LINE_1 = 3'd4;
    localparam S_DONE          = 3'd5;

    reg [2:0]                 r_state;
    reg [INPUT_ADDR_WIDTH:0]  r_cnt;
    reg [INPUT_ADDR_WIDTH:0]  r_line_col;
    reg [WEIGHT_ADDR_WIDTH:0] r_weight_cnt;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state          <= S_IDLE;
            r_cnt            <= {(INPUT_ADDR_WIDTH+1){1'b0}};
            r_line_col       <= {(INPUT_ADDR_WIDTH+1){1'b0}};
            r_weight_cnt     <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
            o_input_rd_en    <= 1'b0;
            o_input_rd_addr  <= {INPUT_ADDR_WIDTH{1'b0}};
            o_weight_rd_en   <= 1'b0;
            o_weight_rd_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
            o_done           <= 1'b0;
        end else begin
            case (r_state)
                S_IDLE: begin
                    o_input_rd_en    <= 1'b0;
                    o_weight_rd_en   <= 1'b0;
                    o_done           <= 1'b0;
                    r_cnt            <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_line_col       <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                    r_weight_cnt     <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
                    o_input_rd_addr  <= {INPUT_ADDR_WIDTH{1'b0}};
                    o_weight_rd_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};

                    if (i_start) begin
                        r_state <= S_W_READ;
                    end
                end

                S_W_READ: begin
                    o_input_rd_en    <= 1'b0;
                    o_weight_rd_en   <= 1'b1;
                    o_weight_rd_addr <= r_weight_cnt[WEIGHT_ADDR_WIDTH-1:0];

                    if (r_weight_cnt >= WEIGHT_SIZE - 1) begin
                        r_weight_cnt <= {(WEIGHT_ADDR_WIDTH+1){1'b0}};
                        r_state      <= S_I_READ_LINEx3;
                    end else begin
                        r_weight_cnt <= r_weight_cnt + 1'b1;
                    end
                end

                S_I_READ_LINEx3: begin
                    o_input_rd_en   <= 1'b1;
                    o_input_rd_addr <= r_cnt[INPUT_ADDR_WIDTH-1:0];
                    o_weight_rd_en  <= 1'b0;

                    if (r_cnt >= INIT_LINE_SIZE - 1) begin
                        r_cnt   <= r_cnt + 1'b1;
                        r_state <= S_I_WAIT;
                    end else begin
                        r_cnt <= r_cnt + 1'b1;
                    end
                end

                S_I_WAIT: begin
                    o_input_rd_en  <= 1'b0;
                    o_weight_rd_en <= 1'b0;

                    if (r_cnt >= INPUT_SIZE) begin
                        r_state <= S_DONE;
                    end else if (i_line_rd_done) begin
                        r_line_col <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                        r_state    <= S_I_READ_LINE_1;
                    end
                end

                S_I_READ_LINE_1: begin
                    o_input_rd_en   <= 1'b1;
                    o_input_rd_addr <= r_cnt[INPUT_ADDR_WIDTH-1:0];
                    o_weight_rd_en  <= 1'b0;

                    if (r_line_col >= INPUT_WIDTH - 1) begin
                        r_line_col <= {(INPUT_ADDR_WIDTH+1){1'b0}};
                        r_cnt      <= r_cnt + 1'b1;
                        r_state    <= S_I_WAIT;
                    end else begin
                        r_line_col <= r_line_col + 1'b1;
                        r_cnt      <= r_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    o_input_rd_en  <= 1'b0;
                    o_weight_rd_en <= 1'b0;
                    o_done         <= 1'b1;
                    r_state        <= S_DONE;
                end

                default: begin
                    r_state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
