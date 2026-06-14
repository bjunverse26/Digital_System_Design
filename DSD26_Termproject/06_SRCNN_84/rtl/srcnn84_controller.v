`timescale 1ns / 1ps

module srcnn84_controller #(
    parameter IMAGE_WIDTH  = 150,
    parameter IMAGE_HEIGHT = 150,
    parameter NUM_IMAGES   = 3
) (
    input  wire                          i_clk,
    input  wire                          i_rstn,
    input  wire                          i_start,

    // Asserted by the downstream datapath when all output pixels
    // for the current image have been flushed.
    input  wire                          i_image_output_done,

    // Clears downstream stream datapath, such as line buffers.
    output wire                          o_clear,

    // Pulses at the first pixel of each padded image stream.
    output wire                          o_stage_start,

    // High while the padded image stream is being generated.
    output wire                          o_stream_active,

    // High only for real image pixels, excluding zero-padding area.
    output wire                          o_stream_real,

    // Current image index.
    output wire [1:0]                    o_image_idx,

    // Current row/column in the padded image stream.
    output wire [$clog2(IMAGE_HEIGHT+2)-1:0] o_stream_row,
    output wire [$clog2(IMAGE_WIDTH+2)-1:0]  o_stream_col,

    // Pulses when one image is complete.
    output reg                           o_done
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    // This controller assumes 1-pixel zero padding for a 3x3 kernel.
    // Therefore, the stream size is (IMAGE_HEIGHT+2) x (IMAGE_WIDTH+2).
    localparam PADDED_WIDTH  = IMAGE_WIDTH + 2;
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + 2;

    localparam ROW_WIDTH     = $clog2(PADDED_HEIGHT);
    localparam COL_WIDTH     = $clog2(PADDED_WIDTH);

    // Image-level FSM states.
    localparam S_IDLE   = 3'd0;
    localparam S_INIT   = 3'd1;
    localparam S_STREAM = 3'd2;
    localparam S_DRAIN  = 3'd3;
    localparam S_DONE   = 3'd4;

    //--------------------------------------------------------------------------
    // State and raster counters
    //--------------------------------------------------------------------------

    reg [2:0] r_state;
    reg [1:0] r_image_idx;

    // Current position in the padded raster scan.
    // Counts from (0,0) to (PADDED_HEIGHT-1, PADDED_WIDTH-1).
    reg [ROW_WIDTH-1:0] r_stream_row;
    reg [COL_WIDTH-1:0] r_stream_col;

    // Last pixel of the padded image stream.
    wire w_stream_last =
        (r_state == S_STREAM) &&
        (r_stream_row == PADDED_HEIGHT - 1) &&
        (r_stream_col == PADDED_WIDTH - 1);

    //--------------------------------------------------------------------------
    // Stream control outputs
    //--------------------------------------------------------------------------

    // Streaming is active only in S_STREAM.
    assign o_stream_active = (r_state == S_STREAM);

    // Clear downstream datapath during initialization.
    assign o_clear = (r_state == S_INIT);

    // First cycle of the padded stream.
    // Useful for resetting write counters or stage-local state.
    assign o_stage_start =
        (r_state == S_STREAM) &&
        (r_stream_row == {ROW_WIDTH{1'b0}}) &&
        (r_stream_col == {COL_WIDTH{1'b0}});

    // Real image area excludes the 1-pixel zero-padding boundary.
    //
    // Padded coordinate:
    //   row = 0 or row = IMAGE_HEIGHT+1 -> padding
    //   col = 0 or col = IMAGE_WIDTH+1  -> padding
    //
    // Real image pixels are:
    //   row = 1 ~ IMAGE_HEIGHT
    //   col = 1 ~ IMAGE_WIDTH
    assign o_stream_real =
        o_stream_active &&
        (r_stream_row >= 1) && (r_stream_row <= IMAGE_HEIGHT) &&
        (r_stream_col >= 1) && (r_stream_col <= IMAGE_WIDTH);

    assign o_image_idx  = r_image_idx;
    assign o_stream_row = r_stream_row;
    assign o_stream_col = r_stream_col;

    //--------------------------------------------------------------------------
    // Image-level stream FSM
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state       <= S_IDLE;
            r_image_idx   <= 2'd0;
            r_stream_row  <= {ROW_WIDTH{1'b0}};
            r_stream_col  <= {COL_WIDTH{1'b0}};
            o_done        <= 1'b0;
        end else begin
            // o_done is a one-cycle pulse.
            o_done <= 1'b0;

            case (r_state)
                S_IDLE: begin
                    // Wait for start and reset stream position.
                    r_image_idx  <= 2'd0;
                    r_stream_row <= {ROW_WIDTH{1'b0}};
                    r_stream_col <= {COL_WIDTH{1'b0}};

                    if (i_start) begin
                        r_state <= S_INIT;
                    end
                end

                S_INIT: begin
                    // Clear downstream logic before starting a new image stream.
                    r_stream_row <= {ROW_WIDTH{1'b0}};
                    r_stream_col <= {COL_WIDTH{1'b0}};
                    r_state      <= S_STREAM;
                end

                S_STREAM: begin
                    // Generate padded raster-scan coordinates.
                    if (r_stream_col == PADDED_WIDTH - 1) begin
                        r_stream_col <= {COL_WIDTH{1'b0}};

                        if (r_stream_row == PADDED_HEIGHT - 1) begin
                            r_stream_row <= {ROW_WIDTH{1'b0}};
                        end else begin
                            r_stream_row <= r_stream_row + 1'b1;
                        end
                    end else begin
                        r_stream_col <= r_stream_col + 1'b1;
                    end

                    // After the last padded pixel is issued,
                    // wait for downstream pipeline/output flush.
                    if (w_stream_last) begin
                        r_state <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    // Wait until the datapath reports that the current image
                    // has completely produced its output pixels.
                    if (i_image_output_done) begin
                        r_state <= S_DONE;
                    end
                end

                S_DONE: begin
                    // One image has completed.
                    o_done <= 1'b1;

                    if (r_image_idx == NUM_IMAGES - 1) begin
                        r_state <= S_IDLE;
                    end else begin
                        r_image_idx <= r_image_idx + 1'b1;
                        r_state     <= S_INIT;
                    end
                end

                default: begin
                    r_state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
