`timescale 1ns/1ps
module axi_lite_interconnect (
    // ---- Master side (from core) ----
    input  wire [31:0] s_axi_araddr,  input  wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,   output wire [1:0] s_axi_rresp, output wire s_axi_rvalid, input wire s_axi_rready,
    input  wire [31:0] s_axi_awaddr,  input  wire s_axi_awvalid, output wire s_axi_awready,
    input  wire [31:0] s_axi_wdata,   input  wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0]  s_axi_bresp,   output wire s_axi_bvalid, input wire s_axi_bready,

    // ---- Slave 0: BRAM ----
    output wire [31:0] m0_araddr, output wire m0_arvalid, input wire m0_arready,
    input  wire [31:0] m0_rdata,  input  wire [1:0] m0_rresp, input wire m0_rvalid, output wire m0_rready,
    output wire [31:0] m0_awaddr, output wire m0_awvalid, input wire m0_awready,
    output wire [31:0] m0_wdata,  output wire [3:0] m0_wstrb, output wire m0_wvalid, input wire m0_wready,
    input  wire [1:0]  m0_bresp,  input  wire m0_bvalid, output wire m0_bready,

    // ---- Slave 1: GPIO ----
    output wire [31:0] m1_araddr, output wire m1_arvalid, input wire m1_arready,
    input  wire [31:0] m1_rdata,  input  wire [1:0] m1_rresp, input wire m1_rvalid, output wire m1_rready,
    output wire [31:0] m1_awaddr, output wire m1_awvalid, input wire m1_awready,
    output wire [31:0] m1_wdata,  output wire [3:0] m1_wstrb, output wire m1_wvalid, input wire m1_wready,
    input  wire [1:0]  m1_bresp,  input  wire m1_bvalid, output wire m1_bready,

    // ---- Slave 2: UART ----
    output wire [31:0] m2_araddr, output wire m2_arvalid, input wire m2_arready,
    input  wire [31:0] m2_rdata,  input  wire [1:0] m2_rresp, input wire m2_rvalid, output wire m2_rready,
    output wire [31:0] m2_awaddr, output wire m2_awvalid, input wire m2_awready,
    output wire [31:0] m2_wdata,  output wire [3:0] m2_wstrb, output wire m2_wvalid, input wire m2_wready,
    input  wire [1:0]  m2_bresp,  input  wire m2_bvalid, output wire m2_bready,

    // ---- Slave 3: TIMER ----
    output wire [31:0] m3_araddr, output wire m3_arvalid, input wire m3_arready,
    input  wire [31:0] m3_rdata,  input  wire [1:0] m3_rresp, input wire m3_rvalid, output wire m3_rready,
    output wire [31:0] m3_awaddr, output wire m3_awvalid, input wire m3_awready,
    output wire [31:0] m3_wdata,  output wire [3:0] m3_wstrb, output wire m3_wvalid, input wire m3_wready,
    input  wire [1:0]  m3_bresp,  input  wire m3_bvalid, output wire m3_bready
);

    // ---- Read-channel decode/mux (based on araddr, held stable by core) ----
    wire [1:0] rd_sel = s_axi_araddr[29:28]; // 00=BRAM 01=GPIO 10=UART 11=TIMER

    assign m0_araddr = s_axi_araddr; assign m0_arvalid = s_axi_arvalid && (rd_sel==2'd0);
    assign m1_araddr = s_axi_araddr; assign m1_arvalid = s_axi_arvalid && (rd_sel==2'd1);
    assign m2_araddr = s_axi_araddr; assign m2_arvalid = s_axi_arvalid && (rd_sel==2'd2);
    assign m3_araddr = s_axi_araddr; assign m3_arvalid = s_axi_arvalid && (rd_sel==2'd3);

    assign s_axi_arready = (rd_sel==2'd0) ? m0_arready :
                            (rd_sel==2'd1) ? m1_arready :
                            (rd_sel==2'd2) ? m2_arready : m3_arready;

    assign s_axi_rdata   = (rd_sel==2'd0) ? m0_rdata :
                            (rd_sel==2'd1) ? m1_rdata :
                            (rd_sel==2'd2) ? m2_rdata : m3_rdata;
    assign s_axi_rresp   = (rd_sel==2'd0) ? m0_rresp :
                            (rd_sel==2'd1) ? m1_rresp :
                            (rd_sel==2'd2) ? m2_rresp : m3_rresp;
    assign s_axi_rvalid  = (rd_sel==2'd0) ? m0_rvalid :
                            (rd_sel==2'd1) ? m1_rvalid :
                            (rd_sel==2'd2) ? m2_rvalid : m3_rvalid;

    assign m0_rready = s_axi_rready && (rd_sel==2'd0);
    assign m1_rready = s_axi_rready && (rd_sel==2'd1);
    assign m2_rready = s_axi_rready && (rd_sel==2'd2);
    assign m3_rready = s_axi_rready && (rd_sel==2'd3);

    // ---- Write-channel decode/mux (based on awaddr) ----
    wire [1:0] wr_sel = s_axi_awaddr[29:28];

    assign m0_awaddr=s_axi_awaddr; assign m0_awvalid=s_axi_awvalid && (wr_sel==2'd0);
    assign m1_awaddr=s_axi_awaddr; assign m1_awvalid=s_axi_awvalid && (wr_sel==2'd1);
    assign m2_awaddr=s_axi_awaddr; assign m2_awvalid=s_axi_awvalid && (wr_sel==2'd2);
    assign m3_awaddr=s_axi_awaddr; assign m3_awvalid=s_axi_awvalid && (wr_sel==2'd3);

    assign m0_wdata=s_axi_wdata; assign m0_wstrb=s_axi_wstrb; assign m0_wvalid=s_axi_wvalid && (wr_sel==2'd0);
    assign m1_wdata=s_axi_wdata; assign m1_wstrb=s_axi_wstrb; assign m1_wvalid=s_axi_wvalid && (wr_sel==2'd1);
    assign m2_wdata=s_axi_wdata; assign m2_wstrb=s_axi_wstrb; assign m2_wvalid=s_axi_wvalid && (wr_sel==2'd2);
    assign m3_wdata=s_axi_wdata; assign m3_wstrb=s_axi_wstrb; assign m3_wvalid=s_axi_wvalid && (wr_sel==2'd3);

    assign s_axi_awready = (wr_sel==2'd0) ? m0_awready :
                            (wr_sel==2'd1) ? m1_awready :
                            (wr_sel==2'd2) ? m2_awready : m3_awready;
    assign s_axi_wready  = (wr_sel==2'd0) ? m0_wready :
                            (wr_sel==2'd1) ? m1_wready :
                            (wr_sel==2'd2) ? m2_wready : m3_wready;
    assign s_axi_bresp   = (wr_sel==2'd0) ? m0_bresp :
                            (wr_sel==2'd1) ? m1_bresp :
                            (wr_sel==2'd2) ? m2_bresp : m3_bresp;
    assign s_axi_bvalid  = (wr_sel==2'd0) ? m0_bvalid :
                            (wr_sel==2'd1) ? m1_bvalid :
                            (wr_sel==2'd2) ? m2_bvalid : m3_bvalid;

    assign m0_bready = s_axi_bready && (wr_sel==2'd0);
    assign m1_bready = s_axi_bready && (wr_sel==2'd1);
    assign m2_bready = s_axi_bready && (wr_sel==2'd2);
    assign m3_bready = s_axi_bready && (wr_sel==2'd3);

endmodule