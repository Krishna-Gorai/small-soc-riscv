`timescale 1ns/1ps
// JTAG debug / load port for Small_SoC.
//
// Sits behind a TAP's USER data register (jtag_tap.v in simulation, Xilinx
// BSCANE2 on the FPGA) and gives the host three things: halt / resume / reset
// of the core, and read / write access to every address on the SoC bus through
// its own AXI-Lite master. A program can therefore be loaded into the BRAM
// and started without rebuilding the bitstream.
//
// Data register, 66 bits, shifted LSB first:
//
//   shift in   [1:0] op      0 = nop (poll), 1 = read, 2 = write, 3 = control
//              [33:2] data   write data / control bits {bit1 core_reset, bit0 halt}
//              [65:34] addr  bus address (read / write)
//
//   shift out  [0]    busy   a request is still in flight; poll again
//              [1]    0
//              [33:2] rdata  data returned by the last completed read
//              [34]   halted core is stopped at an instruction boundary
//              [35]   halt   halt request currently asserted
//              [36]   reset  core reset currently asserted
//              [65:37] 0
//
// A request is issued on Update-DR; the host then polls with op = nop until
// busy is clear. The two clock domains (TCK, clk) are decoupled with toggle
// synchronisers; the payload registers are only read on the far side after
// the toggle has crossed, so they are stable when sampled.
module jtag_dbg (
    // ---- TAP side (BSCANE2-compatible), TCK domain ----
    input  wire        tck,
    input  wire        tdi,
    output wire        tdo,
    input  wire        sel,
    input  wire        capture,
    input  wire        shift,
    input  wire        update,

    // ---- SoC side ----
    input  wire        clk,
    input  wire        rst_n,
    output reg         dbg_halt_req,
    output reg         dbg_core_rst,
    input  wire        dbg_halted,

    // AXI-Lite master
    output reg  [31:0] m_axi_araddr,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,
    output reg  [31:0] m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready
);
    localparam DR_W = 66;
    localparam [1:0] OP_NOP = 2'd0, OP_READ = 2'd1, OP_WRITE = 2'd2, OP_CTRL = 2'd3;

    // clk-domain state referenced from the TCK domain (declared first)
    reg        ack_toggle;
    reg [31:0] rdata_q;                        // last read data, stable while !busy
    reg        halted_q;

    // ================= TCK domain =================
    reg [DR_W-1:0] dr;
    reg [1:0]  req_op;
    reg [31:0] req_addr, req_data;
    reg        req_toggle;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;   // ack toggle, synchronised into TCK
    wire       busy = (req_toggle != ack_sync[1]);

    always @(posedge tck or negedge rst_n) begin
        if (!rst_n) begin
            dr <= {DR_W{1'b0}}; req_op <= OP_NOP; req_addr <= 32'd0; req_data <= 32'd0;
            req_toggle <= 1'b0; ack_sync <= 2'b00;
        end else begin
            ack_sync <= {ack_sync[0], ack_toggle};
            if (sel && capture)
                dr <= {29'd0, dbg_core_rst, dbg_halt_req, halted_q, rdata_q, 1'b0, busy};
            else if (sel && shift)
                dr <= {tdi, dr[DR_W-1:1]};
            else if (sel && update && !busy && dr[1:0] != OP_NOP) begin
                req_op     <= dr[1:0];
                req_data   <= dr[33:2];
                req_addr   <= dr[65:34];
                req_toggle <= ~req_toggle;
            end
        end
    end
    assign tdo = dr[0];

    // ================= clk domain =================
    (* ASYNC_REG = "TRUE" *) reg [2:0] req_sync;
    wire req_edge = req_sync[2] ^ req_sync[1];

    localparam [2:0] S_IDLE = 3'd0, S_RD_ADDR = 3'd1, S_RD_DATA = 3'd2,
                     S_WR_ADDR = 3'd3, S_WR_RESP = 3'd4, S_DONE = 3'd5;
    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_sync <= 3'b000; ack_toggle <= 1'b0; state <= S_IDLE;
            dbg_halt_req <= 1'b0; dbg_core_rst <= 1'b0; rdata_q <= 32'd0; halted_q <= 1'b0;
            m_axi_arvalid <= 1'b0; m_axi_rready <= 1'b0; m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0; m_axi_bready <= 1'b0;
            m_axi_araddr <= 32'd0; m_axi_awaddr <= 32'd0; m_axi_wdata <= 32'd0; m_axi_wstrb <= 4'd0;
        end else begin
            req_sync <= {req_sync[1:0], req_toggle};
            halted_q <= dbg_halted;

            case (state)
            S_IDLE: if (req_edge) begin
                case (req_op)
                    OP_READ: begin
                        m_axi_araddr <= req_addr; m_axi_arvalid <= 1'b1; state <= S_RD_ADDR;
                    end
                    OP_WRITE: begin
                        m_axi_awaddr <= req_addr; m_axi_awvalid <= 1'b1;
                        m_axi_wdata  <= req_data; m_axi_wstrb <= 4'hF; m_axi_wvalid <= 1'b1;
                        state <= S_WR_ADDR;
                    end
                    OP_CTRL: begin
                        dbg_halt_req <= req_data[0];
                        dbg_core_rst <= req_data[1];
                        state <= S_DONE;
                    end
                    default: state <= S_DONE;
                endcase
            end

            S_RD_ADDR: if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arvalid <= 1'b0; m_axi_rready <= 1'b1; state <= S_RD_DATA;
            end
            S_RD_DATA: if (m_axi_rvalid && m_axi_rready) begin
                rdata_q <= m_axi_rdata; m_axi_rready <= 1'b0; state <= S_DONE;
            end

            S_WR_ADDR: begin
                if (m_axi_awvalid && m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_wvalid  && m_axi_wready)  m_axi_wvalid  <= 1'b0;
                if ((!m_axi_awvalid || m_axi_awready) && (!m_axi_wvalid || m_axi_wready)) begin
                    m_axi_bready <= 1'b1; state <= S_WR_RESP;
                end
            end
            S_WR_RESP: if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bready <= 1'b0; state <= S_DONE;
            end

            S_DONE: begin
                ack_toggle <= ~ack_toggle;
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
