`timescale 1ns / 1ps

module tb_prob1();

    parameter WIDTH      = 128;
    parameter DEPTH      = 4096;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    reg                   clk;
    reg                   wr_en;
    reg                   rd_en;
    reg  [ADDR_WIDTH-1:0] wr_addr;
    reg  [ADDR_WIDTH-1:0] rd_addr;
    reg  [WIDTH-1:0]      wr_din;

    wire                  rd_valid;
    wire [WIDTH-1:0]      rd_dout;

    // uram_inst
    simple_dual_port_uram #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE("")
    ) uram_inst (
        .clk(clk),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wr_addr(wr_addr),
        .rd_addr(rd_addr),
        .wr_din(wr_din),
        .rd_valid(rd_valid),
        .rd_dout(rd_dout)
    );

    // 10ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        // initial setting
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_addr = 0;
        rd_addr = 0;
        wr_din  = 0;
        
        // ==================================================
        // WRITE SECTION
        // ==================================================
        repeat (2) @(posedge clk);
        wr_en   = 1'b1;
        wr_addr = 2'd0;
        wr_din  = 128'h0002_0003_0004_0005_0002_0003_0004_0005;
        
        @(posedge clk);
        wr_addr = 2'd1;
        wr_din  = 128'h0003_0004_0005_0006_0003_0004_0005_0006;
        
        @(posedge clk);
        wr_addr = 2'd2;
        wr_din  = 128'h0004_0005_0006_0007_0004_0005_0006_0007;
        
        @(posedge clk);
        wr_addr = 2'd3;
        wr_din  = 128'h0005_0006_0007_0008_0005_0006_0007_0008;
        
        @(posedge clk);
        wr_en   = 1'b0;
        wr_addr = 1'b0;
        @(posedge clk);
        // ==================================================
        // READ SECTION
        // ==================================================
        rd_en   = 1'b1;
        rd_addr = 2'd0;
        
        @(posedge clk);
        rd_addr = 2'd1;
        
        @(posedge clk);
        rd_addr = 2'd2;
        
        @(posedge clk);
        rd_addr = 2'd3;
        
        @(posedge clk);
        rd_en   = 1'b0;
        rd_addr = 1'b0;
        
        #10
        $finish;
    end
endmodule