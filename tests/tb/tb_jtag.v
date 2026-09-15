`timescale 1ns/1ps
// JTAG debug-port test: drives IEEE 1149.1 TMS/TDI sequences into jtag_tap,
// which sits in front of the SoC's jtag_dbg exactly as BSCANE2 does on the
// board. The BRAM starts holding only "jal x0, 0" (the core spins); the host:
//   1. reads IDCODE
//   2. halts the core and checks the halted flag
//   3. loads prog.hex word by word through the debug bus master, reads it back
//   4. resets the core (still halted), releases reset, then releases halt
//   5. peeks GPIO_IN over JTAG while the program runs
//   6. waits for the program's PASS code on GPIO_OUT (same convention as tb_isa)
module tb_jtag;
    reg clk = 0;
    reg rst_n_pin = 0;
    wire [31:0] led;
    reg  [31:0] sw = 32'h0000_00A5;
    wire uart_tx_pin;
    reg  uart_rx_pin = 1'b1;

    localparam CLKS_PER_BIT = 20;
    localparam CLK_PERIOD   = 10;
    localparam TCK_PERIOD   = 100;    // 10 MHz JTAG
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- JTAG pins ----
    reg  tck = 0, tms = 1, tdi = 0, trst_n = 0;
    wire tdo;
    wire u_sel, u_capture, u_shift, u_update, u_reset, u_tdo;

    jtag_tap u_tap (
        .tck(tck), .tms(tms), .tdi(tdi), .trst_n(trst_n), .tdo(tdo),
        .user_sel(u_sel), .user_capture(u_capture), .user_shift(u_shift),
        .user_update(u_update), .user_reset(u_reset), .user_tdo(u_tdo)
    );

    soc_top #(.CLKS_PER_BIT(CLKS_PER_BIT), .INIT_FILE("")) dut (
        .clk(clk), .rst_n_pin(rst_n_pin), .led(led), .sw(sw),
        .uart_tx_pin(uart_tx_pin), .uart_rx_pin(uart_rx_pin),
        .jtag_tck(tck), .jtag_tdi(tdi), .jtag_tdo(u_tdo), .jtag_sel(u_sel),
        .jtag_capture(u_capture), .jtag_shift(u_shift), .jtag_update(u_update)
    );

    // ---- UART decode (so the loaded program's output is visible) ----
    reg [7:0] rx_byte; integer k;
    initial forever begin
        @(negedge uart_tx_pin);
        #(CLK_PERIOD * CLKS_PER_BIT * 1.5);
        for (k = 0; k < 8; k = k + 1) begin rx_byte[k] = uart_tx_pin; #(CLK_PERIOD * CLKS_PER_BIT); end
        if (rx_byte != 8'h0D) $write("%c", rx_byte);
        $fflush;
    end

    // ================= JTAG bus-functional model =================
    task tck_pulse;            // drive tms/tdi, then one full TCK cycle
        begin #(TCK_PERIOD/2) tck = 1; #(TCK_PERIOD/2) tck = 0; end
    endtask

    task tap_reset;            // five TMS=1 clocks -> Test-Logic-Reset, then Run-Test/Idle
        begin tms = 1; repeat (5) tck_pulse; tms = 0; tck_pulse; end
    endtask

    task shift_ir(input [3:0] ir);
        integer i;
        begin
            tms = 1; tck_pulse;            // Select-DR
            tms = 1; tck_pulse;            // Select-IR
            tms = 0; tck_pulse;            // Capture-IR
            tms = 0; tck_pulse;            // Shift-IR
            for (i = 0; i < 4; i = i + 1) begin
                tdi = ir[i]; tms = (i == 3); tck_pulse;   // last bit exits to Exit1-IR
            end
            tms = 1; tck_pulse;            // Update-IR
            tms = 0; tck_pulse;            // Run-Test/Idle
        end
    endtask

    task shift_dr(input integer n, input [65:0] din, output [65:0] dout);
        integer i;
        begin
            dout = 66'd0;
            tms = 1; tck_pulse;            // Select-DR
            tms = 0; tck_pulse;            // Capture-DR
            tms = 0; tck_pulse;            // Shift-DR (capture happens on this edge)
            for (i = 0; i < n; i = i + 1) begin
                tdi = din[i]; tms = (i == n - 1);
                #(TCK_PERIOD/4) dout[i] = tdo;   // settled after the last falling edge
                tck_pulse;
            end
            tms = 1; tck_pulse;            // Update-DR (request issued here)
            tms = 0; tck_pulse;            // Run-Test/Idle
        end
    endtask

    // ---- debug-register protocol (see rtl/jtag_dbg.v) ----
    localparam [1:0] OP_NOP = 2'd0, OP_READ = 2'd1, OP_WRITE = 2'd2, OP_CTRL = 2'd3;
    reg [65:0] resp;

    task dbg_cmd(input [1:0] op, input [31:0] addr, input [31:0] data);
        begin
            shift_dr(66, {addr, data, op}, resp);
            // poll until the request has completed
            begin : poll
                integer tries;
                for (tries = 0; tries < 100; tries = tries + 1) begin
                    shift_dr(66, {32'd0, 32'd0, OP_NOP}, resp);
                    if (!resp[0]) disable poll;
                end
                $display("FAIL: debug request never completed");
                $finish;
            end
        end
    endtask
    task dbg_write(input [31:0] addr, input [31:0] data); begin dbg_cmd(OP_WRITE, addr, data); end endtask
    task dbg_read(input [31:0] addr, output [31:0] data); begin dbg_cmd(OP_READ, addr, 32'd0); data = resp[33:2]; end endtask
    task dbg_ctrl(input halt, input core_rst); begin dbg_cmd(OP_CTRL, 32'd0, {30'd0, core_rst, halt}); end endtask
    task dbg_status(output halted, output halt_req, output rst_req);
        begin shift_dr(66, {32'd0, 32'd0, OP_NOP}, resp); halted = resp[34]; halt_req = resp[35]; rst_req = resp[36]; end
    endtask

    // ================= test =================
    reg [31:0] prog [0:8191];
    integer nwords, i, errors;
    reg [31:0] rd, id;
    reg [65:0] dr;
    reg halted, hreq, rreq;

    initial begin
        // BRAM: spin loop everywhere so the core does something harmless
        for (i = 0; i < 8192; i = i + 1) dut.u_bram.mem[i] = 32'h0000_006F;
        for (i = 0; i < 8192; i = i + 1) prog[i] = 32'hFFFF_FFFF;
        $readmemh("prog.hex", prog);
        nwords = 0;
        for (i = 0; i < 8192; i = i + 1) if (prog[i] !== 32'hFFFF_FFFF) nwords = i + 1;

        errors = 0;
        repeat (5) @(posedge clk);
        rst_n_pin = 1;
        repeat (50) @(posedge clk);

        // 1. IDCODE
        trst_n = 1; #(TCK_PERIOD);
        tap_reset;
        shift_dr(32, 66'd0, dr);
        id = dr[31:0];
        $display("IDCODE = %08h", id);
        if (id !== 32'h1ABC_5001) begin $display("FAIL: bad IDCODE"); errors = errors + 1; end

        // 2. halt
        shift_ir(4'h2);                                   // USER
        dbg_ctrl(1'b1, 1'b0);
        dbg_status(halted, hreq, rreq);
        $display("halt requested: halted=%b halt_req=%b rst=%b pc=%08h", halted, hreq, rreq, dut.u_core.pc_reg);
        if (!halted) begin $display("FAIL: core did not halt"); errors = errors + 1; end

        // 3. load program and verify
        $display("loading %0d words over JTAG ...", nwords);
        for (i = 0; i < nwords; i = i + 1) dbg_write(i * 4, prog[i]);
        for (i = 0; i < nwords; i = i + 1) begin
            dbg_read(i * 4, rd);
            if (rd !== prog[i]) begin
                $display("FAIL: readback mismatch at %08h: %08h != %08h", i * 4, rd, prog[i]);
                errors = errors + 1;
            end
        end
        $display("readback verified (%0d words)", nwords);

        // 4. reset core (halt still asserted), release reset, then run
        dbg_ctrl(1'b1, 1'b1);
        dbg_ctrl(1'b1, 1'b0);
        dbg_status(halted, hreq, rreq);
        $display("after reset: halted=%b pc=%08h", halted, dut.u_core.pc_reg);
        if (dut.u_core.pc_reg !== 32'd0) begin $display("FAIL: pc not reset"); errors = errors + 1; end
        dbg_ctrl(1'b0, 1'b0);
        $display("core released\n---- program output ----");

        // 5. live peek while the program runs: GPIO_IN must read back the switches
        repeat (2000) @(posedge clk);
        dbg_read(32'h1000_0004, rd);
        $display("\n---- JTAG peek GPIO_IN = %08h (switches = %08h) ----", rd, sw);
        if (rd !== sw) begin $display("FAIL: GPIO_IN peek"); errors = errors + 1; end
        dbg_read(32'h3000_0000, rd);
        $display("---- JTAG peek TIMER_COUNT = %0d ----", rd);
    end

    // 6. wait for the program's PASS code
    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (led == 32'h0000_600D) begin
            if (errors == 0) $display("\nRESULT: PASS (%0d cycles)", cycles);
            else             $display("\nRESULT: FAIL (%0d errors)", errors);
            $finish;
        end else if (cycles >= 2_000_000) begin
            $display("\nRESULT: TIMEOUT led=%08h pc=%08h", led, dut.u_core.pc_reg);
            $finish;
        end
    end
endmodule
