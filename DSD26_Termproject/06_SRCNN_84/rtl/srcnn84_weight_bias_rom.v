`timescale 1ns / 1ps

module srcnn84_weight_bias_rom #(
    parameter DATA_WIDTH  = 16,
    parameter KERNEL_SIZE = 3,
    parameter L1_OUT_CH   = 8,
    parameter L2_OUT_CH   = 4,

    // Fixed-point hex text files.
    // Each file is assumed to contain one DATA_WIDTH-bit hex value per line.
    parameter W1_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_W1_hex.txt",
    parameter B1_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_B1_hex.txt",
    parameter W2_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_W2_hex.txt",
    parameter B2_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_B2_hex.txt",
    parameter W3_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_W3_hex.txt",
    parameter B3_INIT = "C:/DSD26_Termproject_Materials/06_SRCNN_84/init/fixed_point_B3_hex.txt"
) (
    // Bias outputs.
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_b1,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_b2,
    output wire signed [DATA_WIDTH-1:0]                       o_b3,

    // Layer 1 weights.
    // Each bus contains L1_OUT_CH weights for one kernel position.
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w00,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w01,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w02,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w10,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w11,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w12,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w20,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w21,
    output wire signed [(L1_OUT_CH*DATA_WIDTH)-1:0]           o_l1_w22,

    // Layer 2 weights.
    // Each bus contains L2_OUT_CH*L1_OUT_CH weights for one kernel position.
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w00,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w01,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w02,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w10,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w11,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w12,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w20,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w21,
    output wire signed [(L2_OUT_CH*L1_OUT_CH*DATA_WIDTH)-1:0] o_l2_w22,

    // Layer 3 weights.
    // Each bus contains L2_OUT_CH weights for one kernel position.
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w00,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w01,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w02,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w10,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w11,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w12,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w20,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w21,
    output wire signed [(L2_OUT_CH*DATA_WIDTH)-1:0]           o_l3_w22
);

    //--------------------------------------------------------------------------
    // Local parameters and ROM storage
    //--------------------------------------------------------------------------

    localparam KERNEL_ELEMS = KERNEL_SIZE * KERNEL_SIZE;

    // Layer 1:
    //   W1 shape: [L1_OUT_CH][KERNEL_ELEMS]
    //   B1 shape: [L1_OUT_CH]
    reg signed [DATA_WIDTH-1:0] r_w1 [0:(L1_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b1 [0:L1_OUT_CH-1];

    // Layer 2:
    //   W2 shape: [L2_OUT_CH][L1_OUT_CH][KERNEL_ELEMS]
    //   B2 shape: [L2_OUT_CH]
    //
    // The flattened PE order is:
    //   pe = output_channel * L1_OUT_CH + input_channel
    reg signed [DATA_WIDTH-1:0] r_w2 [0:(L2_OUT_CH*L1_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b2 [0:L2_OUT_CH-1];

    // Layer 3:
    //   W3 shape: [L2_OUT_CH][KERNEL_ELEMS]
    //   B3 shape: [1]
    reg signed [DATA_WIDTH-1:0] r_w3 [0:(L2_OUT_CH*KERNEL_ELEMS)-1];
    reg signed [DATA_WIDTH-1:0] r_b3 [0:0];

    //--------------------------------------------------------------------------
    // Initialization files
    //--------------------------------------------------------------------------

    // Load fixed-point hex values into ROM arrays.
    initial begin
        $readmemh(W1_INIT, r_w1);
        $readmemh(B1_INIT, r_b1);
        $readmemh(W2_INIT, r_w2);
        $readmemh(B2_INIT, r_b2);
        $readmemh(W3_INIT, r_w3);
        $readmemh(B3_INIT, r_b3);
    end

    //--------------------------------------------------------------------------
    // Flattened layer weight outputs
    //--------------------------------------------------------------------------

    genvar l1_oc;
    generate
        // Layer 1 output packing.
        // Each output bus corresponds to one kernel position,
        // and each DATA_WIDTH slice corresponds to one output channel.
        for (l1_oc = 0; l1_oc < L1_OUT_CH; l1_oc = l1_oc + 1) begin : gen_l1
            assign o_b1[(l1_oc*DATA_WIDTH)+:DATA_WIDTH]     = r_b1[l1_oc];

            assign o_l1_w00[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+0];
            assign o_l1_w01[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+1];
            assign o_l1_w02[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+2];

            assign o_l1_w10[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+3];
            assign o_l1_w11[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+4];
            assign o_l1_w12[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+5];

            assign o_l1_w20[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+6];
            assign o_l1_w21[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+7];
            assign o_l1_w22[(l1_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w1[(l1_oc*KERNEL_ELEMS)+8];
        end
    endgenerate

    genvar l2_pe;
    generate
        // Layer 2 output packing.
        //
        // l2_pe represents one output-channel/input-channel pair:
        //   l2_oc = l2_pe / L1_OUT_CH
        //   l2_ic = l2_pe % L1_OUT_CH
        //
        // Each output bus corresponds to one kernel position.
        for (l2_pe = 0; l2_pe < (L2_OUT_CH*L1_OUT_CH); l2_pe = l2_pe + 1) begin : gen_l2
            assign o_l2_w00[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+0];
            assign o_l2_w01[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+1];
            assign o_l2_w02[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+2];

            assign o_l2_w10[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+3];
            assign o_l2_w11[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+4];
            assign o_l2_w12[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+5];

            assign o_l2_w20[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+6];
            assign o_l2_w21[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+7];
            assign o_l2_w22[(l2_pe*DATA_WIDTH)+:DATA_WIDTH] = r_w2[(l2_pe*KERNEL_ELEMS)+8];
        end
    endgenerate

    genvar l2_oc;
    generate
        // Layer 2 bias and Layer 3 weight packing.
        // Layer 3 has one output channel and L2_OUT_CH input channels.
        for (l2_oc = 0; l2_oc < L2_OUT_CH; l2_oc = l2_oc + 1) begin : gen_b2_l3
            assign o_b2[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_b2[l2_oc];

            assign o_l3_w00[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+0];
            assign o_l3_w01[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+1];
            assign o_l3_w02[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+2];

            assign o_l3_w10[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+3];
            assign o_l3_w11[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+4];
            assign o_l3_w12[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+5];

            assign o_l3_w20[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+6];
            assign o_l3_w21[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+7];
            assign o_l3_w22[(l2_oc*DATA_WIDTH)+:DATA_WIDTH] = r_w3[(l2_oc*KERNEL_ELEMS)+8];
        end
    endgenerate

    // Layer 3 has a single output bias.
    assign o_b3 = r_b3[0];

endmodule
