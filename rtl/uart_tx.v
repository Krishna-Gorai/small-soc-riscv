`timescale 1ns/1ps
module uart_tx #(
    parameter CLKS_PER_BIT = 868 // 100MHz / 115200 baud
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        tx_busy
);
    localparam IDLE=0, START=1, DATA=2, STOP=3;
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; tx<=1'b1; tx_busy<=1'b0; clk_cnt<=0; bit_idx<=0; data_reg<=8'd0;
        end else case (state)
            IDLE: begin
                tx<=1'b1; clk_cnt<=0; bit_idx<=0;
                if (tx_start) begin data_reg<=tx_data; tx_busy<=1'b1; state<=START; end
                else tx_busy<=1'b0;
            end
            START: begin
                tx<=1'b0;
                if (clk_cnt < CLKS_PER_BIT-1) clk_cnt<=clk_cnt+1;
                else begin clk_cnt<=0; state<=DATA; end
            end
            DATA: begin
                tx<=data_reg[bit_idx];
                if (clk_cnt < CLKS_PER_BIT-1) clk_cnt<=clk_cnt+1;
                else begin
                    clk_cnt<=0;
                    if (bit_idx<3'd7) bit_idx<=bit_idx+1;
                    else begin bit_idx<=0; state<=STOP; end
                end
            end
            STOP: begin
                tx<=1'b1;
                if (clk_cnt < CLKS_PER_BIT-1) clk_cnt<=clk_cnt+1;
                else begin clk_cnt<=0; tx_busy<=1'b0; state<=IDLE; end
            end
        endcase
    end
endmodule