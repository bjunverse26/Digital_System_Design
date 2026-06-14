`timescale 1ns / 1ps

module srcnn88_controller #(
    parameter IMAGE_WIDTH      = 150,
    parameter IMAGE_HEIGHT     = 150,
    parameter KERNEL_SIZE      = 3,
    parameter NUM_IMAGES       = 3,
    parameter INPUT_ADDR_WIDTH = 15,
    parameter DRAIN_CYCLES     = 6
) (
    input wire                           i_clk,
    input wire                           i_rstn,

    // Starts one complete SRCNN processing sequence.
    input wire                           i_start,

    // Current layer/image schedule.
    output reg  [1:0]                    o_layer,
    output reg  [1:0]                    o_image_idx,
    output reg                           o_layer_start,

    // Input-image BRAM read interface.
    output reg                           o_input_rd_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]   o_input_rd_addr,

    // Line-buffer control interface.
    output reg                           o_line_clear,
    output reg                           o_line_input_valid,
    output reg                           o_line_input_zero,
    output reg                           o_line_shift,

    // PE enable. Asserted once per output pixel.
    output reg                           o_mac_en,

    // Shift the line-buffer window after the current output column is issued.
    output wire                          o_window_shift,

    // Pulses when one image is complete.
    output reg                           o_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam PAD_SIZE       = KERNEL_SIZE / 2;

    // Padded stream size.
    // For IMAGE_WIDTH/HEIGHT = 150 and KERNEL_SIZE = 3:
    //   LINE_WIDTH    = 152
    //   PADDED_HEIGHT = 152
    localparam LINE_WIDTH     = IMAGE_WIDTH + (KERNEL_SIZE - 1);
    localparam PADDED_HEIGHT  = IMAGE_HEIGHT + (KERNEL_SIZE - 1);

    localparam LINE_CNT_WIDTH    = $clog2(LINE_WIDTH + 1);
    localparam ROW_CNT_WIDTH     = $clog2(PADDED_HEIGHT + 1);
    localparam FILL_CNT_WIDTH    = $clog2(KERNEL_SIZE + 1);
    localparam DRAIN_CNT_WIDTH   = $clog2(DRAIN_CYCLES + 1);

    // FSM states.
    localparam S_IDLE     = 3'd0;
    localparam S_INIT     = 3'd1;
    localparam S_PRELOAD  = 3'd2;
    localparam S_FILL     = 3'd3;
    localparam S_RUN      = 3'd4;
    localparam S_DRAIN    = 3'd5;
    localparam S_DONE     = 3'd6;

    localparam LAYER_1    = 2'd0;
    localparam LAYER_3    = 2'd2;

    //--------------------------------------------------------------------------
    // State and counters
    //--------------------------------------------------------------------------

    reg [2:0] r_state;
    reg [2:0] w_next_state;

    // Current position in the padded input stream.
    reg [ROW_CNT_WIDTH-1:0]       r_stream_row;
    reg [LINE_CNT_WIDTH-1:0]      r_stream_col;

    // Current output pixel position.
    reg [$clog2(IMAGE_HEIGHT):0]  r_output_row;
    reg [$clog2(IMAGE_WIDTH):0]   r_run_col;

    // Fill control.
    // First output row requires KERNEL_SIZE rows to fill the line buffer.
    // After that, only one new padded row is loaded per output row.
    reg [FILL_CNT_WIDTH-1:0]      r_fill_rows;
    reg [FILL_CNT_WIDTH-1:0]      r_fill_row_cnt;
    reg                           r_fill_issued;

    // Wait cycles after all MACs are issued.
    reg [DRAIN_CNT_WIDTH-1:0]     r_drain_cnt;

    // One-cycle delay to align BRAM read data with line-buffer input.
    reg                           r_issue_valid_d;
    reg                           r_issue_zero_d;

    //--------------------------------------------------------------------------
    // Padded stream decode
    //--------------------------------------------------------------------------

    wire w_pad_row;
    wire w_pad_col;
    wire w_stream_zero;
    wire [INPUT_ADDR_WIDTH-1:0] w_stream_addr;

    // Detect whether the current padded-stream position is padding.
    assign w_pad_row = (r_stream_row < PAD_SIZE) ||
                       (r_stream_row >= (IMAGE_HEIGHT + PAD_SIZE));
    assign w_pad_col = (r_stream_col < PAD_SIZE) ||
                       (r_stream_col >= (IMAGE_WIDTH + PAD_SIZE));

    // Padding pixels are generated as zero instead of reading BRAM.
    assign w_stream_zero = w_pad_row || w_pad_col;

    // BRAM address for non-padding image pixels.
    assign w_stream_addr = ((r_stream_row - PAD_SIZE) * IMAGE_WIDTH) +
                           (r_stream_col - PAD_SIZE);

    //--------------------------------------------------------------------------
    // FSM transition conditions
    //--------------------------------------------------------------------------

    wire w_init_done;
    wire w_param_ready;
    wire w_linebuf_ready;
    wire w_run_row_done;
    wire w_next_group;
    wire w_all_issued;
    wire w_pipe_empty;
    wire w_last_layer;
    wire w_last_image;
    wire w_window_shift;

    assign w_init_done     = 1'b1;
    assign w_param_ready   = 1'b1;

    // The line buffer is ready after the required fill rows are issued.
    assign w_linebuf_ready = r_fill_issued;

    // One output row is done after IMAGE_WIDTH MAC issues.
    assign w_run_row_done  = (r_run_col >= IMAGE_WIDTH - 1);

    // Move to the next output row if the current row is done.
    assign w_next_group    = w_run_row_done && (r_output_row < IMAGE_HEIGHT - 1);

    // Entire image has been issued when the last output row is done.
    assign w_all_issued    = w_run_row_done && (r_output_row >= IMAGE_HEIGHT - 1);

    // Drain cycles allow downstream pipeline data to flush.
    assign w_pipe_empty    = (r_drain_cnt >= DRAIN_CYCLES - 1);

    assign w_last_layer    = (o_layer == LAYER_3);
    assign w_last_image    = (o_image_idx >= NUM_IMAGES - 1);
    assign w_window_shift  = (r_state == S_RUN) && o_mac_en;

    assign o_window_shift  = w_window_shift;

    //--------------------------------------------------------------------------
    // 1. State register
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state <= S_IDLE;
        end else begin
            r_state <= w_next_state;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Next-state logic
    //--------------------------------------------------------------------------

    always @(*) begin
        w_next_state = r_state;

        case (r_state)
            S_IDLE: begin
                // Wait for a start request.
                if (i_start) begin
                    w_next_state = S_INIT;
                end
            end

            S_INIT: begin
                // Clear line buffer and reset per-layer counters.
                if (w_init_done) begin
                    w_next_state = S_PRELOAD;
                end
            end

            S_PRELOAD: begin
                // Prepare fill amount for the current output row.
                if (w_param_ready) begin
                    w_next_state = S_FILL;
                end
            end

            S_FILL: begin
                // Feed padded input pixels into the line buffer.
                if (w_linebuf_ready) begin
                    w_next_state = S_RUN;
                end
            end

            S_RUN: begin
                // Issue one MAC per output column.
                if (w_all_issued) begin
                    w_next_state = S_DRAIN;
                end else if (w_next_group) begin
                    w_next_state = S_PRELOAD;
                end
            end

            S_DRAIN: begin
                // Wait for downstream pipeline latency.
                if (w_pipe_empty) begin
                    w_next_state = S_DONE;
                end
            end

            S_DONE: begin
                // Move to next layer/image, or return to idle after all work.
                if (w_last_layer && w_last_image) begin
                    w_next_state = S_IDLE;
                end else begin
                    w_next_state = S_INIT;
                end
            end

            default: begin
                w_next_state = S_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // 3. Sequential output and counter logic
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_stream_row       <= {ROW_CNT_WIDTH{1'b0}};
            r_stream_col       <= {LINE_CNT_WIDTH{1'b0}};
            r_output_row       <= {($clog2(IMAGE_HEIGHT)+1){1'b0}};
            r_run_col          <= {($clog2(IMAGE_WIDTH)+1){1'b0}};
            r_fill_rows        <= {FILL_CNT_WIDTH{1'b0}};
            r_fill_row_cnt     <= {FILL_CNT_WIDTH{1'b0}};
            r_fill_issued      <= 1'b0;
            r_drain_cnt        <= {DRAIN_CNT_WIDTH{1'b0}};
            r_issue_valid_d    <= 1'b0;
            r_issue_zero_d     <= 1'b0;

            o_layer            <= LAYER_1;
            o_image_idx        <= 2'd0;
            o_layer_start      <= 1'b0;
            o_input_rd_en      <= 1'b0;
            o_input_rd_addr    <= {INPUT_ADDR_WIDTH{1'b0}};
            o_line_clear       <= 1'b0;
            o_line_input_valid <= 1'b0;
            o_line_input_zero  <= 1'b0;
            o_line_shift       <= 1'b0;
            o_mac_en           <= 1'b0;
            o_done             <= 1'b0;
        end else begin
            // Default pulse outputs to zero.
            o_layer_start      <= 1'b0;
            o_input_rd_en      <= 1'b0;
            o_line_clear       <= 1'b0;
            o_line_shift       <= 1'b0;
            o_mac_en           <= 1'b0;
            o_done             <= 1'b0;

            // Delayed issue signals are sent to the line buffer.
            // This matches synchronous BRAM read latency.
            o_line_input_valid <= r_issue_valid_d;
            o_line_input_zero  <= r_issue_zero_d;
            r_issue_valid_d    <= 1'b0;
            r_issue_zero_d     <= 1'b0;

            case (r_state)
                S_IDLE: begin
                    // Reset frame/layer traversal counters.
                    r_stream_row       <= {ROW_CNT_WIDTH{1'b0}};
                    r_stream_col       <= {LINE_CNT_WIDTH{1'b0}};
                    r_output_row       <= {($clog2(IMAGE_HEIGHT)+1){1'b0}};
                    r_run_col          <= {($clog2(IMAGE_WIDTH)+1){1'b0}};
                    r_fill_rows        <= {FILL_CNT_WIDTH{1'b0}};
                    r_fill_row_cnt     <= {FILL_CNT_WIDTH{1'b0}};
                    r_fill_issued      <= 1'b0;
                    r_drain_cnt        <= {DRAIN_CNT_WIDTH{1'b0}};

                    o_layer            <= LAYER_1;
                    o_image_idx        <= 2'd0;
                    o_input_rd_addr    <= {INPUT_ADDR_WIDTH{1'b0}};

                    if (i_start) begin
                        o_layer_start <= 1'b1;
                    end
                end

                S_INIT: begin
                    // Start a new layer pass.
                    o_line_clear <= 1'b1;
                    r_stream_row <= {ROW_CNT_WIDTH{1'b0}};
                    r_stream_col <= {LINE_CNT_WIDTH{1'b0}};
                    r_output_row <= {($clog2(IMAGE_HEIGHT)+1){1'b0}};
                    r_run_col    <= {($clog2(IMAGE_WIDTH)+1){1'b0}};
                end

                S_PRELOAD: begin
                    // Decide how many padded rows must be fed before running.
                    r_stream_col       <= {LINE_CNT_WIDTH{1'b0}};
                    r_fill_row_cnt     <= {FILL_CNT_WIDTH{1'b0}};
                    r_fill_issued      <= 1'b0;

                    if (r_output_row == {($clog2(IMAGE_HEIGHT)+1){1'b0}}) begin
                        // First output row: fill the whole 3-row window.
                        r_fill_rows <= KERNEL_SIZE;
                    end else begin
                        // Next output rows: shift line buffer and load one new row.
                        r_fill_rows  <= {{(FILL_CNT_WIDTH-1){1'b0}}, 1'b1};
                        o_line_shift <= 1'b1;
                    end
                end

                S_FILL: begin
                    if (!r_fill_issued) begin
                        // Issue one padded-stream pixel.
                        // Padding locations are marked zero and do not read BRAM.
                        r_issue_valid_d <= 1'b1;
                        r_issue_zero_d  <= w_stream_zero;

                        if (!w_stream_zero) begin
                            o_input_rd_en   <= 1'b1;
                            o_input_rd_addr <= w_stream_addr;
                        end

                        // Advance padded-stream column/row.
                        if (r_stream_col >= LINE_WIDTH - 1) begin
                            r_stream_col <= {LINE_CNT_WIDTH{1'b0}};
                            r_stream_row <= r_stream_row + 1'b1;

                            if (r_fill_row_cnt >= r_fill_rows - 1) begin
                                r_fill_issued <= 1'b1;
                            end else begin
                                r_fill_row_cnt <= r_fill_row_cnt + 1'b1;
                            end
                        end else begin
                            r_stream_col <= r_stream_col + 1'b1;
                        end
                    end
                end

                S_RUN: begin
                    // Enable MAC once per output pixel.
                    o_mac_en <= 1'b1;

                    // Sweep one output row from col 0 to IMAGE_WIDTH-1.
                    if (r_run_col >= IMAGE_WIDTH - 1) begin
                        r_run_col <= {($clog2(IMAGE_WIDTH)+1){1'b0}};

                        if (r_output_row < IMAGE_HEIGHT - 1) begin
                            r_output_row <= r_output_row + 1'b1;
                        end
                    end else begin
                        r_run_col <= r_run_col + 1'b1;
                    end
                end

                S_DRAIN: begin
                    // Allow remaining pipeline results to drain.
                    if (r_drain_cnt >= DRAIN_CYCLES - 1) begin
                        r_drain_cnt <= {DRAIN_CNT_WIDTH{1'b0}};
                    end else begin
                        r_drain_cnt <= r_drain_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    if (w_last_layer) begin
                        // Current image is complete after layer 3.
                        o_done <= 1'b1;

                        if (!w_last_image) begin
                            // Move to the next image and restart at layer 1.
                            o_image_idx   <= o_image_idx + 1'b1;
                            o_layer       <= LAYER_1;
                            o_layer_start <= 1'b1;
                        end
                    end else begin
                        // Move to the next SRCNN layer.
                        o_layer       <= o_layer + 1'b1;
                        o_layer_start <= 1'b1;
                    end
                end

                default: begin
                    r_stream_row       <= {ROW_CNT_WIDTH{1'b0}};
                    r_stream_col       <= {LINE_CNT_WIDTH{1'b0}};
                    r_output_row       <= {($clog2(IMAGE_HEIGHT)+1){1'b0}};
                    r_run_col          <= {($clog2(IMAGE_WIDTH)+1){1'b0}};
                    r_fill_rows        <= {FILL_CNT_WIDTH{1'b0}};
                    r_fill_row_cnt     <= {FILL_CNT_WIDTH{1'b0}};
                    r_fill_issued      <= 1'b0;
                    r_drain_cnt        <= {DRAIN_CNT_WIDTH{1'b0}};
                    o_layer            <= LAYER_1;
                    o_image_idx        <= 2'd0;
                end
            endcase
        end
    end

endmodule
