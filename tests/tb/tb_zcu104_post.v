`timescale 1ns/1ps
// Board-level testbench for the implemented netlist (fpga/build/zcu104_top_funcsim.v).
// Drives the real 300 MHz differential clock and decodes the UART at the real
// 115200 baud (868 clocks/bit at 100 MHz). Gate-level simulation is slow, so it
// passes as soon as "Hello" has been received rather than the whole banner.
module tb_zcu104_post;
    reg  clk300_p = 0;
    wire clk300_n = ~clk300_p;
    reg  cpu_reset = 0;
    reg  [3:0] dip = 4'b0101;
    reg  [3:0] pb  = 4'b0000;
    wire [3:0] led;
    wire uart_tx;
    reg  uart_rx = 1'b1;

    always #1.6667 clk300_p = ~clk300_p;          // 300 MHz

    zcu104_top dut (
        .clk300_p(clk300_p), .clk300_n(clk300_n), .cpu_reset(cpu_reset),
        .dip(dip), .pb(pb), .led(led), .uart_tx(uart_tx), .uart_rx(uart_rx)
    );

    localparam real BIT_NS = 1e9 / 115200.0;      // 8680.6 ns
    localparam [8*5-1:0] EXPECT = "Hello";
    reg [8*5-1:0] window = 0;
    reg [7:0] rx_byte;
    integer i;
    initial begin
        #200;                                     // let GSR release before arming
        forever begin
            @(negedge uart_tx);
            #(BIT_NS * 1.5);
            for (i = 0; i < 8; i = i + 1) begin
                rx_byte[i] = uart_tx;
                #(BIT_NS);
            end
            if (rx_byte != 8'h0D) $write("%c", rx_byte);
            $fflush;
            window = {window[8*4-1:0], rx_byte};
            if (window == EXPECT) begin
                $display("\nPASS: post-implementation netlist prints the banner (t=%0t, led=%b)", $time, led);
                $finish;
            end
        end
    end

    initial begin
        #3000000;                                 // 3 ms watchdog
        $display("\nFAIL: timeout, led=%b", led);
        $finish;
    end
endmodule
