`timescale 1ns / 1ps

module simple_dual_port_bram #(
    parameter WIDTH      = 16,
    parameter DEPTH      = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_FILE  = ""
)(
    input  wire                  clk        ,
    input  wire                  wr_en      ,
    input  wire                  rd_en      ,
    input  wire [ADDR_WIDTH-1:0] wr_addr    ,
    input  wire [ADDR_WIDTH-1:0] rd_addr    ,
    input  wire [WIDTH-1:0]      wr_din     ,
    output reg                   rd_valid   ,
    output reg  [WIDTH-1:0]      rd_dout
);

    // Inferred block RAM storage.
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Optional memory initialization.
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
        if (wr_en)
            mem[wr_addr] <= wr_din;

        // Synchronous read port. rd_valid follows rd_en by one clock.
        if (rd_en) begin
            rd_dout <= mem[rd_addr]; // READ_FIRST
        end

        rd_valid <= rd_en;
    end

endmodule
