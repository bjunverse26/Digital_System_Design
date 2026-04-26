`timescale 1ns / 1ps

// GEMV datapath backed by UltraRAM.
// Wide input and weight words are read from URAM, split into eight 16-bit lanes,
// accumulated by parallel MACs, reduced through a pipelined adder tree, and then
// written back to output URAM.
module uram_based_gemv #(
    parameter INPUT_WIDTH       = 128,
    parameter WEIGHT_WIDTH      = 128,
    parameter OUTPUT_WIDTH      = 48,

    parameter INPUT_DEPTH       = 4096,
    parameter WEIGHT_DEPTH      = 4096,
    parameter OUTPUT_DEPTH      = 4096,

    parameter INPUT_ADDR_WIDTH  = $clog2(INPUT_DEPTH),
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_DEPTH),
    parameter OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_DEPTH)
) (
    input  wire                         i_clk,
    input  wire                         i_rstn,

    // input URAM control
    input  wire                         i_input_wr_en,
    input  wire [INPUT_ADDR_WIDTH-1:0]  i_input_wr_addr,
    input  wire [INPUT_WIDTH-1:0]       i_input_wr_din,
    input  wire                         i_input_rd_en,
    input  wire [INPUT_ADDR_WIDTH-1:0]  i_input_rd_addr,

    // weight URAM control
    input  wire                         i_weight_wr_en,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] i_weight_wr_addr,
    input  wire [WEIGHT_WIDTH-1:0]      i_weight_wr_din,
    input  wire                         i_weight_rd_en,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] i_weight_rd_addr,

    // MAC control
    input  wire                         i_mac_enable,

    // output URAM write control
    input  wire                         i_output_wr_en,
    input  wire [OUTPUT_ADDR_WIDTH-1:0] i_output_wr_addr,

    // output URAM read control
    input  wire                         i_output_rd_en,
    input  wire [OUTPUT_ADDR_WIDTH-1:0] i_output_rd_addr,
    output wire                         o_output_rd_valid,
    output wire [OUTPUT_WIDTH-1:0]      o_output_rd_dout
);

    // URAM read data and valid pulses.
    wire                            input_uram_valid;
    wire signed [INPUT_WIDTH-1:0]   input_uram_dout;
    wire                            weight_uram_valid;
    wire signed [WEIGHT_WIDTH-1:0]  weight_uram_dout;
    // Output URAM control is delayed to align with MAC and adder-tree latency.
    reg                             output_uram_wr_en_ff0;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_wr_addr_ff0;
    reg                             output_uram_rd_en_ff0;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_rd_addr_ff0;

    // Eight parallel MAC lanes consume one 16-bit slice from each wide word.
    wire                            dsp_enable;
    wire signed [OUTPUT_WIDTH-1:0]  mac_out [0:7];
    reg                             mac_valid;
    reg                             output_uram_wr_en_ff1;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_wr_addr_ff1;
    reg                             output_uram_rd_en_ff1;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_rd_addr_ff1;
    
    // Three-stage registered reduction tree: 8 lanes -> 4 -> 2 -> 1.
    reg signed [OUTPUT_WIDTH-1:0]   adder_l1_sum0_ff;
    reg signed [OUTPUT_WIDTH-1:0]   adder_l1_sum1_ff;
    reg signed [OUTPUT_WIDTH-1:0]   adder_l1_sum2_ff;
    reg signed [OUTPUT_WIDTH-1:0]   adder_l1_sum3_ff;
    reg                             adder_l1_valid;
    reg                             adder_l2_valid;
    reg                             output_uram_wr_en_ff2;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_wr_addr_ff2;
    reg                             output_uram_rd_en_ff2;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_rd_addr_ff2;
    

    reg signed [OUTPUT_WIDTH-1:0]   adder_l2_sum0_ff;
    reg signed [OUTPUT_WIDTH-1:0]   adder_l2_sum1_ff;
    reg                             output_uram_wr_en_ff3;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_wr_addr_ff3;
    reg                             output_uram_rd_en_ff3;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_rd_addr_ff3;
    

    reg signed [OUTPUT_WIDTH-1:0]   adder_l3_sum_ff;
    reg                             adder_l3_valid;
    reg                             output_uram_wr_en_ff4;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_wr_addr_ff4;
    reg                             output_uram_rd_en_ff4;
    reg [OUTPUT_ADDR_WIDTH-1:0]     output_uram_rd_addr_ff4;  

    // Activation/input vector storage.
    simple_dual_port_uram #(
        .WIDTH(INPUT_WIDTH),
        .DEPTH(INPUT_DEPTH),
        .ADDR_WIDTH(INPUT_ADDR_WIDTH)
    ) u_input_uram (
        .clk     (i_clk              ),
        .wr_en   (i_input_wr_en      ),
        .rd_en   (i_input_rd_en      ),
        .wr_addr (i_input_wr_addr    ),
        .rd_addr (i_input_rd_addr    ),
        .wr_din  (i_input_wr_din     ),
        .rd_valid(input_uram_valid   ),
        .rd_dout (input_uram_dout    )
    );

    // Weight vector storage.
    simple_dual_port_uram #(
        .WIDTH(WEIGHT_WIDTH),
        .DEPTH(WEIGHT_DEPTH),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_weight_uram (
        .clk     (i_clk               ),
        .wr_en   (i_weight_wr_en      ),
        .rd_en   (i_weight_rd_en      ),
        .wr_addr (i_weight_wr_addr    ),
        .rd_addr (i_weight_rd_addr    ),
        .wr_din  (i_weight_wr_din     ),
        .rd_valid(weight_uram_valid   ),
        .rd_dout (weight_uram_dout    )
    );
    
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_mac
            // One MAC per 16-bit lane of the 128-bit URAM word.
            MAC u_mac (
                .i_clk           (i_clk                      ),
                .i_rstn          (i_rstn                     ),
                .i_dsp_enable    (dsp_enable                 ),
                .i_dsp_input     (input_uram_dout[16*i+:16]  ),
                .i_dsp_weight    (weight_uram_dout[16*i+:16] ),
                .o_dsp_output    (mac_out[i]                 )      
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            output_uram_wr_en_ff0   <= 1'b0;
            output_uram_wr_addr_ff0 <= {OUTPUT_ADDR_WIDTH{1'b0}};
            output_uram_rd_en_ff0   <= 1'b0;
            output_uram_rd_addr_ff0 <= {OUTPUT_ADDR_WIDTH{1'b0}};

            output_uram_wr_en_ff1   <= 1'b0;
            output_uram_wr_addr_ff1 <= {OUTPUT_ADDR_WIDTH{1'b0}};
            output_uram_rd_en_ff1   <= 1'b0;
            output_uram_rd_addr_ff1 <= {OUTPUT_ADDR_WIDTH{1'b0}};

            output_uram_wr_en_ff2   <= 1'b0;
            output_uram_wr_addr_ff2 <= {OUTPUT_ADDR_WIDTH{1'b0}};
            output_uram_rd_en_ff2   <= 1'b0;
            output_uram_rd_addr_ff2 <= {OUTPUT_ADDR_WIDTH{1'b0}};

            output_uram_wr_en_ff3   <= 1'b0;
            output_uram_wr_addr_ff3 <= {OUTPUT_ADDR_WIDTH{1'b0}};
            output_uram_rd_en_ff3   <= 1'b0;
            output_uram_rd_addr_ff3 <= {OUTPUT_ADDR_WIDTH{1'b0}};

            output_uram_wr_en_ff4   <= 1'b0;
            output_uram_wr_addr_ff4 <= {OUTPUT_ADDR_WIDTH{1'b0}};
            output_uram_rd_en_ff4   <= 1'b0;
            output_uram_rd_addr_ff4 <= {OUTPUT_ADDR_WIDTH{1'b0}};
        end else begin
            // Shift the external output-memory command through the datapath
            // latency so the write address matches the reduced MAC result.
            output_uram_wr_en_ff0   <= i_output_wr_en;
            output_uram_wr_addr_ff0 <= i_output_wr_addr;
            output_uram_rd_en_ff0   <= i_output_rd_en;
            output_uram_rd_addr_ff0 <= i_output_rd_addr;

            output_uram_wr_en_ff1   <= output_uram_wr_en_ff0;
            output_uram_wr_addr_ff1 <= output_uram_wr_addr_ff0;
            output_uram_rd_en_ff1   <= output_uram_rd_en_ff0;
            output_uram_rd_addr_ff1 <= output_uram_rd_addr_ff0;

            output_uram_wr_en_ff2   <= output_uram_wr_en_ff1;
            output_uram_wr_addr_ff2 <= output_uram_wr_addr_ff1;
            output_uram_rd_en_ff2   <= output_uram_rd_en_ff1;
            output_uram_rd_addr_ff2 <= output_uram_rd_addr_ff1;

            output_uram_wr_en_ff3   <= output_uram_wr_en_ff2;
            output_uram_wr_addr_ff3 <= output_uram_wr_addr_ff2;
            output_uram_rd_en_ff3   <= output_uram_rd_en_ff2;
            output_uram_rd_addr_ff3 <= output_uram_rd_addr_ff2;

            output_uram_wr_en_ff4   <= output_uram_wr_en_ff3;
            output_uram_wr_addr_ff4 <= output_uram_wr_addr_ff3;
            output_uram_rd_en_ff4   <= output_uram_rd_en_ff3;
            output_uram_rd_addr_ff4 <= output_uram_rd_addr_ff3;
        end
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            mac_valid      <= 1'b0;
            adder_l1_valid <= 1'b0;
            adder_l2_valid <= 1'b0;
            adder_l3_valid <= 1'b0;
        end else begin
            // Valid pipeline mirrors the MAC and adder-tree stages.
            mac_valid      <= dsp_enable;
            adder_l1_valid <= mac_valid;
            adder_l2_valid <= adder_l1_valid;
            adder_l3_valid <= adder_l2_valid;
        end
    end

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            adder_l1_sum0_ff <= {OUTPUT_WIDTH{1'b0}};
            adder_l1_sum1_ff <= {OUTPUT_WIDTH{1'b0}};
            adder_l1_sum2_ff <= {OUTPUT_WIDTH{1'b0}};
            adder_l1_sum3_ff <= {OUTPUT_WIDTH{1'b0}};

            adder_l2_sum0_ff <= {OUTPUT_WIDTH{1'b0}}; 
            adder_l2_sum1_ff <= {OUTPUT_WIDTH{1'b0}};

            adder_l3_sum_ff  <= {OUTPUT_WIDTH{1'b0}};
        end else begin
            if (mac_valid) begin
                // Reduction level 1: 8 MAC outputs to 4 partial sums.
                adder_l1_sum0_ff <= mac_out[0] + mac_out[1];
                adder_l1_sum1_ff <= mac_out[2] + mac_out[3];
                adder_l1_sum2_ff <= mac_out[4] + mac_out[5];
                adder_l1_sum3_ff <= mac_out[6] + mac_out[7];
            end
            if (adder_l1_valid) begin
                // Reduction level 2: 4 partial sums to 2.
                adder_l2_sum0_ff <= adder_l1_sum0_ff + adder_l1_sum1_ff;
                adder_l2_sum1_ff <= adder_l1_sum2_ff + adder_l1_sum3_ff;
            end
            if (adder_l2_valid) begin
                // Reduction level 3: final GEMV dot-product sum.
                adder_l3_sum_ff <= adder_l2_sum0_ff + adder_l2_sum1_ff;
            end
        end
    end

    // Output URAM receives the fully reduced MAC result.
    simple_dual_port_uram #(
        .WIDTH(OUTPUT_WIDTH),
        .DEPTH(OUTPUT_DEPTH),
        .ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) u_output_uram (
        .clk     (i_clk                     ),
        .wr_en   (output_uram_wr_en_ff4     ),
        .rd_en   (output_uram_rd_en_ff4     ),
        .wr_addr (output_uram_wr_addr_ff4   ),
        .rd_addr (output_uram_rd_addr_ff4   ),
        .wr_din  (adder_l3_sum_ff           ),
        .rd_valid(o_output_rd_valid         ),
        .rd_dout (o_output_rd_dout          )
    );

    // MACs run only when both URAM reads have returned valid data.
    assign dsp_enable = i_mac_enable && input_uram_valid && weight_uram_valid;

endmodule
