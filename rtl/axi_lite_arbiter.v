`timescale 1ns/1ps
// Two-master AXI-Lite arbiter: m0 (core) and m1 (debug) share one slave port.
//
// m0 has priority. m1 is granted only when m0 has nothing in flight (no valid
// asserted, no response awaited) and keeps the bus until its own request has
// completed; meanwhile m0's valids are masked from the slave and its readies
// are held low, so the core simply waits. No transaction is ever cut short,
// so the AXI handshake rules hold for both masters.
module axi_lite_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    // ---- master 0 (core) ----
    input  wire [31:0] m0_araddr, input wire m0_arvalid, output wire m0_arready,
    output wire [31:0] m0_rdata,  output wire [1:0] m0_rresp, output wire m0_rvalid, input wire m0_rready,
    input  wire [31:0] m0_awaddr, input wire m0_awvalid, output wire m0_awready,
    input  wire [31:0] m0_wdata,  input wire [3:0] m0_wstrb, input wire m0_wvalid, output wire m0_wready,
    output wire [1:0]  m0_bresp,  output wire m0_bvalid, input wire m0_bready,

    // ---- master 1 (debug) ----
    input  wire [31:0] m1_araddr, input wire m1_arvalid, output wire m1_arready,
    output wire [31:0] m1_rdata,  output wire [1:0] m1_rresp, output wire m1_rvalid, input wire m1_rready,
    input  wire [31:0] m1_awaddr, input wire m1_awvalid, output wire m1_awready,
    input  wire [31:0] m1_wdata,  input wire [3:0] m1_wstrb, input wire m1_wvalid, output wire m1_wready,
    output wire [1:0]  m1_bresp,  output wire m1_bvalid, input wire m1_bready,

    // ---- slave side (to interconnect) ----
    output wire [31:0] s_araddr, output wire s_arvalid, input wire s_arready,
    input  wire [31:0] s_rdata,  input  wire [1:0] s_rresp, input wire s_rvalid, output wire s_rready,
    output wire [31:0] s_awaddr, output wire s_awvalid, input wire s_awready,
    output wire [31:0] s_wdata,  output wire [3:0] s_wstrb, output wire s_wvalid, input wire s_wready,
    input  wire [1:0]  s_bresp,  input  wire s_bvalid, output wire s_bready
);
    wire m0_busy = m0_arvalid | m0_rready | m0_awvalid | m0_wvalid | m0_bready;
    wire m1_busy = m1_arvalid | m1_rready | m1_awvalid | m1_wvalid | m1_bready;

    reg grant1;   // 1 = debug master owns the bus
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           grant1 <= 1'b0;
        else if (!grant1)     grant1 <= m1_busy && !m0_busy;
        else                  grant1 <= m1_busy;          // release when debug is idle
    end

    assign s_araddr  = grant1 ? m1_araddr  : m0_araddr;
    assign s_arvalid = grant1 ? m1_arvalid : m0_arvalid;
    assign s_rready  = grant1 ? m1_rready  : m0_rready;
    assign s_awaddr  = grant1 ? m1_awaddr  : m0_awaddr;
    assign s_awvalid = grant1 ? m1_awvalid : m0_awvalid;
    assign s_wdata   = grant1 ? m1_wdata   : m0_wdata;
    assign s_wstrb   = grant1 ? m1_wstrb   : m0_wstrb;
    assign s_wvalid  = grant1 ? m1_wvalid  : m0_wvalid;
    assign s_bready  = grant1 ? m1_bready  : m0_bready;

    assign m0_arready = !grant1 & s_arready;
    assign m0_rvalid  = !grant1 & s_rvalid;
    assign m0_awready = !grant1 & s_awready;
    assign m0_wready  = !grant1 & s_wready;
    assign m0_bvalid  = !grant1 & s_bvalid;
    assign m0_rdata   = s_rdata;  assign m0_rresp = s_rresp; assign m0_bresp = s_bresp;

    assign m1_arready =  grant1 & s_arready;
    assign m1_rvalid  =  grant1 & s_rvalid;
    assign m1_awready =  grant1 & s_awready;
    assign m1_wready  =  grant1 & s_wready;
    assign m1_bvalid  =  grant1 & s_bvalid;
    assign m1_rdata   = s_rdata;  assign m1_rresp = s_rresp; assign m1_bresp = s_bresp;
endmodule
