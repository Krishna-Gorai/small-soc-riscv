`timescale 1ns/1ps
module axilite_gpio (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axi_araddr, input wire s_axi_arvalid, output reg s_axi_arready,
    output reg  [31:0] s_axi_rdata,  output reg [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    input  wire [31:0] s_axi_awaddr, input wire s_axi_awvalid, output reg s_axi_awready,
    input  wire [31:0] s_axi_wdata,  input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output reg s_axi_wready,
    output reg  [1:0]  s_axi_bresp,  output reg s_axi_bvalid, input wire s_axi_bready,
    output reg  [31:0] gpio_out,   // e.g. LEDs
    input  wire [31:0] gpio_in     // e.g. switches
);
    reg r_state, w_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axi_arready<=1'b1; s_axi_rvalid<=1'b0; s_axi_rdata<=32'd0; s_axi_rresp<=2'b00; r_state<=1'b0; end
        else case (r_state)
            1'b0: begin
                s_axi_arready<=1'b1;
                if (s_axi_arvalid && s_axi_arready) begin
                    case (s_axi_araddr[3:2])
                        2'd0: s_axi_rdata <= gpio_out;
                        2'd1: s_axi_rdata <= gpio_in;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready<=1'b1; s_axi_wready<=1'b1; s_axi_bvalid<=1'b0; s_axi_bresp<=2'b00; w_state<=1'b0; gpio_out<=32'd0;
        end else case (w_state)
            1'b0: if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready) begin
                if (s_axi_awaddr[3:2]==2'd0) begin
                    if (s_axi_wstrb[0]) gpio_out[7:0]   <= s_axi_wdata[7:0];
                    if (s_axi_wstrb[1]) gpio_out[15:8]  <= s_axi_wdata[15:8];
                    if (s_axi_wstrb[2]) gpio_out[23:16] <= s_axi_wdata[23:16];
                    if (s_axi_wstrb[3]) gpio_out[31:24] <= s_axi_wdata[31:24];
                end
                s_axi_awready<=1'b0; s_axi_wready<=1'b0;
                s_axi_bresp<=2'b00; s_axi_bvalid<=1'b1; w_state<=1'b1;
            end
            1'b1: if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid<=1'b0; s_axi_awready<=1'b1; s_axi_wready<=1'b1; w_state<=1'b0;
            end
        endcase
    end
endmodule