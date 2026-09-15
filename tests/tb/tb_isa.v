`timescale 1ns/1ps
// Generic program-runner testbench for Small_SoC.
//
//   +HEX=<file>        program image (one 32-bit word per line), loaded into BRAM;
//                      defaults to "prog.hex" in the run directory (the Vivado
//                      .bat wrappers on Windows cannot pass '=' in plusargs)
//   +TIMEOUT=<cycles>  watchdog, default 300000 (or the number in "timeout.txt"
//                      in the run directory, if that file exists)
//   +UART_STIM         send "Hi<LF>" into the SoC's UART RX once the SoC's own
//                      TX has been idle for 50 us (i.e. after any start-up banner)
//
// The program signals completion through the GPIO output register:
//   0x0000600D          -> "RESULT: PASS"
//   0xBAD00000 | n      -> "RESULT: FAIL test n"
// Anything the program sends on the UART is decoded and echoed to the console.
module tb_isa;
    reg clk = 0;
    reg rst_n_pin = 0;
    wire [31:0] led;
    reg  [31:0] sw = 32'h0000_00A5;
    wire uart_tx_pin;
    reg  uart_rx_pin = 1'b1;

    localparam CLKS_PER_BIT = 20;     // fast UART for simulation
    localparam CLK_PERIOD   = 10;     // ns

    always #(CLK_PERIOD/2) clk = ~clk;

    soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT), .INIT_FILE("")) dut (
        .clk(clk), .rst_n_pin(rst_n_pin), .led(led), .sw(sw),
        .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin),
        .jtag_tck(1'b0), .jtag_tdi(1'b0), .jtag_tdo(), .jtag_sel(1'b0),
        .jtag_capture(1'b0), .jtag_shift(1'b0), .jtag_update(1'b0)
    );

    // ---- program load ----
    reg [1023:0] hexfile;
    integer timeout_cycles, fd;
    initial begin
        if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "prog.hex";
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles)) timeout_cycles = 300000;
        fd = $fopen("timeout.txt", "r");
        if (fd != 0) begin
            if ($fscanf(fd, "%d", timeout_cycles) != 1) timeout_cycles = 300000;
            $fclose(fd);
        end
        $readmemh(hexfile, dut.u_bram.mem);
    end

    // ---- reset ----
    initial begin
        rst_n_pin = 0;
        repeat (5) @(posedge clk);
        rst_n_pin = 1;
    end

    // ---- UART TX decoder (8N1) ----
    reg [7:0] rx_byte;
    integer   i;
    initial begin
        forever begin
            @(negedge uart_tx_pin);                       // start bit
            #(CLK_PERIOD * CLKS_PER_BIT * 1.5);           // middle of bit 0
            for (i = 0; i < 8; i = i + 1) begin
                rx_byte[i] = uart_tx_pin;
                #(CLK_PERIOD * CLKS_PER_BIT);
            end
            if (rx_byte != 8'h0D) $write("%c", rx_byte);   // drop CR: console adds its own
            $fflush;
        end
    end

    // ---- optional UART RX stimulus (8N1) ----
    task uart_send(input [7:0] b);
        integer k;
        begin
            uart_rx_pin = 1'b0;                          // start
            #(CLK_PERIOD * CLKS_PER_BIT);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_pin = b[k];
                #(CLK_PERIOD * CLKS_PER_BIT);
            end
            uart_rx_pin = 1'b1;                          // stop
            #(CLK_PERIOD * CLKS_PER_BIT * 12);           // stop + gap: RX has a 1-byte buffer
        end
    endtask
    time last_tx_edge = 0;
    always @(negedge uart_tx_pin) last_tx_edge = $time;
    initial begin
        if ($test$plusargs("UART_STIM")) begin
            #10000;
            while ($time - last_tx_edge < 50000) #10000;
            uart_send("H"); uart_send("i"); uart_send(8'h0A);
        end
    end

    // ---- result / watchdog ----
    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (rst_n_pin) begin
            if (led == 32'h0000_600D) begin
                $display("\nRESULT: PASS (%0d cycles)", cycles);
                $finish;
            end else if (led[31:20] == 12'hBAD) begin
                $display("\nRESULT: FAIL test %0d (%0d cycles)", led[19:0], cycles);
                $finish;
            end else if (cycles >= timeout_cycles) begin
                $display("\nRESULT: TIMEOUT after %0d cycles, pc=%08h led=%08h",
                         cycles, dut.u_core.pc_reg, led);
                $finish;
            end
        end
    end
endmodule
