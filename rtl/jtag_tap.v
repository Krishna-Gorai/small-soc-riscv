`timescale 1ns/1ps
// IEEE 1149.1 test access port with a 4-bit instruction register.
//
// Instructions: IDCODE (reset value), BYPASS, USER. USER hands the data
// register to external logic through the same interface Xilinx's BSCANE2
// primitive presents (sel / capture / shift / update / tck / tdi / tdo), so
// jtag_dbg.v can sit behind either this TAP (simulation, or a discrete JTAG
// header) or the FPGA's own JTAG port via BSCANE2 (ZCU104 build).
module jtag_tap #(
    parameter [31:0] IDCODE = 32'h1ABC_5001   // version 1, part 0xABC5, manufacturer 0x001, LSB 1
)(
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    input  wire trst_n,
    output reg  tdo,

    // user data-register interface (BSCANE2-compatible)
    output wire user_sel,       // USER instruction is current
    output wire user_capture,   // Capture-DR
    output wire user_shift,     // Shift-DR
    output wire user_update,    // Update-DR
    output wire user_reset,     // Test-Logic-Reset
    input  wire user_tdo
);
    localparam [3:0] IR_IDCODE = 4'h1, IR_USER = 4'h2, IR_BYPASS = 4'hF;

    localparam [3:0]
        TEST_LOGIC_RESET = 4'd0,  RUN_TEST_IDLE = 4'd1,
        SELECT_DR        = 4'd2,  CAPTURE_DR    = 4'd3,  SHIFT_DR  = 4'd4,  EXIT1_DR  = 4'd5,
        PAUSE_DR         = 4'd6,  EXIT2_DR      = 4'd7,  UPDATE_DR = 4'd8,
        SELECT_IR        = 4'd9,  CAPTURE_IR    = 4'd10, SHIFT_IR  = 4'd11, EXIT1_IR  = 4'd12,
        PAUSE_IR         = 4'd13, EXIT2_IR      = 4'd14, UPDATE_IR = 4'd15;

    reg [3:0] state;
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) state <= TEST_LOGIC_RESET;
        else case (state)
            TEST_LOGIC_RESET: state <= tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_DR:        state <= tms ? SELECT_IR        : CAPTURE_DR;
            CAPTURE_DR:       state <= tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         state <= tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         state <= tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         state <= tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         state <= tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_IR:        state <= tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       state <= tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         state <= tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         state <= tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         state <= tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         state <= tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
        endcase
    end

    // ---- instruction register ----
    reg [3:0] ir_shift, ir;
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir <= IR_IDCODE; ir_shift <= 4'b0001;
        end else begin
            if (state == TEST_LOGIC_RESET) ir <= IR_IDCODE;
            if (state == CAPTURE_IR)       ir_shift <= 4'b0001;        // 1149.1: LSBs = 01
            else if (state == SHIFT_IR)    ir_shift <= {tdi, ir_shift[3:1]};
            else if (state == UPDATE_IR)   ir <= ir_shift;
        end
    end

    // ---- IDCODE and BYPASS data registers ----
    reg [31:0] idcode_shift;
    reg        bypass;
    always @(posedge tck) begin
        if (state == CAPTURE_DR) begin
            idcode_shift <= IDCODE;
            bypass       <= 1'b0;
        end else if (state == SHIFT_DR) begin
            idcode_shift <= {tdi, idcode_shift[31:1]};
            bypass       <= tdi;
        end
    end

    // ---- user register hand-off ----
    assign user_sel     = (ir == IR_USER);
    assign user_capture = (state == CAPTURE_DR);
    assign user_shift   = (state == SHIFT_DR);
    assign user_update  = (state == UPDATE_DR);
    assign user_reset   = (state == TEST_LOGIC_RESET);

    // TDO changes on the falling edge of TCK
    always @(negedge tck) begin
        if (state == SHIFT_IR)      tdo <= ir_shift[0];
        else case (ir)
            IR_IDCODE: tdo <= idcode_shift[0];
            IR_USER:   tdo <= user_tdo;
            default:   tdo <= bypass;
        endcase
    end
endmodule
