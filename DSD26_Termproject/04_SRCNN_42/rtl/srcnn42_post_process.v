`timescale 1ns / 1ps

module srcnn42_post_process #(
    parameter DATA_WIDTH  = 16,
    parameter FIXED_SHIFT = 8
) (
    input wire                             i_clk,
    input wire                             i_rstn,

    // Enables one valid post-processing input sample.
    input wire                             i_valid,

    // Layer 1/2: enable ReLU.
    // Layer 3: disable ReLU to allow signed final output.
    input wire                             i_relu_en,

    // MAC result has twice the data width.
    // For DATA_WIDTH = 16, this is a 32-bit accumulated fixed-point value.
    input wire signed [(2*DATA_WIDTH)-1:0] i_mac_data,

    // Bias is already represented in DATA_WIDTH fixed-point format.
    input wire signed [DATA_WIDTH-1:0]     i_bias,

    output reg  signed [DATA_WIDTH-1:0]    o_output_data,
    output reg                             o_output_valid
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    localparam MAC_WIDTH = 2 * DATA_WIDTH;

    // Saturation limits for signed DATA_WIDTH output.
    // For DATA_WIDTH = 16:
    //   DATA_MAX =  32767
    //   DATA_MIN = -32768
    localparam signed [DATA_WIDTH-1:0] DATA_MAX = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [DATA_WIDTH-1:0] DATA_MIN = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    // Sign-extend DATA_WIDTH limits to MAC_WIDTH for comparison.
    localparam signed [MAC_WIDTH-1:0] CLIP_MAX =
        {{(MAC_WIDTH-DATA_WIDTH){DATA_MAX[DATA_WIDTH-1]}}, DATA_MAX};
    localparam signed [MAC_WIDTH-1:0] CLIP_MIN =
        {{(MAC_WIDTH-DATA_WIDTH){DATA_MIN[DATA_WIDTH-1]}}, DATA_MIN};

    //--------------------------------------------------------------------------
    // Fixed-point rescale, bias addition, ReLU, and clipping
    //--------------------------------------------------------------------------

    wire signed [MAC_WIDTH-1:0] w_shift_data;
    wire signed [MAC_WIDTH-1:0] w_bias_ext;
    wire signed [MAC_WIDTH-1:0] w_bias_data;
    wire signed [MAC_WIDTH-1:0] w_relu_data;
    reg  signed [DATA_WIDTH-1:0] w_clip_data;

    // Rescale accumulated MAC result back to DATA_WIDTH fixed-point scale.
    assign w_shift_data = i_mac_data >>> FIXED_SHIFT;

    // Sign-extend bias before adding it to the shifted MAC result.
    assign w_bias_ext   = {{(MAC_WIDTH-DATA_WIDTH){i_bias[DATA_WIDTH-1]}}, i_bias};

    // Add bias after fixed-point scaling.
    assign w_bias_data  = w_shift_data + w_bias_ext;

    // Apply ReLU only when enabled.
    // If the biased result is negative and ReLU is enabled, force it to zero.
    assign w_relu_data  = (i_relu_en && w_bias_data[MAC_WIDTH-1]) ? {MAC_WIDTH{1'b0}} :
                                                                    w_bias_data;

    // Saturate the result to the DATA_WIDTH signed range.
    always @(*) begin
        if (w_relu_data > CLIP_MAX) begin
            w_clip_data = DATA_MAX;
        end else if (w_relu_data < CLIP_MIN) begin
            w_clip_data = DATA_MIN;
        end else begin
            w_clip_data = w_relu_data[DATA_WIDTH-1:0];
        end
    end

    //--------------------------------------------------------------------------
    // Output register
    //--------------------------------------------------------------------------

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_output_data  <= {DATA_WIDTH{1'b0}};
            o_output_valid <= 1'b0;
        end else begin
            // Output valid follows input valid with one registered stage.
            o_output_valid <= i_valid;

            if (i_valid) begin
                o_output_data <= w_clip_data;
            end
        end
    end

endmodule
