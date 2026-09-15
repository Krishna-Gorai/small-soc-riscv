`timescale 1ns/1ps
module axilite_bram_ctrl #(
    parameter MEM_SIZE_WORDS = 8192,   // 32KB
    parameter INIT_FILE      = "program.hex"  // "" = leave uninitialised (TB loads it)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axi_araddr, input wire s_axi_arvalid, output reg s_axi_arready,
    output reg  [31:0] s_axi_rdata,  output reg [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    input  wire [31:0] s_axi_awaddr, input wire s_axi_awvalid, output reg s_axi_awready,
    input  wire [31:0] s_axi_wdata,  input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output reg s_axi_wready,
    output reg  [1:0]  s_axi_bresp,  output reg s_axi_bvalid, input wire s_axi_bready
);
    reg [31:0] mem [0:MEM_SIZE_WORDS-1];

    // Program image. Kept synthesizable (no translate_off) so the BRAM is
    // initialised in the bitstream as well as in simulation.
    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    // ---- Memory array: synchronous, no reset (lets Vivado infer block RAM) ----
    wire rd_fire = s_axi_arvalid && s_axi_arready;
    wire wr_fire = s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready;

    always @(posedge clk) begin
        if (rd_fire) s_axi_rdata <= mem[s_axi_araddr[14:2]];
        if (wr_fire) begin
            if (s_axi_wstrb[0]) mem[s_axi_awaddr[14:2]][7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) mem[s_axi_awaddr[14:2]][15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) mem[s_axi_awaddr[14:2]][23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) mem[s_axi_awaddr[14:2]][31:24] <= s_axi_wdata[31:24];
        end
    end

    // ---- Read handshake FSM ----
    localparam R_IDLE=1'b0, R_RESP=1'b1;
    reg r_state;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready<=1'b1; s_axi_rvalid<=1'b0; s_axi_rresp<=2'b00; r_state<=R_IDLE;
        end else case (r_state)
            R_IDLE: begin
                s_axi_arready<=1'b1;
                if (rd_fire) begin
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    s_axi_arready<= 1'b0;
                    r_state<=R_RESP;
                end
            end
            R_RESP: if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid<=1'b0; s_axi_arready<=1'b1; r_state<=R_IDLE;
            end
        endcase
    end

    // ---- Write handshake FSM ----
    localparam W_IDLE=1'b0, W_RESP=1'b1;
    reg w_state;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready<=1'b1; s_axi_wready<=1'b1; s_axi_bvalid<=1'b0; s_axi_bresp<=2'b00; w_state<=W_IDLE;
        end else case (w_state)
            W_IDLE: if (wr_fire) begin
                s_axi_awready<=1'b0; s_axi_wready<=1'b0;
                s_axi_bresp<=2'b00; s_axi_bvalid<=1'b1; w_state<=W_RESP;
            end
            W_RESP: if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid<=1'b0; s_axi_awready<=1'b1; s_axi_wready<=1'b1; w_state<=W_IDLE;
            end
        endcase
    end
endmodule
