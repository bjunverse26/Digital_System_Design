`timescale 1ns / 1ps

module srcnn84_line_buffer #(
    parameter DATA_WIDTH   = 16,
    parameter IMAGE_WIDTH  = 150,
    parameter IMAGE_HEIGHT = 150,
    parameter KERNEL_SIZE  = 3
) (
    input wire                           i_clk,
    input wire                           i_rstn,

    input wire                           i_clear,

    // Input pixel stream with zero padding already included.
    input wire                           i_input_valid,
    input wire signed [DATA_WIDTH-1:0]   i_input_data,

    output reg                           o_window_valid,
    output reg [$clog2(IMAGE_WIDTH)-1:0] o_out_col,

    output reg signed [DATA_WIDTH-1:0]   o_window_00,
    output reg signed [DATA_WIDTH-1:0]   o_window_01,
    output reg signed [DATA_WIDTH-1:0]   o_window_02,
    output reg signed [DATA_WIDTH-1:0]   o_window_10,
    output reg signed [DATA_WIDTH-1:0]   o_window_11,
    output reg signed [DATA_WIDTH-1:0]   o_window_12,
    output reg signed [DATA_WIDTH-1:0]   o_window_20,
    output reg signed [DATA_WIDTH-1:0]   o_window_21,
    output reg signed [DATA_WIDTH-1:0]   o_window_22
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam PAD_SIZE      = KERNEL_SIZE / 2;
    localparam PADDED_WIDTH  = IMAGE_WIDTH + (2 * PAD_SIZE);
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + (2 * PAD_SIZE);
    localparam COL_WIDTH     = $clog2(PADDED_WIDTH);
    localparam ROW_WIDTH     = $clog2(PADDED_HEIGHT);

    //--------------------------------------------------------------------------
    // Line memories and horizontal delay registers
    //--------------------------------------------------------------------------

    // Store the previous two padded rows.
    // The current row is handled by i_input_data and bottom delay registers.
    reg signed [DATA_WIDTH-1:0] r_prev2_line [0:PADDED_WIDTH-1];
    reg signed [DATA_WIDTH-1:0] r_prev1_line [0:PADDED_WIDTH-1];

    // Current position in the padded input stream.
    reg [COL_WIDTH-1:0] r_col;
    reg [ROW_WIDTH-1:0] r_row;

    // Horizontal delay registers.
    // d1 holds col-1, and d2 holds col-2 for each window row.
    reg signed [DATA_WIDTH-1:0] r_top_d1;
    reg signed [DATA_WIDTH-1:0] r_top_d2;
    reg signed [DATA_WIDTH-1:0] r_mid_d1;
    reg signed [DATA_WIDTH-1:0] r_mid_d2;
    reg signed [DATA_WIDTH-1:0] r_bot_d1;
    reg signed [DATA_WIDTH-1:0] r_bot_d2;

    wire signed [DATA_WIDTH-1:0] w_prev2_pixel;
    wire signed [DATA_WIDTH-1:0] w_prev1_pixel;
    wire                         w_valid_window;

    // Read the same-column pixels from the previous two rows.
    assign w_prev1_pixel = r_prev1_line[r_col];
    assign w_prev2_pixel = r_prev2_line[r_col];

    // A complete 3x3 window is available after two rows and two columns.
    assign w_valid_window = i_input_valid &&
                            (r_row >= (KERNEL_SIZE - 1)) &&
                            (r_col >= (KERNEL_SIZE - 1));

    integer i;

    //--------------------------------------------------------------------------
    // Streaming line-buffer update and 3x3 window generation
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_col          <= {COL_WIDTH{1'b0}};
            r_row          <= {ROW_WIDTH{1'b0}};

            r_top_d1       <= {DATA_WIDTH{1'b0}};
            r_top_d2       <= {DATA_WIDTH{1'b0}};
            r_mid_d1       <= {DATA_WIDTH{1'b0}};
            r_mid_d2       <= {DATA_WIDTH{1'b0}};
            r_bot_d1       <= {DATA_WIDTH{1'b0}};
            r_bot_d2       <= {DATA_WIDTH{1'b0}};

            o_window_valid <= 1'b0;
            o_out_col      <= {$clog2(IMAGE_WIDTH){1'b0}};

            o_window_00    <= {DATA_WIDTH{1'b0}};
            o_window_01    <= {DATA_WIDTH{1'b0}};
            o_window_02    <= {DATA_WIDTH{1'b0}};
            o_window_10    <= {DATA_WIDTH{1'b0}};
            o_window_11    <= {DATA_WIDTH{1'b0}};
            o_window_12    <= {DATA_WIDTH{1'b0}};
            o_window_20    <= {DATA_WIDTH{1'b0}};
            o_window_21    <= {DATA_WIDTH{1'b0}};
            o_window_22    <= {DATA_WIDTH{1'b0}};

            for (i = 0; i < PADDED_WIDTH; i = i + 1) begin
                r_prev2_line[i] <= {DATA_WIDTH{1'b0}};
                r_prev1_line[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (i_clear) begin
                r_col          <= {COL_WIDTH{1'b0}};
                r_row          <= {ROW_WIDTH{1'b0}};

                r_top_d1       <= {DATA_WIDTH{1'b0}};
                r_top_d2       <= {DATA_WIDTH{1'b0}};
                r_mid_d1       <= {DATA_WIDTH{1'b0}};
                r_mid_d2       <= {DATA_WIDTH{1'b0}};
                r_bot_d1       <= {DATA_WIDTH{1'b0}};
                r_bot_d2       <= {DATA_WIDTH{1'b0}};

                o_window_valid <= 1'b0;
                o_out_col      <= {$clog2(IMAGE_WIDTH){1'b0}};

                for (i = 0; i < PADDED_WIDTH; i = i + 1) begin
                    r_prev2_line[i] <= {DATA_WIDTH{1'b0}};
                    r_prev1_line[i] <= {DATA_WIDTH{1'b0}};
                end
            end else begin
                o_window_valid <= w_valid_window;

                if (w_valid_window) begin
                    // r_col points to the rightmost column of the current 3x3 window.
                    o_out_col   <= r_col - (KERNEL_SIZE - 1);

                    // Assemble the 3x3 window.
                    o_window_00 <= r_top_d2;
                    o_window_01 <= r_top_d1;
                    o_window_02 <= w_prev2_pixel;

                    o_window_10 <= r_mid_d2;
                    o_window_11 <= r_mid_d1;
                    o_window_12 <= w_prev1_pixel;

                    o_window_20 <= r_bot_d2;
                    o_window_21 <= r_bot_d1;
                    o_window_22 <= i_input_data;
                end

                if (i_input_valid) begin
                    // Vertical update at the current column:
                    // prev2 <= prev1, prev1 <= current input.
                    r_prev2_line[r_col] <= w_prev1_pixel;
                    r_prev1_line[r_col] <= i_input_data;

                    if (r_col == {COL_WIDTH{1'b0}}) begin
                        // Start of a new row: clear left-side history.
                        r_top_d2 <= {DATA_WIDTH{1'b0}};
                        r_top_d1 <= w_prev2_pixel;

                        r_mid_d2 <= {DATA_WIDTH{1'b0}};
                        r_mid_d1 <= w_prev1_pixel;

                        r_bot_d2 <= {DATA_WIDTH{1'b0}};
                        r_bot_d1 <= i_input_data;
                    end else begin
                        // Horizontal shift:
                        // previous col-1 becomes col-2,
                        // current column becomes col-1 for the next cycle.
                        r_top_d2 <= r_top_d1;
                        r_top_d1 <= w_prev2_pixel;

                        r_mid_d2 <= r_mid_d1;
                        r_mid_d1 <= w_prev1_pixel;

                        r_bot_d2 <= r_bot_d1;
                        r_bot_d1 <= i_input_data;
                    end

                    // Advance padded image coordinates.
                    if (r_col == PADDED_WIDTH - 1) begin
                        r_col <= {COL_WIDTH{1'b0}};

                        if (r_row == PADDED_HEIGHT - 1) begin
                            r_row <= {ROW_WIDTH{1'b0}};
                        end else begin
                            r_row <= r_row + 1'b1;
                        end
                    end else begin
                        r_col <= r_col + 1'b1;
                    end
                end
            end
        end
    end

endmodule
