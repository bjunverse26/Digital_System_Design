//==============================================================================
// File Name   : simple_dual_port_bram.v
// Project     : Digital System Design - Lab03
// Author      : Beomjun Kim
// Description : Parameterized simple dual-port block RAM wrapper.
// Notes       : Supports one synchronous write port, one synchronous read port,
//               and optional memory initialization by hex file.
//==============================================================================

`timescale 1ns / 1ps

module simple_dual_port_bram #(
    parameter WIDTH      = 16,
    parameter DEPTH      = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_FILE  = ""
)(
    input  wire                  clk,
    input  wire                  wr_en,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire [WIDTH-1:0]      wr_din,
    
    output reg                   rd_valid,
    output reg  [WIDTH-1:0]      rd_dout
);

    // Inferred block RAM storage.
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Optional simulation/synthesis memory initialization.
    generate
        if (INIT_FILE != "") begin : use_init_file
            initial begin
                $readmemh(INIT_FILE, mem);
            end
        end else begin : init_to_zero
            integer i;
            initial begin
                for (i = 0; i < DEPTH; i = i + 1)
                    mem[i] = {WIDTH{1'b0}};
            end
        end
    endgenerate

    always @(posedge clk) begin
        // Independent write port.
        if (wr_en) begin
            mem[wr_addr] <= wr_din;
        end

        if (rd_en) begin
            rd_dout <= mem[rd_addr]; // READ_FIRST
        end

        rd_valid <= rd_en;
    end

endmodule
