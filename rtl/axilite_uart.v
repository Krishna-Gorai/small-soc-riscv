`timescale 1ns/1ps

module axilite_uart #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axi_araddr, input wire s_axi_arvalid, output reg s_axi_arready,
    output reg  [31:0] s_axi_rdata,  output reg [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    input  wire [31:0] s_axi_awaddr, input wire s_axi_awvalid, output reg s_axi_awready,
    input  wire [31:0] s_axi_wdata,  input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output reg s_axi_wready,
    output reg  [1:0]  s_axi_bresp,  output reg s_axi_bvalid, input wire s_axi_bready,
    output wire         uart_tx_pin,
    input  wire         uart_rx_pin
);
    reg  [7:0] tx_data_reg;
    reg        tx_start;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;
    reg        rx_valid_clear;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(rst_n), .tx_data(tx_data_reg), .tx_start(tx_start),
        .tx(uart_tx_pin), .tx_busy(tx_busy)
    );
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx_pin), .rx_data(rx_data),
        .rx_valid(rx_valid), .rx_valid_clear(rx_valid_clear)
    );

    reg r_state, w_state;

    // 0x0=TX(write)/TX-readback(read), 0x4=RX(read, clears rx_valid), 0x8=STATUS{rx_valid,tx_busy}
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready<=1'b1; s_axi_rvalid<=1'b0; s_axi_rdata<=32'd0; s_axi_rresp<=2'b00; r_state<=1'b0; rx_valid_clear<=1'b0;
        end else begin
            rx_valid_clear<=1'b0;
            case (r_state)
                1'b0: begin
                    s_axi_arready<=1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        case (s_axi_araddr[3:2])
                            2'd0: s_axi_rdata <= {24'd0, tx_data_reg};
                            2'd1: begin s_axi_rdata <= {24'd0, rx_data}; rx_valid_clear<=1'b1; end
                            2'd2: s_axi_rdata <= {30'd0, rx_valid, tx_busy};
                            default: s_axi_rdata <= 32'd0;
                        endcase
                        s_axi_rresp<=2'b00; s_axi_rvalid<=1'b1; s_axi_arready<=1'b0; r_state<=1'b1;
                    end
                end
                1'b1: if (s_axi_rvalid && s_axi_rready) begin
                    s_axi_rvalid<=1'b0; s_axi_arready<=1'b1; r_state<=1'b0;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready<=1'b1; s_axi_wready<=1'b1; s_axi_bvalid<=1'b0; s_axi_bresp<=2'b00; w_state<=1'b0; tx_start<=1'b0; tx_data_reg<=8'd0;
        end else begin
            tx_start<=1'b0;
            case (w_state)
                1'b0: if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready) begin
                    if (s_axi_awaddr[3:2]==2'd0 && s_axi_wstrb[0]) begin
                        tx_data_reg<=s_axi_wdata[7:0]; tx_start<=1'b1;
                    end
                    s_axi_awready<=1'b0; s_axi_wready<=1'b0;
                    s_axi_bresp<=2'b00; s_axi_bvalid<=1'b1; w_state<=1'b1;
                end
                1'b1: if (s_axi_bvalid && s_axi_bready) begin
                    s_axi_bvalid<=1'b0; s_axi_awready<=1'b1; s_axi_wready<=1'b1; w_state<=1'b0;
                end
            endcase
        end
    end
endmodule