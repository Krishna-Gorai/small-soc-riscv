`timescale 1ns/1ps
// ZCU104 board wrapper for soc_top.
//
//  * 300 MHz differential board clock -> IBUFDS -> BUFGCE_DIV(/3) = 100 MHz.
//    No MMCM and no IP, so the whole design is plain Verilog + two primitives.
//  * CPU_RESET push button (active high) is synchronised and stretched into a
//    128-cycle power-on reset; the SoC also comes out of reset by itself after
//    configuration, without the button ever being pressed.
//  * GPIO: LEDs 0-3 on the low nibble of GPIO_OUT; GPIO_IN = {push buttons, DIP}.
//  * UART on the PL channel of the on-board CP2108 USB-UART bridge.
//  * JTAG debug port through BSCANE2 (USER1): the SoC's jtag_dbg hangs off the
//    FPGA's own JTAG chain, so the board's USB-JTAG reaches it with no extra pins.
module zcu104_top (
    input  wire       clk300_p,
    input  wire       clk300_n,
    input  wire       cpu_reset,     // push button, active high
    input  wire [3:0] dip,           // GPIO_DIP_SW[3:0]
    input  wire [3:0] pb,            // GPIO_PB_SW[3:0]
    output wire [3:0] led,           // GPIO_LED[3:0]
    output wire       uart_tx,       // to CP2108 (uart2_PL_TX)
    input  wire       uart_rx        // from CP2108 (uart2_PL_RX)
);
    localparam CLK_HZ       = 100_000_000;
    localparam BAUD         = 115_200;
    localparam CLKS_PER_BIT = CLK_HZ / BAUD;   // 868

    // ---- clock ----
    wire clk_ref, clk;
    IBUFDS u_ibufds (.I(clk300_p), .IB(clk300_n), .O(clk_ref));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(3)) u_div (.I(clk_ref), .CE(1'b1), .CLR(1'b0), .O(clk));

    // ---- reset: synchronise the button, then hold reset for 128 cycles ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync = 2'b00;
    reg [6:0] rst_cnt = 7'd0;
    reg       rst_n   = 1'b0;
    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], cpu_reset};
        if (rst_sync[1]) begin
            rst_cnt <= 7'd0;
            rst_n   <= 1'b0;
        end else if (rst_cnt != 7'd127) begin
            rst_cnt <= rst_cnt + 7'd1;
            rst_n   <= 1'b0;
        end else begin
            rst_n   <= 1'b1;
        end
    end

    // ---- JTAG: USER1 register of the device's own TAP ----
    wire bs_tck, bs_tdi, bs_tdo, bs_sel, bs_capture, bs_shift, bs_update, bs_tck_buf;
    BSCANE2 #(.JTAG_CHAIN(1)) u_bscan (
        .CAPTURE(bs_capture), .DRCK(), .RESET(), .RUNTEST(), .SEL(bs_sel),
        .SHIFT(bs_shift), .TCK(bs_tck), .TDI(bs_tdi), .TMS(), .UPDATE(bs_update),
        .TDO(bs_tdo)
    );
    BUFG u_tck_bufg (.I(bs_tck), .O(bs_tck_buf));

    // ---- SoC ----
    wire [31:0] gpio_out;
    soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_soc (
        .clk(clk), .rst_n_pin(rst_n),
        .led(gpio_out), .sw({24'd0, pb, dip}),
        .uart_tx_pin(uart_tx), .uart_rx_pin(uart_rx),
        .jtag_tck(bs_tck_buf), .jtag_tdi(bs_tdi), .jtag_tdo(bs_tdo), .jtag_sel(bs_sel),
        .jtag_capture(bs_capture), .jtag_shift(bs_shift), .jtag_update(bs_update)
    );
    assign led = gpio_out[3:0];
endmodule
