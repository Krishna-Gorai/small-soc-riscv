`timescale 1ns/1ps
// Vivado-project testbench: boots the hardware program image (program.hex,
// built from sw/hello) and passes when the start-up banner appears on the
// UART. For the ISA regression and other programs use tests/tb/tb_isa.v.
module tb_soc_top;
    reg clk = 0;
    reg rst_n_pin = 0;
    wire [31:0] led;
    reg  [31:0] sw = 32'h0000_0005;
    wire uart_tx_pin;
    reg  uart_rx_pin = 1'b1;

    localparam CLKS_PER_BIT = 20;      // fast UART for simulation
    localparam CLK_PERIOD   = 10;      // ns
    always #(CLK_PERIOD/2) clk = ~clk;

    soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk(clk), .rst_n_pin(rst_n_pin),
        .led(led), .sw(sw),
        .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin)
    );

    // ---- UART TX decoder (8N1) ----
    localparam [8*20-1:0] EXPECT = "Hello from Small_SoC";
    reg [8*20-1:0] window = 0;
    reg [7:0] rx_byte;
    integer   i;
    initial begin
        forever begin
            @(negedge uart_tx_pin);
            #(CLK_PERIOD * CLKS_PER_BIT * 1.5);
            for (i = 0; i < 8; i = i + 1) begin
                rx_byte[i] = uart_tx_pin;
                #(CLK_PERIOD * CLKS_PER_BIT);
            end
            if (rx_byte != 8'h0D) $write("%c", rx_byte);
            window = {window[8*19-1:0], rx_byte};
            if (window == EXPECT) begin
                $display("\nPASS: banner received at %0t", $time);
                #200;
                $finish;
            end
        end
    end

    initial begin
        rst_n_pin = 0;
        repeat (5) @(posedge clk);
        rst_n_pin = 1;
        #2000000;
        $display("\nFAIL: timeout, no banner. led=%08h pc=%08h", led, dut.u_core.pc_reg);
        $finish;
    end
endmodule
