`timescale 1ns / 1ps

module srcnn84_pad_insert #(
    parameter DATA_WIDTH   = 16,
    parameter CHANNELS     = 1,
    parameter IMAGE_WIDTH  = 150,
    parameter IMAGE_HEIGHT = 150
) (
    input wire                                    i_clk,
    input wire                                    i_rstn,

    input wire                                    i_clear,
    input wire                                    i_start,

    // Unpadded input stream.
    // For CHANNELS > 1, all channel values for one pixel position are packed.
    input wire                                    i_data_valid,
    input wire signed [(CHANNELS*DATA_WIDTH)-1:0] i_data,

    // Padded output stream.
    // Output order:
    //   top zero row
    //   left zero + image row + right zero
    //   ...
    //   bottom zero row
    output reg                                    o_pad_valid,
    output reg signed [(CHANNELS*DATA_WIDTH)-1:0] o_pad_data,
    output reg                                    o_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    // 1-pixel padding on the left and right side.
    localparam PADDED_WIDTH = IMAGE_WIDTH + 2;

    localparam COL_WIDTH    = $clog2(PADDED_WIDTH + 1);
    localparam ROW_WIDTH    = $clog2(IMAGE_HEIGHT + 1);

    // Padding insertion FSM.
    localparam S_IDLE        = 3'd0;
    localparam S_TOP_ZERO    = 3'd1;
    localparam S_WAIT_ROW    = 3'd2;
    localparam S_LEFT_ZERO   = 3'd3;
    localparam S_ROW_DATA    = 3'd4;
    localparam S_RIGHT_ZERO  = 3'd5;
    localparam S_BOTTOM_ZERO = 3'd6;
    localparam S_DONE        = 3'd7;

    //--------------------------------------------------------------------------
    // Local padding sequencer
    //--------------------------------------------------------------------------

    reg [2:0] r_state;

    // Counts columns while emitting top/bottom zero rows.
    reg [COL_WIDTH-1:0] r_col_count;

    // Counts real image rows already emitted.
    reg [ROW_WIDTH-1:0] r_row_count;

    // Counts real pixels emitted inside the current image row.
    reg [COL_WIDTH-1:0] r_data_count;

    // One-word holding buffer for current row data.
    // r_next_data is used to accept the next input while current data is emitted.
    reg signed [(CHANNELS*DATA_WIDTH)-1:0] r_hold_data;
    reg signed [(CHANNELS*DATA_WIDTH)-1:0] r_next_data;
    reg r_next_valid;

    wire signed [(CHANNELS*DATA_WIDTH)-1:0] w_zero_data =
        {(CHANNELS*DATA_WIDTH){1'b0}};

    //--------------------------------------------------------------------------
    // Emit top/bottom rows and left/right pixels around each feature row
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state      <= S_IDLE;
            r_col_count  <= {COL_WIDTH{1'b0}};
            r_row_count  <= {ROW_WIDTH{1'b0}};
            r_data_count <= {COL_WIDTH{1'b0}};
            r_hold_data  <= w_zero_data;
            r_next_data  <= w_zero_data;
            r_next_valid <= 1'b0;
            o_pad_valid  <= 1'b0;
            o_pad_data   <= w_zero_data;
            o_done       <= 1'b0;
        end else begin
            if (i_clear) begin
                r_state      <= S_IDLE;
                r_col_count  <= {COL_WIDTH{1'b0}};
                r_row_count  <= {ROW_WIDTH{1'b0}};
                r_data_count <= {COL_WIDTH{1'b0}};
                r_hold_data  <= w_zero_data;
                r_next_data  <= w_zero_data;
                r_next_valid <= 1'b0;
                o_pad_valid  <= 1'b0;
                o_pad_data   <= w_zero_data;
                o_done       <= 1'b0;
            end else begin
                // Default outputs. Valid/done are one-cycle pulses.
                o_pad_valid <= 1'b0;
                o_pad_data  <= w_zero_data;
                o_done      <= 1'b0;

                case (r_state)
                    S_IDLE: begin
                        // Wait for a new padding sequence.
                        if (i_start) begin
                            r_state     <= S_TOP_ZERO;
                            r_col_count <= {COL_WIDTH{1'b0}};
                            r_row_count <= {ROW_WIDTH{1'b0}};
                        end
                    end

                    S_TOP_ZERO: begin
                        // Emit the top padding row.
                        o_pad_valid <= 1'b1;
                        o_pad_data  <= w_zero_data;

                        if (r_col_count == PADDED_WIDTH - 1) begin
                            r_col_count <= {COL_WIDTH{1'b0}};
                            r_state     <= S_WAIT_ROW;
                        end else begin
                            r_col_count <= r_col_count + 1'b1;
                        end
                    end

                    S_WAIT_ROW: begin
                        // Wait until the first real pixel of the next row arrives.
                        if (i_data_valid) begin
                            r_hold_data  <= i_data;
                            r_next_data  <= w_zero_data;
                            r_next_valid <= 1'b0;
                            r_data_count <= {COL_WIDTH{1'b0}};
                            r_state      <= S_LEFT_ZERO;
                        end
                    end

                    S_LEFT_ZERO: begin
                        // Emit left padding pixel before real row data.
                        o_pad_valid <= 1'b1;
                        o_pad_data  <= w_zero_data;

                        // If the next real pixel is already available,
                        // store it so ROW_DATA can continue without a gap.
                        if (i_data_valid) begin
                            r_next_data  <= i_data;
                            r_next_valid <= 1'b1;
                        end

                        r_state <= S_ROW_DATA;
                    end

                    S_ROW_DATA: begin
                        // Emit real image/feature-map data for the current row.
                        o_pad_valid <= 1'b1;
                        o_pad_data  <= r_hold_data;

                        // Keep a small one-entry lookahead buffer.
                        // This lets the module absorb i_data while emitting held data.
                        if (r_next_valid) begin
                            r_hold_data  <= r_next_data;
                            r_next_valid <= i_data_valid;

                            if (i_data_valid) begin
                                r_next_data <= i_data;
                            end
                        end else if (i_data_valid) begin
                            r_hold_data <= i_data;
                        end

                        if (r_data_count == IMAGE_WIDTH - 1) begin
                            r_data_count <= {COL_WIDTH{1'b0}};
                            r_state      <= S_RIGHT_ZERO;
                            r_next_valid <= 1'b0;
                        end else begin
                            r_data_count <= r_data_count + 1'b1;
                        end
                    end

                    S_RIGHT_ZERO: begin
                        // Emit right padding pixel after the real row.
                        o_pad_valid <= 1'b1;
                        o_pad_data  <= w_zero_data;

                        if (r_row_count == IMAGE_HEIGHT - 1) begin
                            // Last real row is done. Move to bottom padding row.
                            r_row_count <= {ROW_WIDTH{1'b0}};
                            r_col_count <= {COL_WIDTH{1'b0}};
                            r_state     <= S_BOTTOM_ZERO;
                        end else begin
                            r_row_count <= r_row_count + 1'b1;

                            // If the first pixel of the next row is already available,
                            // start the next row immediately. Otherwise wait.
                            if (i_data_valid) begin
                                r_hold_data  <= i_data;
                                r_next_data  <= w_zero_data;
                                r_next_valid <= 1'b0;
                                r_state      <= S_LEFT_ZERO;
                            end else begin
                                r_state      <= S_WAIT_ROW;
                            end
                        end
                    end

                    S_BOTTOM_ZERO: begin
                        // Emit the bottom padding row.
                        o_pad_valid <= 1'b1;
                        o_pad_data  <= w_zero_data;

                        if (r_col_count == PADDED_WIDTH - 1) begin
                            r_col_count <= {COL_WIDTH{1'b0}};
                            r_state     <= S_DONE;
                        end else begin
                            r_col_count <= r_col_count + 1'b1;
                        end
                    end

                    S_DONE: begin
                        // Padding sequence for one image/frame is complete.
                        o_done  <= 1'b1;
                        r_state <= S_IDLE;
                    end

                    default: begin
                        r_state <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
