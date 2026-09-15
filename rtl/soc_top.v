`timescale 1ns/1ps

module soc_top #(
    parameter CLKS_PER_BIT = 868,
    parameter INIT_FILE    = "program.hex"
)(
    input  wire        clk,
    input  wire        rst_n_pin,   // active-low reset button
    output wire [31:0] led,
    input  wire [31:0] sw,
    output wire         uart_tx_pin,
    input  wire         uart_rx_pin
);
    // 2-FF reset synchronizer
    reg rst_sync0, rst_n;
    always @(posedge clk or negedge rst_n_pin) begin
        if (!rst_n_pin) begin rst_sync0<=1'b0; rst_n<=1'b0; end
        else begin rst_sync0<=1'b1; rst_n<=rst_sync0; end
    end

    // Core <-> Interconnect wires
    wire [31:0] c_araddr, c_awaddr, c_wdata, c_rdata;
    wire [3:0]  c_wstrb;
    wire [1:0]  c_rresp, c_bresp;
    wire        c_arvalid, c_arready, c_rvalid, c_rready;
    wire        c_awvalid, c_awready, c_wvalid, c_wready, c_bvalid, c_bready;

    wire irq_timer;

    riscv_core u_core (
        .clk(clk), .rst_n(rst_n), .irq_timer(irq_timer),
        .m_axi_araddr(c_araddr), .m_axi_arvalid(c_arvalid), .m_axi_arready(c_arready),
        .m_axi_rdata(c_rdata),   .m_axi_rresp(c_rresp), .m_axi_rvalid(c_rvalid), .m_axi_rready(c_rready),
        .m_axi_awaddr(c_awaddr), .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
        .m_axi_wdata(c_wdata),   .m_axi_wstrb(c_wstrb), .m_axi_wvalid(c_wvalid), .m_axi_wready(c_wready),
        .m_axi_bresp(c_bresp),   .m_axi_bvalid(c_bvalid), .m_axi_bready(c_bready)
    );

    // Interconnect <-> Slave wires
    wire [31:0] b_araddr,b_rdata,b_awaddr,b_wdata, g_araddr,g_rdata,g_awaddr,g_wdata,
                u_araddr,u_rdata,u_awaddr,u_wdata, t_araddr,t_rdata,t_awaddr,t_wdata;
    wire [3:0]  b_wstrb,g_wstrb,u_wstrb,t_wstrb;
    wire [1:0]  b_rresp,b_bresp,g_rresp,g_bresp,u_rresp,u_bresp,t_rresp,t_bresp;
    wire b_arvalid,b_arready,b_rvalid,b_rready,b_awvalid,b_awready,b_wvalid,b_wready,b_bvalid,b_bready;
    wire g_arvalid,g_arready,g_rvalid,g_rready,g_awvalid,g_awready,g_wvalid,g_wready,g_bvalid,g_bready;
    wire u_arvalid,u_arready,u_rvalid,u_rready,u_awvalid,u_awready,u_wvalid,u_wready,u_bvalid,u_bready;
    wire t_arvalid,t_arready,t_rvalid,t_rready,t_awvalid,t_awready,t_wvalid,t_wready,t_bvalid,t_bready;

    axi_lite_interconnect u_xbar (
        .s_axi_araddr(c_araddr), .s_axi_arvalid(c_arvalid), .s_axi_arready(c_arready),
        .s_axi_rdata(c_rdata),   .s_axi_rresp(c_rresp), .s_axi_rvalid(c_rvalid), .s_axi_rready(c_rready),
        .s_axi_awaddr(c_awaddr), .s_axi_awvalid(c_awvalid), .s_axi_awready(c_awready),
        .s_axi_wdata(c_wdata),   .s_axi_wstrb(c_wstrb), .s_axi_wvalid(c_wvalid), .s_axi_wready(c_wready),
        .s_axi_bresp(c_bresp),   .s_axi_bvalid(c_bvalid), .s_axi_bready(c_bready),

        .m0_araddr(b_araddr), .m0_arvalid(b_arvalid), .m0_arready(b_arready),
        .m0_rdata(b_rdata),   .m0_rresp(b_rresp), .m0_rvalid(b_rvalid), .m0_rready(b_rready),
        .m0_awaddr(b_awaddr), .m0_awvalid(b_awvalid), .m0_awready(b_awready),
        .m0_wdata(b_wdata),   .m0_wstrb(b_wstrb), .m0_wvalid(b_wvalid), .m0_wready(b_wready),
        .m0_bresp(b_bresp),   .m0_bvalid(b_bvalid), .m0_bready(b_bready),

        .m1_araddr(g_araddr), .m1_arvalid(g_arvalid), .m1_arready(g_arready),
        .m1_rdata(g_rdata),   .m1_rresp(g_rresp), .m1_rvalid(g_rvalid), .m1_rready(g_rready),
        .m1_awaddr(g_awaddr), .m1_awvalid(g_awvalid), .m1_awready(g_awready),
        .m1_wdata(g_wdata),   .m1_wstrb(g_wstrb), .m1_wvalid(g_wvalid), .m1_wready(g_wready),
        .m1_bresp(g_bresp),   .m1_bvalid(g_bvalid), .m1_bready(g_bready),

        .m2_araddr(u_araddr), .m2_arvalid(u_arvalid), .m2_arready(u_arready),
        .m2_rdata(u_rdata),   .m2_rresp(u_rresp), .m2_rvalid(u_rvalid), .m2_rready(u_rready),
        .m2_awaddr(u_awaddr), .m2_awvalid(u_awvalid), .m2_awready(u_awready),
        .m2_wdata(u_wdata),   .m2_wstrb(u_wstrb), .m2_wvalid(u_wvalid), .m2_wready(u_wready),
        .m2_bresp(u_bresp),   .m2_bvalid(u_bvalid), .m2_bready(u_bready),

        .m3_araddr(t_araddr), .m3_arvalid(t_arvalid), .m3_arready(t_arready),
        .m3_rdata(t_rdata),   .m3_rresp(t_rresp), .m3_rvalid(t_rvalid), .m3_rready(t_rready),
        .m3_awaddr(t_awaddr), .m3_awvalid(t_awvalid), .m3_awready(t_awready),
        .m3_wdata(t_wdata),   .m3_wstrb(t_wstrb), .m3_wvalid(t_wvalid), .m3_wready(t_wready),
        .m3_bresp(t_bresp),   .m3_bvalid(t_bvalid), .m3_bready(t_bready)
    );

    axilite_bram_ctrl #(.MEM_SIZE_WORDS(8192), .INIT_FILE(INIT_FILE)) u_bram (
        .clk(clk), .rst_n(rst_n),
        .s_axi_araddr(b_araddr), .s_axi_arvalid(b_arvalid), .s_axi_arready(b_arready),
        .s_axi_rdata(b_rdata),   .s_axi_rresp(b_rresp), .s_axi_rvalid(b_rvalid), .s_axi_rready(b_rready),
        .s_axi_awaddr(b_awaddr), .s_axi_awvalid(b_awvalid), .s_axi_awready(b_awready),
        .s_axi_wdata(b_wdata),   .s_axi_wstrb(b_wstrb), .s_axi_wvalid(b_wvalid), .s_axi_wready(b_wready),
        .s_axi_bresp(b_bresp),   .s_axi_bvalid(b_bvalid), .s_axi_bready(b_bready)
    );

    axilite_gpio u_gpio (
        .clk(clk), .rst_n(rst_n),
        .s_axi_araddr(g_araddr), .s_axi_arvalid(g_arvalid), .s_axi_arready(g_arready),
        .s_axi_rdata(g_rdata),   .s_axi_rresp(g_rresp), .s_axi_rvalid(g_rvalid), .s_axi_rready(g_rready),
        .s_axi_awaddr(g_awaddr), .s_axi_awvalid(g_awvalid), .s_axi_awready(g_awready),
        .s_axi_wdata(g_wdata),   .s_axi_wstrb(g_wstrb), .s_axi_wvalid(g_wvalid), .s_axi_wready(g_wready),
        .s_axi_bresp(g_bresp),   .s_axi_bvalid(g_bvalid), .s_axi_bready(g_bready),
        .gpio_out(led), .gpio_in(sw)
    );

    axilite_uart #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .s_axi_araddr(u_araddr), .s_axi_arvalid(u_arvalid), .s_axi_arready(u_arready),
        .s_axi_rdata(u_rdata),   .s_axi_rresp(u_rresp), .s_axi_rvalid(u_rvalid), .s_axi_rready(u_rready),
        .s_axi_awaddr(u_awaddr), .s_axi_awvalid(u_awvalid), .s_axi_awready(u_awready),
        .s_axi_wdata(u_wdata),   .s_axi_wstrb(u_wstrb), .s_axi_wvalid(u_wvalid), .s_axi_wready(u_wready),
        .s_axi_bresp(u_bresp),   .s_axi_bvalid(u_bvalid), .s_axi_bready(u_bready),
        .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    axilite_timer u_timer (
        .clk(clk), .rst_n(rst_n),
        .s_axi_araddr(t_araddr), .s_axi_arvalid(t_arvalid), .s_axi_arready(t_arready),
        .s_axi_rdata(t_rdata),   .s_axi_rresp(t_rresp), .s_axi_rvalid(t_rvalid), .s_axi_rready(t_rready),
        .s_axi_awaddr(t_awaddr), .s_axi_awvalid(t_awvalid), .s_axi_awready(t_awready),
        .s_axi_wdata(t_wdata),   .s_axi_wstrb(t_wstrb), .s_axi_wvalid(t_wvalid), .s_axi_wready(t_wready),
        .s_axi_bresp(t_bresp),   .s_axi_bvalid(t_bvalid), .s_axi_bready(t_bready),
        .irq(irq_timer)
    );

endmodule