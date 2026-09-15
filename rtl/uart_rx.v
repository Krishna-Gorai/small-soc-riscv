`timescale 1ns/1ps
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    input  wire       rx_valid_clear
);
    localparam IDLE=0, START=1, DATA=2, STOP=3;
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_reg;
    reg rx_sync0, rx_sync1; // 2-FF synchronizer for the async rx line

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_sync0<=1'b1; rx_sync1<=1'b1; end
        else begin rx_sync0<=rx; rx_sync1<=rx_sync0; end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; clk_cnt<=0; bit_idx<=0; rx_valid<=1'b0; rx_data<=8'd0; data_reg<=8'd0; end
        else begin
            if (rx_valid_clear) rx_valid<=1'b0;
            case (state)
                IDLE: begin
                    clk_cnt<=0; bit_idx<=0;
                    if (rx_sync1==1'b0) state<=START;
                end
                START: begin
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rx_sync1==1'b0) begin clk_cnt<=0; state<=DATA; end
                        else state<=IDLE; // glitch, false start
                    end else clk_cnt<=clk_cnt+1;
                end
                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT-1) clk_cnt<=clk_cnt+1;
                    else begin
                        clk_cnt<=0;
                        data_reg[bit_idx]<=rx_sync1;
                        if (bit_idx<3'd7) bit_idx<=bit_idx+1;
                        else begin bit_idx<=0; state<=STOP; end
                    end
                end
                STOP: begin
                    if (clk_cnt < CLKS_PER_BIT-1) clk_cnt<=clk_cnt+1;
                    else begin clk_cnt<=0; rx_data<=data_reg; rx_valid<=1'b1; state<=IDLE; end
                end
            endcase
        end
    end
endmodule