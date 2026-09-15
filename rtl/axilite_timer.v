`timescale 1ns/1ps
// AXI-Lite timer.
//   0x0  COUNT    (RO)  free-running counter, wraps to 0 when it reaches COMPARE
//   0x4  COMPARE  (RW)  period - 1
//   0x8  CTRL     (RW)  bit0 enable, bit1 irq_en
//   0xC  STATUS   (RW)  bit0 pending: set on every wrap, write 1 to clear
// irq = irq_en & pending (level, cleared by software in the handler).
module axilite_timer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axi_araddr, input wire s_axi_arvalid, output reg s_axi_arready,
    output reg  [31:0] s_axi_rdata,  output reg [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    input  wire [31:0] s_axi_awaddr, input wire s_axi_awvalid, output reg s_axi_awready,
    input  wire [31:0] s_axi_wdata,  input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output reg s_axi_wready,
    output reg  [1:0]  s_axi_bresp,  output reg s_axi_bvalid, input wire s_axi_bready,
    output wire        irq
);
    reg [31:0] count_reg;
    reg [31:0] compare_reg;
    reg        enable_reg, irq_en_reg, pending_reg;
    wire       match = enable_reg && (count_reg >= compare_reg);

    assign irq = irq_en_reg && pending_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) count_reg <= 32'd0;
        else if (!enable_reg) count_reg <= 32'd0;
        else count_reg <= match ? 32'd0 : count_reg + 32'd1;
    end

    reg r_state, w_state;
    wire wr_fire = s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready;
    wire wr_status_clear = wr_fire && (s_axi_awaddr[3:2] == 2'd3) && s_axi_wstrb[0] && s_axi_wdata[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s_axi_arready<=1'b1; s_axi_rvalid<=1'b0; s_axi_rdata<=32'd0; s_axi_rresp<=2'b00; r_state<=1'b0; end
        else case (r_state)
            1'b0: begin
                s_axi_arready<=1'b1;
                if (s_axi_arvalid && s_axi_arready) begin
                    case (s_axi_araddr[3:2])
                        2'd0: s_axi_rdata <= count_reg;
                        2'd1: s_axi_rdata <= compare_reg;
                        2'd2: s_axi_rdata <= {30'd0, irq_en_reg, enable_reg};
                        2'd3: s_axi_rdata <= {31'd0, pending_reg};
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
            s_axi_awready<=1'b1; s_axi_wready<=1'b1; s_axi_bvalid<=1'b0; s_axi_bresp<=2'b00; w_state<=1'b0;
            compare_reg<=32'd0; enable_reg<=1'b0; irq_en_reg<=1'b0; pending_reg<=1'b0;
        end else begin
            // pending: set on wrap, cleared by writing 1 to STATUS (set wins if both)
            if (wr_status_clear) pending_reg <= 1'b0;
            if (match)           pending_reg <= 1'b1;

            case (w_state)
                1'b0: if (wr_fire) begin
                    case (s_axi_awaddr[3:2])
                        2'd1: if (s_axi_wstrb[0]) compare_reg <= s_axi_wdata;
                        2'd2: if (s_axi_wstrb[0]) begin enable_reg <= s_axi_wdata[0]; irq_en_reg <= s_axi_wdata[1]; end
                        default: ;
                    endcase
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
