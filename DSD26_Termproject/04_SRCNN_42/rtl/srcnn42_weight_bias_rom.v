`timescale 1ns / 1ps

module srcnn42_weight_bias_rom #(
    parameter DATA_WIDTH  = 16,
    parameter KERNEL_SIZE = 3,
    parameter L1_OUT_CH   = 4,
    parameter L2_OUT_CH   = 2,

    // Hex text files for fixed-point weights and biases.
    // Each file is assumed to contain one DATA_WIDTH-bit hex value per line.
    parameter W1_INIT = "",
    parameter B1_INIT = "",
    parameter W2_INIT = "",
    parameter B2_INIT = "",
    parameter W3_INIT = "",
    parameter B3_INIT = ""
) (
    // Selects which layer's parameters are driven to the outputs.
    input wire [1:0]                                          i_layer,

    // Packed 3x3 kernel weights for all PE slots.
    // Each output corresponds to one kernel position.
    //
    // o_weight_00 = all PE weights for kernel[0][0]
    // o_weight_01 = all PE weights for kernel[0][1]
    // ...
    // o_weight_22 = all PE weights for kernel[2][2]
    //
    // Each bus is divided into DATA_WIDTH-bit chunks:
    //   [PE0][PE1][PE2] ... [PE_COUNT-1]
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_00,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_01,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_02,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_10,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_11,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_12,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_20,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_21,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_weight_22,

    // Packed post-convolution bias values.
    // The output width follows L1_OUT_CH so that the same post-processing path
    // can be reused across layers. Unused bias slots are driven to zero.
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_post_bias
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------

    // Number of elements in one 3x3 kernel.
    localparam KERNEL_ELEMS = KERNEL_SIZE * KERNEL_SIZE;

    // Maximum number of PE slots used by layer 2.
    localparam PE_COUNT     = L2_OUT_CH * L1_OUT_CH;

    localparam LAYER_1      = 2'd0;
    localparam LAYER_2      = 2'd1;
    localparam LAYER_3      = 2'd2;

    //--------------------------------------------------------------------------
    // Weight and bias ROMs
    //--------------------------------------------------------------------------

    // Layer 1:
    //   W1 shape: [L1_OUT_CH][KERNEL_ELEMS]
    //   B1 shape: [L1_OUT_CH]
    reg signed [DATA_WIDTH-1:0] r_w1 [0:(L1_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b1 [0:L1_OUT_CH-1];

    // Layer 2:
    //   W2 shape: [L2_OUT_CH][L1_OUT_CH][KERNEL_ELEMS]
    //   B2 shape: [L2_OUT_CH]
    reg signed [DATA_WIDTH-1:0] r_w2 [0:(L2_OUT_CH*L1_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b2 [0:L2_OUT_CH-1];

    // Layer 3:
    //   W3 shape: [L2_OUT_CH][KERNEL_ELEMS]
    //   B3 shape: [1]
    reg signed [DATA_WIDTH-1:0] r_w3 [0:(L2_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b3 [0:0];

    // Load fixed-point hex values into ROM arrays at simulation/synthesis init.
    initial begin
        $readmemh(W1_INIT, r_w1);
        $readmemh(B1_INIT, r_b1);
        $readmemh(W2_INIT, r_w2);
        $readmemh(B2_INIT, r_b2);
        $readmemh(W3_INIT, r_w3);
        $readmemh(B3_INIT, r_b3);
    end

    //--------------------------------------------------------------------------
    // Weight selection function
    //--------------------------------------------------------------------------

    function signed [DATA_WIDTH-1:0] select_weight;
        input [1:0]                 layer;
        input integer               pe_id;
        input integer               k_idx;

        // For layer 2, one PE corresponds to one output/input-channel pair.
        integer l2_oc;
        integer l2_ic;

        begin
            l2_oc = pe_id / L1_OUT_CH;
            l2_ic = pe_id % L1_OUT_CH;

            if (layer == LAYER_1) begin
                // Layer 1 uses only L1_OUT_CH PE slots.
                // Remaining PE slots are padded with zero.
                if (pe_id < L1_OUT_CH) begin
                    select_weight = r_w1[(pe_id*KERNEL_ELEMS)+k_idx];
                end else begin
                    select_weight = {DATA_WIDTH{1'b0}};
                end
            end else if (layer == LAYER_2) begin
                // Layer 2 uses all PE slots.
                // pe_id is decoded into:
                //   l2_oc = output channel index
                //   l2_ic = input channel index
                select_weight = r_w2[(l2_oc*L1_OUT_CH*KERNEL_ELEMS)
                                   + (l2_ic*KERNEL_ELEMS)
                                   + k_idx];
            end else if (layer == LAYER_3) begin
                // Layer 3 uses only L2_OUT_CH PE slots.
                // Remaining PE slots are padded with zero.
                if (pe_id < L2_OUT_CH) begin
                    select_weight = r_w3[(pe_id*KERNEL_ELEMS)+k_idx];
                end else begin
                    select_weight = {DATA_WIDTH{1'b0}};
                end
            end else begin
                select_weight = {DATA_WIDTH{1'b0}};
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Bias selection function
    //--------------------------------------------------------------------------

    function signed [DATA_WIDTH-1:0] select_bias;
        input [1:0]   layer;
        input integer post_id;

        begin
            if (layer == LAYER_1) begin
                // Layer 1 has L1_OUT_CH bias values.
                select_bias = r_b1[post_id];
            end else if ((layer == LAYER_2) && (post_id < L2_OUT_CH)) begin
                // Layer 2 has L2_OUT_CH bias values.
                // Unused post slots are driven to zero below.
                select_bias = r_b2[post_id];
            end else if ((layer == LAYER_3) && (post_id == 0)) begin
                // Layer 3 has one output bias.
                select_bias = r_b3[0];
            end else begin
                select_bias = {DATA_WIDTH{1'b0}};
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Combinational ROM outputs
    //--------------------------------------------------------------------------

    genvar pe_idx;
    generate
        for (pe_idx = 0; pe_idx < PE_COUNT; pe_idx = pe_idx + 1) begin : gen_pe_weights
            // Pack each PE's selected kernel value into the corresponding
            // DATA_WIDTH-bit slice of each output bus.
            //
            // k_idx mapping:
            //   0 1 2
            //   3 4 5
            //   6 7 8
            assign o_weight_00[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 0);
            assign o_weight_01[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 1);
            assign o_weight_02[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 2);

            assign o_weight_10[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 3);
            assign o_weight_11[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 4);
            assign o_weight_12[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 5);

            assign o_weight_20[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 6);
            assign o_weight_21[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 7);
            assign o_weight_22[(pe_idx*DATA_WIDTH)+:DATA_WIDTH] = select_weight(i_layer, pe_idx, 8);
        end
    endgenerate

    genvar post_idx;
    generate
        for (post_idx = 0; post_idx < L1_OUT_CH; post_idx = post_idx + 1) begin : gen_post_bias
            // Pack selected bias values.
            // Layers with fewer bias values return zero for unused post slots.
            assign o_post_bias[(post_idx*DATA_WIDTH)+:DATA_WIDTH] = select_bias(i_layer, post_idx);
        end
    endgenerate

endmodule
