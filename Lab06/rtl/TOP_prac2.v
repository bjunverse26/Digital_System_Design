//==============================================================================
// File Name   : TOP_prac2.v
// Project     : Digital System Design - Lab06
// Author      : Beomjun Kim
// Description : Multi-channel output-stationary 3x3 convolution engine.
// Notes       : - Reuses one line buffer and one PE across input channels.
//               - Accumulates channel-wise partial sums by output position.
//               - Emits final outputs only when the last input channel is done.
//               - Delays output index to match PE pipeline latency.
//==============================================================================

`timescale 1ns / 1ps

module TOP_prac2 #(
    parameter INPUT_WIDTH   = 5,
    parameter INPUT_HEIGHT  = 5,
    parameter WEIGHT_WIDTH  = 3,
    parameter WEIGHT_HEIGHT = 3,
    parameter DATA_WIDTH    = 16,
    parameter LINE_WIDTH    = INPUT_WIDTH,
    parameter KERNEL_SIZE   = WEIGHT_HEIGHT
) (
    input  wire                             i_clk,
    input  wire                             i_rstn,

    // Current input channel index.
    input  wire [1:0]                       i_ch,

    // Asserted when the line buffer has enough pixels to start one output row.
    input  wire                             i_line_done,

    // Streaming input feature-map interface.
    input  wire                             i_input_valid,
    input  wire signed [DATA_WIDTH-1:0]     i_input_data,

    // Streaming kernel load interface. Weights are loaded in row-major order
    // for the current input channel.
    input  wire                             i_weight_valid,
    input  wire signed [DATA_WIDTH-1:0]     i_weight_data,

    // Final convolution output interface. Valid only on LAST_CH.
    output wire                             o_output_valid,
    output wire signed [(2*DATA_WIDTH)-1:0] o_output,

    // One-cycle pulse requesting the next input line.
    output wire                             o_line_rd_done,

    // One-cycle pulse asserted when the current channel is fully processed.
    output wire                             o_ch_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam OUTPUT_WIDTH  = INPUT_WIDTH  - WEIGHT_WIDTH  + 1;
    localparam OUTPUT_HEIGHT = INPUT_HEIGHT - WEIGHT_HEIGHT + 1;
    localparam WEIGHT_NUM    = WEIGHT_WIDTH * WEIGHT_HEIGHT;
    localparam OUTPUT_NUM    = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam OUTPUT_COL_WIDTH = (OUTPUT_WIDTH  > 1) ? $clog2(OUTPUT_WIDTH)  : 1;
    localparam OUTPUT_ROW_WIDTH = (OUTPUT_HEIGHT > 1) ? $clog2(OUTPUT_HEIGHT) : 1;
    localparam OUTPUT_IDX_WIDTH = (OUTPUT_NUM   > 1) ? $clog2(OUTPUT_NUM)    : 1;

    // Current implementation assumes three input channels: ch0, ch1, ch2.
    localparam LAST_CH       = 2'd2;

    //--------------------------------------------------------------------------
    // Kernel and partial-sum storage
    //--------------------------------------------------------------------------

    // Kernel register file for the current input channel.
    // Index order follows row-major 3x3 layout.
    reg signed [DATA_WIDTH-1:0]     r_weight [0:WEIGHT_NUM-1];

    // Output-stationary partial sums.
    // Each entry corresponds to one output pixel position.
    reg signed [(2*DATA_WIDTH)-1:0] r_psum   [0:OUTPUT_NUM-1];

    //--------------------------------------------------------------------------
    // Row/column control registers
    //--------------------------------------------------------------------------

    // Number of loaded kernel coefficients for the current channel.
    reg [3:0] r_weight_cnt;

    // PE enable. Held high while one output row is being evaluated.
    reg       r_mac_en;

    // Horizontal 3x3 window position within the current output row.
    reg [OUTPUT_COL_WIDTH-1:0] r_line_col;

    // Current output row index.
    reg [OUTPUT_ROW_WIDTH-1:0] r_out_row;

    //--------------------------------------------------------------------------
    // Output-index pipeline
    //--------------------------------------------------------------------------

    // The PE has a 5-stage datapath from i_mac_en/window input to output valid.
    // Delay the output index so the accumulation address matches PE output data.
    reg [OUTPUT_IDX_WIDTH-1:0] r_out_idx_d0;
    reg [OUTPUT_IDX_WIDTH-1:0] r_out_idx_d1;
    reg [OUTPUT_IDX_WIDTH-1:0] r_out_idx_d2;
    reg [OUTPUT_IDX_WIDTH-1:0] r_out_idx_d3;
    reg [OUTPUT_IDX_WIDTH-1:0] r_out_idx_d4;

    //--------------------------------------------------------------------------
    // Output registers
    //--------------------------------------------------------------------------

    reg                             r_output_valid;
    reg signed [(2*DATA_WIDTH)-1:0] r_output;
    reg                             r_ch_done;

    //--------------------------------------------------------------------------
    // Line-buffer window wires
    //--------------------------------------------------------------------------

    wire signed [DATA_WIDTH-1:0] w_window_00;
    wire signed [DATA_WIDTH-1:0] w_window_01;
    wire signed [DATA_WIDTH-1:0] w_window_02;
    wire signed [DATA_WIDTH-1:0] w_window_10;
    wire signed [DATA_WIDTH-1:0] w_window_11;
    wire signed [DATA_WIDTH-1:0] w_window_12;
    wire signed [DATA_WIDTH-1:0] w_window_20;
    wire signed [DATA_WIDTH-1:0] w_window_21;
    wire signed [DATA_WIDTH-1:0] w_window_22;

    //--------------------------------------------------------------------------
    // Internal control wires
    //--------------------------------------------------------------------------

    wire                             w_last_col;
    wire                             w_last_row;
    wire                             w_line_shift;
    wire [OUTPUT_IDX_WIDTH-1:0]      w_out_idx;

    wire signed [(2*DATA_WIDTH)-1:0] w_pe_output;
    wire                             w_pe_output_valid;
    wire [OUTPUT_IDX_WIDTH-1:0]      w_pe_out_idx;
    wire signed [(2*DATA_WIDTH)-1:0] w_accum;

    // End of the current output row.
    assign w_last_col = r_mac_en && (r_line_col == OUTPUT_WIDTH - 1);

    // Last output row of the current channel.
    assign w_last_row = (r_out_row == OUTPUT_HEIGHT - 1);

    // Shift line buffer only between output rows.
    assign w_line_shift = w_last_col && !w_last_row;

    // Current output position before PE pipeline latency.
    assign w_out_idx = (r_out_row * OUTPUT_WIDTH) + r_line_col;

    // Output position aligned with PE output valid.
    assign w_pe_out_idx = r_out_idx_d4;

    // First channel initializes psum. Later channels accumulate onto psum.
    assign w_accum = (i_ch == 2'd0) ? w_pe_output
                                    : r_psum[w_pe_out_idx] + w_pe_output;

    assign o_line_rd_done = w_line_shift;
    assign o_output_valid = r_output_valid;
    assign o_output       = r_output;
    assign o_ch_done      = r_ch_done;

    integer i;

    //--------------------------------------------------------------------------
    // Kernel load, window scan control, and output-index delay
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_weight_cnt <= 4'd0;
            r_mac_en     <= 1'b0;
            r_line_col   <= {OUTPUT_COL_WIDTH{1'b0}};
            r_out_row    <= {OUTPUT_ROW_WIDTH{1'b0}};

            r_out_idx_d0 <= {OUTPUT_IDX_WIDTH{1'b0}};
            r_out_idx_d1 <= {OUTPUT_IDX_WIDTH{1'b0}};
            r_out_idx_d2 <= {OUTPUT_IDX_WIDTH{1'b0}};
            r_out_idx_d3 <= {OUTPUT_IDX_WIDTH{1'b0}};
            r_out_idx_d4 <= {OUTPUT_IDX_WIDTH{1'b0}};

            for (i = 0; i < WEIGHT_NUM; i = i + 1) begin
                r_weight[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Reset weight loading state at the end of each input channel.
            if (r_ch_done) begin
                r_weight_cnt <= 4'd0;
            end

            // Load one channel's kernel coefficients. Additional valid pulses
            // after WEIGHT_NUM coefficients are ignored.
            else if (i_weight_valid && (r_weight_cnt < WEIGHT_NUM)) begin
                r_weight[r_weight_cnt] <= i_weight_data;
                r_weight_cnt           <= r_weight_cnt + 1'b1;
            end

            // Start one output-row MAC burst when the line buffer is ready.
            if (!r_mac_en && i_line_done) begin
                r_mac_en   <= 1'b1;
                r_line_col <= {OUTPUT_COL_WIDTH{1'b0}};
            end

            // Advance the sliding window while PE is enabled.
            else if (r_mac_en) begin
                if (r_line_col == OUTPUT_WIDTH - 1) begin
                    r_mac_en   <= 1'b0;
                    r_line_col <= {OUTPUT_COL_WIDTH{1'b0}};

                    if (r_out_row == OUTPUT_HEIGHT - 1) begin
                        r_out_row <= {OUTPUT_ROW_WIDTH{1'b0}};
                    end else begin
                        r_out_row <= r_out_row + 1'b1;
                    end
                end else begin
                    r_line_col <= r_line_col + 1'b1;
                end
            end

            // Align output index with PE output latency.
            r_out_idx_d0 <= w_out_idx;
            r_out_idx_d1 <= r_out_idx_d0;
            r_out_idx_d2 <= r_out_idx_d1;
            r_out_idx_d3 <= r_out_idx_d2;
            r_out_idx_d4 <= r_out_idx_d3;
        end
    end

    //--------------------------------------------------------------------------
    // Partial-sum accumulation and final output generation
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_output_valid <= 1'b0;
            r_output       <= {(2*DATA_WIDTH){1'b0}};
            r_ch_done      <= 1'b0;

            for (i = 0; i < OUTPUT_NUM; i = i + 1) begin
                r_psum[i] <= {(2*DATA_WIDTH){1'b0}};
            end
        end else begin
            // Default pulse outputs.
            r_output_valid <= 1'b0;
            r_ch_done      <= 1'b0;

            // Accumulate PE result into the output-stationary psum buffer.
            if (w_pe_output_valid) begin
                r_psum[w_pe_out_idx] <= w_accum;

                // Emit final output only after the last input channel is added.
                if (i_ch == LAST_CH) begin
                    r_output_valid <= 1'b1;
                    r_output       <= w_accum;
                end

                // Current channel is complete when the last output position is
                // written back.
                if (w_pe_out_idx == OUTPUT_NUM - 1) begin
                    r_ch_done <= 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // 3-line sliding window buffer
    //--------------------------------------------------------------------------

    line_buffer #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LINE_WIDTH  (LINE_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer (
        .i_clk         (i_clk),
        .i_rstn        (i_rstn),
        .i_clear       (r_ch_done),

        .i_input_valid (i_input_valid),
        .i_input_data  (i_input_data),

        .i_line_col    (r_line_col),
        .i_line_shift  (w_line_shift),

        .o_window_00   (w_window_00),
        .o_window_01   (w_window_01),
        .o_window_02   (w_window_02),
        .o_window_10   (w_window_10),
        .o_window_11   (w_window_11),
        .o_window_12   (w_window_12),
        .o_window_20   (w_window_20),
        .o_window_21   (w_window_21),
        .o_window_22   (w_window_22)
    );

    //--------------------------------------------------------------------------
    // 3x3 convolution processing element
    //--------------------------------------------------------------------------

    pe #(
        .KERNEL_SIZE (KERNEL_SIZE),
        .DATA_WIDTH  (DATA_WIDTH)
    ) u_pe (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),

        .i_mac_en       (r_mac_en),

        .i_window_00    (w_window_00),
        .i_window_01    (w_window_01),
        .i_window_02    (w_window_02),
        .i_window_10    (w_window_10),
        .i_window_11    (w_window_11),
        .i_window_12    (w_window_12),
        .i_window_20    (w_window_20),
        .i_window_21    (w_window_21),
        .i_window_22    (w_window_22),

        .i_weight_00    (r_weight[0]),
        .i_weight_01    (r_weight[1]),
        .i_weight_02    (r_weight[2]),
        .i_weight_10    (r_weight[3]),
        .i_weight_11    (r_weight[4]),
        .i_weight_12    (r_weight[5]),
        .i_weight_20    (r_weight[6]),
        .i_weight_21    (r_weight[7]),
        .i_weight_22    (r_weight[8]),

        .o_output_data  (w_pe_output),
        .o_output_valid (w_pe_output_valid)
    );

endmodule
