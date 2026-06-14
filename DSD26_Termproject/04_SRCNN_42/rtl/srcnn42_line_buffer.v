`timescale 1ns / 1ps

module srcnn42_line_buffer #(
    parameter DATA_WIDTH  = 16,
    parameter IMAGE_WIDTH = 150,
    parameter KERNEL_SIZE = 3
) (
    input wire                           i_clk,
    input wire                           i_rstn,

    input wire                           i_clear,

    // Input stream.
    // The input word contains two horizontally adjacent pixels:
    //   i_input_data[15:0]  = even-column pixel
    //   i_input_data[31:16] = odd-column pixel
    input wire                           i_input_valid,
    input wire signed [(2*DATA_WIDTH)-1:0] i_input_data,

    // Row-shift and window-shift control.
    input wire                           i_line_shift,
    input wire                           i_window_shift,
    input wire                           i_window_shift_two,

    // Current 3x3 window. Outputs are fixed slices from scan rows.
    output reg signed [DATA_WIDTH-1:0]   o_window_00,
    output reg signed [DATA_WIDTH-1:0]   o_window_01,
    output reg signed [DATA_WIDTH-1:0]   o_window_02,
    output reg signed [DATA_WIDTH-1:0]   o_window_10,
    output reg signed [DATA_WIDTH-1:0]   o_window_11,
    output reg signed [DATA_WIDTH-1:0]   o_window_12,
    output reg signed [DATA_WIDTH-1:0]   o_window_20,
    output reg signed [DATA_WIDTH-1:0]   o_window_21,
    output reg signed [DATA_WIDTH-1:0]   o_window_22,

    // Extra horizontal taps for the adjacent output column.
    output reg signed [DATA_WIDTH-1:0]   o_window_03,
    output reg signed [DATA_WIDTH-1:0]   o_window_13,
    output reg signed [DATA_WIDTH-1:0]   o_window_23
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam LINE_WIDTH    = IMAGE_WIDTH + (KERNEL_SIZE - 1);
    localparam WORDS_PER_ROW = IMAGE_WIDTH / 2;
    localparam PAIR_WIDTH    = 2 * DATA_WIDTH;
    localparam LINE_BITS     = DATA_WIDTH * LINE_WIDTH;
    localparam CNT_WIDTH     = $clog2((WORDS_PER_ROW * KERNEL_SIZE) + 1);

    //--------------------------------------------------------------------------
    // Internal storage
    //--------------------------------------------------------------------------

    // Packed line buffers. r_line[0] is the top row of the active window.
    reg [LINE_BITS-1:0] r_line [0:KERNEL_SIZE-1];

    // Scan rows shift horizontally during RUN so that the active windows
    // are always located at fixed slices of each row.
    reg [LINE_BITS-1:0] r_scan [0:KERNEL_SIZE-1];

    // Pixel-pair count within the active 3-line buffer context.
    reg [CNT_WIDTH-1:0] r_cnt;

    wire [PAIR_WIDTH-1:0] w_input_pair_ordered;

    integer i;

    // Store the even-column pixel before the odd-column pixel in scan order.
    assign w_input_pair_ordered = {i_input_data[DATA_WIDTH-1:0],
                                   i_input_data[PAIR_WIDTH-1:DATA_WIDTH]};

    //--------------------------------------------------------------------------
    // Line-buffer update
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_cnt <= {CNT_WIDTH{1'b0}};

            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                r_line[i] <= {LINE_BITS{1'b0}};
                r_scan[i] <= {LINE_BITS{1'b0}};
            end
        end else begin
            if (i_clear) begin
                r_cnt <= {CNT_WIDTH{1'b0}};

                for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    r_line[i] <= {LINE_BITS{1'b0}};
                    r_scan[i] <= {LINE_BITS{1'b0}};
                end
            end
            // Shift active 3-line window up by one row.
            // New pixel pairs are loaded into r_line[2] after this cycle.
            else if (i_line_shift) begin
                r_line[0] <= r_line[1];
                r_line[1] <= r_line[2];
                r_line[2] <= {LINE_BITS{1'b0}};
                r_scan[0] <= {LINE_BITS{1'b0}};
                r_scan[1] <= {LINE_BITS{1'b0}};
                r_scan[2] <= {LINE_BITS{1'b0}};

                r_cnt <= WORDS_PER_ROW * (KERNEL_SIZE - 1);
            end

            // Load one packed even/odd pixel pair into the row selected by r_cnt.
            else if (i_input_valid) begin
                if (r_cnt < WORDS_PER_ROW) begin
                    r_line[0] <= {r_line[0][LINE_BITS-PAIR_WIDTH-1:0], w_input_pair_ordered};
                end else if (r_cnt < (WORDS_PER_ROW * 2)) begin
                    r_line[1] <= {r_line[1][LINE_BITS-PAIR_WIDTH-1:0], w_input_pair_ordered};
                end else if (r_cnt < (WORDS_PER_ROW * KERNEL_SIZE)) begin
                    r_line[2] <= {r_line[2][LINE_BITS-PAIR_WIDTH-1:0], w_input_pair_ordered};
                end

                if (r_cnt == (WORDS_PER_ROW * KERNEL_SIZE) - 1) begin
                    r_scan[0] <= r_line[0];
                    r_scan[1] <= r_line[1];
                    r_scan[2] <= {r_line[2][LINE_BITS-PAIR_WIDTH-1:0],
                                  w_input_pair_ordered};
                end

                if (r_cnt < (WORDS_PER_ROW * KERNEL_SIZE)) begin
                    r_cnt <= r_cnt + 1'b1;
                end
            end
            // Move to the next output column/group after computation issue.
            else if (i_window_shift) begin
                for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    if (i_window_shift_two) begin
                        r_scan[i] <= {r_scan[i][LINE_BITS-(2*DATA_WIDTH)-1:0],
                                      {(2*DATA_WIDTH){1'b0}}};
                    end else begin
                        r_scan[i] <= {r_scan[i][LINE_BITS-DATA_WIDTH-1:0],
                                      {DATA_WIDTH{1'b0}}};
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // 3x3 window selection
    //--------------------------------------------------------------------------

    always @(*) begin
        o_window_00 = r_scan[0][((LINE_WIDTH - 2) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_01 = r_scan[0][((LINE_WIDTH - 3) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_02 = r_scan[0][((LINE_WIDTH - 4) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_03 = r_scan[0][((LINE_WIDTH - 5) * DATA_WIDTH) +: DATA_WIDTH];

        o_window_10 = r_scan[1][((LINE_WIDTH - 2) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_11 = r_scan[1][((LINE_WIDTH - 3) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_12 = r_scan[1][((LINE_WIDTH - 4) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_13 = r_scan[1][((LINE_WIDTH - 5) * DATA_WIDTH) +: DATA_WIDTH];

        o_window_20 = r_scan[2][((LINE_WIDTH - 2) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_21 = r_scan[2][((LINE_WIDTH - 3) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_22 = r_scan[2][((LINE_WIDTH - 4) * DATA_WIDTH) +: DATA_WIDTH];
        o_window_23 = r_scan[2][((LINE_WIDTH - 5) * DATA_WIDTH) +: DATA_WIDTH];
    end

endmodule
