`timescale 1ns / 1ps

module simple_line_lutram #(
    parameter WIDTH          = 128,
    parameter DEPTH          = 4,
    parameter ADDR_WIDTH     = $clog2(DEPTH),
    parameter RD_WIDTH       = 16,
    parameter BANK_DEPTH     = WIDTH / RD_WIDTH,
    parameter BANK_SEL_WIDTH = $clog2(BANK_DEPTH)
)(
    input  wire                      clk,
    input  wire                      wr_en,
    input  wire [ADDR_WIDTH-1:0]     wr_addr,
    input  wire [WIDTH-1:0]          wr_din,
    input  wire                      rd_en,
    input  wire [ADDR_WIDTH-1:0]     rd_addr,
    input  wire [BANK_SEL_WIDTH-1:0] rd_sel,
    output reg  [RD_WIDTH-1:0]       rd_dout
);

    // Each bank stores one RD_WIDTH slice of the wide line.
    wire [BANK_DEPTH*RD_WIDTH-1:0] bank_do;  // data from all banks
    wire [RD_WIDTH-1:0]            sel_do;   // selected bank output

    genvar b;
    generate
        for (b = 0; b < BANK_DEPTH; b = b + 1) begin : gen_bank
            integer i;
            // Distributed RAM bank for one element position inside the line.
            (* ram_style = "distributed" *) reg [RD_WIDTH-1:0] ram [0:DEPTH-1]; // one LUTRAM bank

            // Clear LUTRAM contents for deterministic simulation startup.
            initial begin
                for (i = 0; i < DEPTH; i = i + 1)
                    ram[i] = {RD_WIDTH{1'b0}};
            end

            always @(posedge clk) begin
                // Write one slice of the incoming wide line into this bank.
                if (wr_en)
                    ram[wr_addr] <= wr_din[(b*RD_WIDTH) +: RD_WIDTH];
            end

            // Asynchronous bank read; selected output is registered below.
            assign bank_do[(b*RD_WIDTH) +: RD_WIDTH] = ram[rd_addr];
        end
    endgenerate

    // Select one element from the addressed line.
    assign sel_do = bank_do[(rd_sel*RD_WIDTH) +: RD_WIDTH];

    always @(posedge clk) begin
        // Register the selected element to match the rest of the datapath.
        if (rd_en)
            rd_dout <= sel_do;
        else
            rd_dout <= {RD_WIDTH{1'b0}};
    end
endmodule
