//==============================================================================
// File Name   : lutram_line_buffer_gemv.v
// Project     : Digital System Design - Lab04
// Author      : Beomjun Kim
// Description : GEMV datapath with URAM backing storage and LUTRAM line buffers.
// Notes       : Wide URAM reads are cached into small distributed-RAM lines so
//               individual 16-bit elements can feed four parallel MAC lanes.
//==============================================================================

`timescale 1ns / 1ps

module lutram_line_buffer_gemv #(
    parameter INPUT_WIDTH              = 128,
    parameter WEIGHT_WIDTH             = 128,
    parameter OUTPUT_WIDTH             = 48,
    parameter INPUT_DEPTH              = 4096,
    parameter WEIGHT_DEPTH             = 4096,
    parameter OUTPUT_DEPTH             = 4096,
    parameter INPUT_ADDR_WIDTH         = $clog2(INPUT_DEPTH),
    parameter WEIGHT_ADDR_WIDTH        = $clog2(WEIGHT_DEPTH),
    parameter OUTPUT_ADDR_WIDTH        = $clog2(OUTPUT_DEPTH),
    parameter INPUT_LUTRAM_DEPTH       = 4,
    parameter WEIGHT_LUTRAM_DEPTH      = 1,
    parameter OUTPUT_LUTRAM_DEPTH      = 1,
    parameter INPUT_LUTRAM_ADDR_WIDTH  = $clog2(INPUT_LUTRAM_DEPTH),
    parameter WEIGHT_LUTRAM_ADDR_WIDTH = $clog2(WEIGHT_LUTRAM_DEPTH),
    parameter OUTPUT_LUTRAM_ADDR_WIDTH = $clog2(OUTPUT_LUTRAM_DEPTH),
    parameter INPUT_LUTRAM_WIDTH       = 128,
    parameter WEIGHT_LUTRAM_WIDTH      = 128,
    parameter OUTPUT_LUTRAM_WIDTH      = 192,
    parameter INPUT_LUTRAM_RD_WIDTH    = 16,
    parameter WEIGHT_LUTRAM_RD_WIDTH   = 16,
    parameter OUTPUT_LUTRAM_RD_WIDTH   = 48,
    parameter INPUT_LUTRAM_SEL_WIDTH   = $clog2(INPUT_LUTRAM_WIDTH / INPUT_LUTRAM_RD_WIDTH),
    parameter WEIGHT_LUTRAM_SEL_WIDTH  = $clog2(WEIGHT_LUTRAM_WIDTH / WEIGHT_LUTRAM_RD_WIDTH),
    parameter OUTPUT_LUTRAM_SEL_WIDTH  = $clog2(OUTPUT_LUTRAM_WIDTH / OUTPUT_LUTRAM_RD_WIDTH)
)(
    input  wire                                   i_clk,
    input  wire                                   i_rstn,

    // Input URAM control.
    input  wire                                   i_input_wr_en,
    input  wire [INPUT_ADDR_WIDTH-1:0]            i_input_wr_addr,
    input  wire [INPUT_WIDTH-1:0]                 i_input_wr_din,
    input  wire                                   i_input_rd_en,
    input  wire [INPUT_ADDR_WIDTH-1:0]            i_input_rd_addr,

    // Weight URAM control.
    input  wire                                   i_weight_wr_en,
    input  wire [WEIGHT_ADDR_WIDTH-1:0]           i_weight_wr_addr,
    input  wire [WEIGHT_WIDTH-1:0]                i_weight_wr_din,
    input  wire                                   i_weight_rd_en,
    input  wire [WEIGHT_ADDR_WIDTH-1:0]           i_weight_rd_addr,

    // Input LUTRAM control.
    input  wire [3:0]                             i_input_lutram_wr_en,
    input  wire [INPUT_LUTRAM_ADDR_WIDTH-1:0]     i_input_lutram_wr_addr,
    input  wire                                   i_input_lutram_rd_en,
    input  wire [INPUT_LUTRAM_ADDR_WIDTH-1:0]     i_input_lutram_rd_addr,
    input  wire [INPUT_LUTRAM_SEL_WIDTH-1:0]      i_input_lutram_rd_sel,

    // Weight LUTRAM control.
    input  wire                                   i_weight_lutram_wr_en,
    input  wire [WEIGHT_LUTRAM_ADDR_WIDTH-1:0]    i_weight_lutram_wr_addr,
    input  wire                                   i_weight_lutram_rd_en,
    input  wire [WEIGHT_LUTRAM_ADDR_WIDTH-1:0]    i_weight_lutram_rd_addr,
    input  wire [WEIGHT_LUTRAM_SEL_WIDTH-1:0]     i_weight_lutram_rd_sel,

    // Output LUTRAM control.
    input  wire                                   i_output_lutram_wr_en,
    input  wire [OUTPUT_LUTRAM_ADDR_WIDTH-1:0]    i_output_lutram_wr_addr,
    input  wire                                   i_output_lutram_rd_en,
    input  wire [OUTPUT_LUTRAM_ADDR_WIDTH-1:0]    i_output_lutram_rd_addr,
    input  wire [OUTPUT_LUTRAM_SEL_WIDTH-1:0]     i_output_lutram_rd_sel,

    // MAC control.
    input  wire                                   i_acc_clear,
    input  wire                                   i_mac_enable,

    // Output URAM write/read control.
    input  wire                                   i_output_wr_en,
    input  wire [OUTPUT_ADDR_WIDTH-1:0]           i_output_wr_addr,
    input  wire                                   i_output_rd_en,
    input  wire [OUTPUT_ADDR_WIDTH-1:0]           i_output_rd_addr,
    output wire                                   o_output_rd_valid,
    output wire [OUTPUT_WIDTH-1:0]                o_output_rd_dout,

    output reg                                    o_output_valid,
    output reg  signed [OUTPUT_WIDTH-1:0]         o_output0,
    output reg  signed [OUTPUT_WIDTH-1:0]         o_output1,
    output reg  signed [OUTPUT_WIDTH-1:0]         o_output2,
    output reg  signed [OUTPUT_WIDTH-1:0]         o_output3
    );

    // URAM outputs provide wide rows/vectors for line-buffer fills.
    wire [INPUT_WIDTH-1:0]               in_u_do;   // input row from URAM
    wire [WEIGHT_WIDTH-1:0]              wt_u_do;   // weight vector from URAM
    wire [INPUT_LUTRAM_RD_WIDTH-1:0]     in_l_do0;  // row0 element from LUTRAM
    wire [INPUT_LUTRAM_RD_WIDTH-1:0]     in_l_do1;  // row1 element from LUTRAM
    wire [INPUT_LUTRAM_RD_WIDTH-1:0]     in_l_do2;  // row2 element from LUTRAM
    wire [INPUT_LUTRAM_RD_WIDTH-1:0]     in_l_do3;  // row3 element from LUTRAM
    wire [WEIGHT_LUTRAM_RD_WIDTH-1:0]    wt_l_do;   // weight element from LUTRAM
    wire [OUTPUT_LUTRAM_RD_WIDTH-1:0]    out_l_do;  // output element from LUTRAM
    wire signed [OUTPUT_WIDTH-1:0]       mac0;      // output0 accumulated value
    wire signed [OUTPUT_WIDTH-1:0]       mac1;      // output1 accumulated value
    wire signed [OUTPUT_WIDTH-1:0]       mac2;      // output2 accumulated value
    wire signed [OUTPUT_WIDTH-1:0]       mac3;      // output3 accumulated value

    // Input URAM: backing storage for activation rows.
    simple_dual_port_uram #(
        .WIDTH(INPUT_WIDTH),
        .DEPTH(INPUT_DEPTH)
    ) u_in_uram (
        .clk     (i_clk),
        .wr_en   (i_input_wr_en),
        .rd_en   (i_input_rd_en),
        .wr_addr (i_input_wr_addr),
        .rd_addr (i_input_rd_addr),
        .wr_din  (i_input_wr_din),
        .rd_valid(),
        .rd_dout (in_u_do)
    );

    // Weight URAM: backing storage for weight vectors.
    simple_dual_port_uram #(
        .WIDTH(WEIGHT_WIDTH),
        .DEPTH(WEIGHT_DEPTH)
    ) u_wt_uram (
        .clk     (i_clk),
        .wr_en   (i_weight_wr_en),
        .rd_en   (i_weight_rd_en),
        .wr_addr (i_weight_wr_addr),
        .rd_addr (i_weight_rd_addr),
        .wr_din  (i_weight_wr_din),
        .rd_valid(),
        .rd_dout (wt_u_do)
    );

    // Input LUTRAM banks: four cached rows are read in parallel for four outputs.
    simple_line_lutram #(
        .WIDTH         (INPUT_LUTRAM_WIDTH),
        .DEPTH         (INPUT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (INPUT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (INPUT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(INPUT_LUTRAM_SEL_WIDTH)
    ) u_in_lut0 (
        .clk    (i_clk),
        .wr_en  (i_input_lutram_wr_en[0]),
        .wr_addr(i_input_lutram_wr_addr),
        .wr_din (in_u_do),
        .rd_en  (i_input_lutram_rd_en),
        .rd_addr(i_input_lutram_rd_addr),
        .rd_sel (i_input_lutram_rd_sel),
        .rd_dout(in_l_do0)
    );

    simple_line_lutram #(
        .WIDTH         (INPUT_LUTRAM_WIDTH),
        .DEPTH         (INPUT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (INPUT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (INPUT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(INPUT_LUTRAM_SEL_WIDTH)
    ) u_in_lut1 ( 
        .clk    (i_clk),
        .wr_en  (i_input_lutram_wr_en[1]),
        .wr_addr(i_input_lutram_wr_addr),
        .wr_din (in_u_do),
        .rd_en  (i_input_lutram_rd_en),
        .rd_addr(i_input_lutram_rd_addr),
        .rd_sel (i_input_lutram_rd_sel),
        .rd_dout(in_l_do1)
    );

    simple_line_lutram #(
        .WIDTH         (INPUT_LUTRAM_WIDTH),
        .DEPTH         (INPUT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (INPUT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (INPUT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(INPUT_LUTRAM_SEL_WIDTH)
    ) u_in_lut2 (
        .clk    (i_clk),
        .wr_en  (i_input_lutram_wr_en[2]),
        .wr_addr(i_input_lutram_wr_addr),
        .wr_din (in_u_do),
        .rd_en  (i_input_lutram_rd_en),
        .rd_addr(i_input_lutram_rd_addr),
        .rd_sel (i_input_lutram_rd_sel),
        .rd_dout(in_l_do2)
    );

    simple_line_lutram #(
        .WIDTH         (INPUT_LUTRAM_WIDTH),
        .DEPTH         (INPUT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (INPUT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (INPUT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(INPUT_LUTRAM_SEL_WIDTH)
    ) u_in_lut3 (
        .clk    (i_clk),
        .wr_en  (i_input_lutram_wr_en[3]),
        .wr_addr(i_input_lutram_wr_addr),
        .wr_din (in_u_do),
        .rd_en  (i_input_lutram_rd_en),
        .rd_addr(i_input_lutram_rd_addr),
        .rd_sel (i_input_lutram_rd_sel),
        .rd_dout(in_l_do3)
    );

    // Weight LUTRAM: selects one scalar weight from the cached weight vector.
    simple_line_lutram #(
        .WIDTH         (WEIGHT_LUTRAM_WIDTH),
        .DEPTH         (WEIGHT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (WEIGHT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (WEIGHT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(WEIGHT_LUTRAM_SEL_WIDTH)
    ) u_wt_lut (
        .clk    (i_clk),
        .wr_en  (i_weight_lutram_wr_en),
        .wr_addr(i_weight_lutram_wr_addr),
        .wr_din (wt_u_do),
        .rd_en  (i_weight_lutram_rd_en),
        .rd_addr(i_weight_lutram_rd_addr),
        .rd_sel (i_weight_lutram_rd_sel),
        .rd_dout(wt_l_do)
    );

    // Four MAC lanes share the selected weight and consume four input rows.
    MAC u_mac0 (
        .i_clk       (i_clk),
        .i_rstn      (i_rstn & ~i_acc_clear),
        .i_dsp_enable(i_mac_enable),
        .i_dsp_input ($signed(in_l_do0)),
        .i_dsp_weight($signed(wt_l_do)),
        .o_dsp_output(mac0)
    );

    MAC u_mac1 (
        .i_clk       (i_clk),
        .i_rstn      (i_rstn & ~i_acc_clear),
        .i_dsp_enable(i_mac_enable),
        .i_dsp_input ($signed(in_l_do1)),
        .i_dsp_weight($signed(wt_l_do)),
        .o_dsp_output(mac1)
    );

    MAC u_mac2 (
        .i_clk       (i_clk),
        .i_rstn      (i_rstn & ~i_acc_clear),
        .i_dsp_enable(i_mac_enable),
        .i_dsp_input ($signed(in_l_do2)),
        .i_dsp_weight($signed(wt_l_do)),
        .o_dsp_output(mac2)
    );

    MAC u_mac3 (
        .i_clk       (i_clk),
        .i_rstn      (i_rstn & ~i_acc_clear),
        .i_dsp_enable(i_mac_enable),
        .i_dsp_input ($signed(in_l_do3)),
        .i_dsp_weight($signed(wt_l_do)),
        .o_dsp_output(mac3)
    );

    // Output LUTRAM packs four accumulated outputs into one cached line.
    simple_line_lutram #(
        .WIDTH         (OUTPUT_LUTRAM_WIDTH),
        .DEPTH         (OUTPUT_LUTRAM_DEPTH),
        .ADDR_WIDTH    (OUTPUT_LUTRAM_ADDR_WIDTH),
        .RD_WIDTH      (OUTPUT_LUTRAM_RD_WIDTH),
        .BANK_SEL_WIDTH(OUTPUT_LUTRAM_SEL_WIDTH)
    ) u_out_lut (
        .clk    (i_clk),
        .wr_en  (i_output_lutram_wr_en),
        .wr_addr(i_output_lutram_wr_addr),
        .wr_din ({mac3, mac2, mac1, mac0}),
        .rd_en  (i_output_lutram_rd_en),
        .rd_addr(i_output_lutram_rd_addr),
        .rd_sel (i_output_lutram_rd_sel),
        .rd_dout(out_l_do)
    );

    // Output URAM stores selected output elements from the output line buffer.
    simple_dual_port_uram #(
        .WIDTH(OUTPUT_WIDTH),
        .DEPTH(OUTPUT_DEPTH)
    ) u_out_uram (
        .clk     (i_clk),
        .wr_en   (i_output_wr_en),
        .rd_en   (i_output_rd_en),
        .wr_addr (i_output_wr_addr),
        .rd_addr (i_output_rd_addr),
        .wr_din  (out_l_do),
        .rd_valid(o_output_rd_valid),
        .rd_dout (o_output_rd_dout)
    );

    always @(posedge i_clk) begin
        if (~i_rstn) begin
            o_output_valid <= 1'b0;
            o_output0      <= {OUTPUT_WIDTH{1'b0}};
            o_output1      <= {OUTPUT_WIDTH{1'b0}};
            o_output2      <= {OUTPUT_WIDTH{1'b0}};
            o_output3      <= {OUTPUT_WIDTH{1'b0}};
        end else begin
            if (i_acc_clear) begin
                // i_acc_clear starts a new accumulation window.
                o_output_valid <= 1'b0;
                o_output0      <= {OUTPUT_WIDTH{1'b0}};
                o_output1      <= {OUTPUT_WIDTH{1'b0}};
                o_output2      <= {OUTPUT_WIDTH{1'b0}};
                o_output3      <= {OUTPUT_WIDTH{1'b0}};
            end else begin
                if (i_output_lutram_wr_en) begin
                    // Mirror the MAC outputs externally when they are committed
                    // to the output LUTRAM.
                    o_output_valid <= 1'b1;
                    o_output0      <= mac0;
                    o_output1      <= mac1;
                    o_output2      <= mac2;
                    o_output3      <= mac3;
                end
            end
        end
    end

endmodule
