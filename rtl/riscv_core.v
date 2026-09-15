`timescale 1ns/1ps
module riscv_core #(
    parameter RESET_ADDR = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq_timer,   // machine timer interrupt (level)

    // AXI-Lite master (shared for fetch and data access)
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

    // ---------------- Opcodes ----------------
    localparam OP_RTYPE  = 7'b0110011;
    localparam OP_ITYPE  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_SYSTEM = 7'b1110011;   // CSR ops, ECALL, EBREAK, MRET, WFI
    localparam OP_FENCE  = 7'b0001111;   // FENCE / FENCE.I: no-ops on this core

    // CSR addresses
    localparam CSR_MSTATUS   = 12'h300;
    localparam CSR_MISA      = 12'h301;
    localparam CSR_MIE       = 12'h304;
    localparam CSR_MTVEC     = 12'h305;
    localparam CSR_MSCRATCH  = 12'h340;
    localparam CSR_MEPC      = 12'h341;
    localparam CSR_MCAUSE    = 12'h342;
    localparam CSR_MTVAL     = 12'h343;
    localparam CSR_MIP       = 12'h344;
    localparam CSR_MCYCLE    = 12'hB00;
    localparam CSR_MINSTRET  = 12'hB02;
    localparam CSR_MCYCLEH   = 12'hB80;
    localparam CSR_MINSTRETH = 12'hB82;
    localparam CSR_CYCLE     = 12'hC00;
    localparam CSR_INSTRET   = 12'hC02;
    localparam CSR_CYCLEH    = 12'hC80;
    localparam CSR_INSTRETH  = 12'hC82;
    localparam CSR_MVENDORID = 12'hF11;
    localparam CSR_MARCHID   = 12'hF12;
    localparam CSR_MIMPID    = 12'hF13;
    localparam CSR_MHARTID   = 12'hF14;

    // ---------------- FSM states ----------------
    localparam S_IF_ADDR  = 3'd0;
    localparam S_IF_DATA  = 3'd1;
    localparam S_EXEC     = 3'd2;
    localparam S_MEM_ADDR = 3'd3;
    localparam S_MEM_DATA = 3'd4;
    localparam S_WB       = 3'd5;

    reg [2:0]  state;
    reg [31:0] pc_reg;
    reg [31:0] instr_reg;
    reg [31:0] mem_addr_reg;
    reg [31:0] mem_rdata_reg;
    reg        mem_is_load_r;
    reg        aw_done, w_done;

    // ---------------- Instruction fields ----------------
    wire [6:0] opcode = instr_reg[6:0];
    wire [4:0] rd     = instr_reg[11:7];
    wire [2:0] funct3 = instr_reg[14:12];
    wire [4:0] rs1    = instr_reg[19:15];
    wire [4:0] rs2    = instr_reg[24:20];
    wire [6:0] funct7 = instr_reg[31:25];

    wire [31:0] imm_i = {{20{instr_reg[31]}}, instr_reg[31:20]};
    wire [31:0] imm_s = {{20{instr_reg[31]}}, instr_reg[31:25], instr_reg[11:7]};
    wire [31:0] imm_b = {{19{instr_reg[31]}}, instr_reg[31], instr_reg[7],
                          instr_reg[30:25], instr_reg[11:8], 1'b0};
    wire [31:0] imm_u = {instr_reg[31:12], 12'd0};
    wire [31:0] imm_j = {{11{instr_reg[31]}}, instr_reg[31], instr_reg[19:12],
                          instr_reg[20], instr_reg[30:21], 1'b0};

    wire is_rtype  = (opcode == OP_RTYPE);
    wire is_itype  = (opcode == OP_ITYPE);
    wire is_load   = (opcode == OP_LOAD);
    wire is_store  = (opcode == OP_STORE);
    wire is_branch = (opcode == OP_BRANCH);
    wire is_jal    = (opcode == OP_JAL);
    wire is_jalr   = (opcode == OP_JALR);
    wire is_lui    = (opcode == OP_LUI);
    wire is_auipc  = (opcode == OP_AUIPC);
    wire is_system = (opcode == OP_SYSTEM);
    wire is_csr    = is_system && (funct3 != 3'b000);
    wire is_ecall  = is_system && (funct3 == 3'b000) && (instr_reg[31:20] == 12'h000);
    wire is_ebreak = is_system && (funct3 == 3'b000) && (instr_reg[31:20] == 12'h001);
    wire is_mret   = is_system && (funct3 == 3'b000) && (instr_reg[31:20] == 12'h302);
    // WFI (12'h105) and FENCE are executed as no-ops.

    // ---------------- Register file ----------------
    wire [31:0] rs1_data, rs2_data;
    reg  [4:0]  rd_waddr;
    reg  [31:0] rd_wdata;
    reg         rd_we;

    regfile u_regfile (
        .clk(clk), .rs1_addr(rs1), .rs2_addr(rs2),
        .rd_addr(rd_waddr), .rd_data(rd_wdata), .rd_we(rd_we),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // ---------------- ALU op decode ----------------
    reg [3:0] alu_op;
    always @(*) begin
        case (opcode)
            OP_RTYPE: begin
                case ({funct7[5], funct3})
                    4'b0_000: alu_op = 4'b0000; // ADD
                    4'b1_000: alu_op = 4'b0001; // SUB
                    4'b0_001: alu_op = 4'b0101; // SLL
                    4'b0_010: alu_op = 4'b1000; // SLT
                    4'b0_011: alu_op = 4'b1001; // SLTU
                    4'b0_100: alu_op = 4'b0100; // XOR
                    4'b0_101: alu_op = 4'b0110; // SRL
                    4'b1_101: alu_op = 4'b0111; // SRA
                    4'b0_110: alu_op = 4'b0011; // OR
                    4'b0_111: alu_op = 4'b0010; // AND
                    default:  alu_op = 4'b0000;
                endcase
            end
            OP_ITYPE: begin
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI
                    3'b010: alu_op = 4'b1000; // SLTI
                    3'b011: alu_op = 4'b1001; // SLTIU
                    3'b100: alu_op = 4'b0100; // XORI
                    3'b110: alu_op = 4'b0011; // ORI
                    3'b111: alu_op = 4'b0010; // ANDI
                    3'b001: alu_op = 4'b0101; // SLLI
                    3'b101: alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRAI/SRLI
                    default: alu_op = 4'b0000;
                endcase
            end
            OP_LUI:  alu_op = 4'b1010; // pass-through b
            default: alu_op = 4'b0000; // loads/stores/jalr/auipc -> ADD
        endcase
    end

    wire [31:0] alu_a = (is_auipc || is_jal) ? pc_reg :
                         (is_lui)            ? 32'd0  : rs1_data;

    wire [31:0] alu_b = (is_rtype)           ? rs2_data :
                         (is_itype)          ? imm_i    :
                         (is_load || is_jalr)? imm_i    :
                         (is_store)          ? imm_s    :
                         (is_lui || is_auipc)? imm_u    : 32'd0;

    wire [31:0] alu_result;
    wire        alu_zero;
    alu u_alu (.a(alu_a), .b(alu_b), .alu_op(alu_op),
               .result(alu_result), .zero(alu_zero));

    // ---------------- Branch condition ----------------
    reg btaken_r;
    always @(*) begin
        case (funct3)
            3'b000: btaken_r = (rs1_data == rs2_data);
            3'b001: btaken_r = (rs1_data != rs2_data);
            3'b100: btaken_r = ($signed(rs1_data) <  $signed(rs2_data));
            3'b101: btaken_r = ($signed(rs1_data) >= $signed(rs2_data));
            3'b110: btaken_r = (rs1_data <  rs2_data);
            3'b111: btaken_r = (rs1_data >= rs2_data);
            default: btaken_r = 1'b0;
        endcase
    end
    wire branch_taken = is_branch && btaken_r;

    wire [31:0] pc_plus4   = pc_reg + 32'd4;
    wire [31:0] branch_tgt = pc_reg + imm_b;
    wire [31:0] jal_tgt    = pc_reg + imm_j;
    wire [31:0] jalr_tgt   = (rs1_data + imm_i) & ~32'h1;

    wire [31:0] pc_next = is_jal       ? jal_tgt    :
                          is_jalr      ? jalr_tgt   :
                          branch_taken ? branch_tgt : pc_plus4;

    // ---------------- Machine-mode CSRs ----------------
    reg        mstatus_mie, mstatus_mpie;
    reg        mie_mtie;
    reg [31:0] mtvec, mscratch, mepc, mcause;
    reg [63:0] mcycle, minstret;

    wire [11:0] csr_addr  = instr_reg[31:20];
    wire [31:0] csr_wmask = funct3[2] ? {27'd0, rs1} : rs1_data;   // immediate or register form
    reg  [31:0] csr_rdata;
    always @(*) begin
        case (csr_addr)
            CSR_MSTATUS:   csr_rdata = {24'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
            CSR_MISA:      csr_rdata = 32'h4000_0100;              // RV32I
            CSR_MIE:       csr_rdata = {24'd0, mie_mtie, 7'd0};
            CSR_MTVEC:     csr_rdata = mtvec;
            CSR_MSCRATCH:  csr_rdata = mscratch;
            CSR_MEPC:      csr_rdata = mepc;
            CSR_MCAUSE:    csr_rdata = mcause;
            CSR_MIP:       csr_rdata = {24'd0, irq_timer, 7'd0};
            CSR_MCYCLE,    CSR_CYCLE:    csr_rdata = mcycle[31:0];
            CSR_MCYCLEH,   CSR_CYCLEH:   csr_rdata = mcycle[63:32];
            CSR_MINSTRET,  CSR_INSTRET:  csr_rdata = minstret[31:0];
            CSR_MINSTRETH, CSR_INSTRETH: csr_rdata = minstret[63:32];
            default:       csr_rdata = 32'd0;   // mtval, mvendorid, marchid, mimpid, mhartid ...
        endcase
    end
    // CSRRW writes the operand; CSRRS/CSRRC set/clear bits. The *I forms use
    // the 5-bit immediate. A CSRRS/CSRRC with rs1 = x0 is a pure read.
    wire        csr_we    = is_csr && !((funct3[1:0] != 2'b01) && (rs1 == 5'd0));
    wire [31:0] csr_wdata = (funct3[1:0] == 2'b01) ? csr_wmask :
                            (funct3[1:0] == 2'b10) ? (csr_rdata |  csr_wmask) :
                                                     (csr_rdata & ~csr_wmask);

    // Interrupt: taken at the next instruction boundary when globally enabled.
    wire irq_take = mstatus_mie && mie_mtie && irq_timer;

    // ---------------- Load alignment ----------------
    reg [31:0] load_data_aligned;
    always @(*) begin
        case (funct3)
            3'b000: case (mem_addr_reg[1:0]) // LB
                2'b00: load_data_aligned = {{24{mem_rdata_reg[7]}},  mem_rdata_reg[7:0]};
                2'b01: load_data_aligned = {{24{mem_rdata_reg[15]}}, mem_rdata_reg[15:8]};
                2'b10: load_data_aligned = {{24{mem_rdata_reg[23]}}, mem_rdata_reg[23:16]};
                2'b11: load_data_aligned = {{24{mem_rdata_reg[31]}}, mem_rdata_reg[31:24]};
            endcase
            3'b100: case (mem_addr_reg[1:0]) // LBU
                2'b00: load_data_aligned = {24'd0, mem_rdata_reg[7:0]};
                2'b01: load_data_aligned = {24'd0, mem_rdata_reg[15:8]};
                2'b10: load_data_aligned = {24'd0, mem_rdata_reg[23:16]};
                2'b11: load_data_aligned = {24'd0, mem_rdata_reg[31:24]};
            endcase
            3'b001: load_data_aligned = mem_addr_reg[1] ? // LH
                {{16{mem_rdata_reg[31]}}, mem_rdata_reg[31:16]} :
                {{16{mem_rdata_reg[15]}}, mem_rdata_reg[15:0]};
            3'b101: load_data_aligned = mem_addr_reg[1] ? // LHU
                {16'd0, mem_rdata_reg[31:16]} : {16'd0, mem_rdata_reg[15:0]};
            3'b010: load_data_aligned = mem_rdata_reg; // LW
            default: load_data_aligned = mem_rdata_reg;
        endcase
    end

    wire [31:0] wb_data = is_load             ? load_data_aligned :
                          (is_jal || is_jalr) ? pc_plus4          :
                          is_csr              ? csr_rdata         : alu_result;

    // ---------------- Store data/strobe ----------------
    reg [31:0] store_wdata;
    reg [3:0]  store_wstrb;
    always @(*) begin
        case (funct3)
            3'b000: case (mem_addr_reg[1:0]) // SB
                2'b00: begin store_wdata = {24'd0, rs2_data[7:0]};       store_wstrb = 4'b0001; end
                2'b01: begin store_wdata = {16'd0, rs2_data[7:0], 8'd0}; store_wstrb = 4'b0010; end
                2'b10: begin store_wdata = {8'd0, rs2_data[7:0], 16'd0}; store_wstrb = 4'b0100; end
                2'b11: begin store_wdata = {rs2_data[7:0], 24'd0};       store_wstrb = 4'b1000; end
            endcase
            3'b001: if (mem_addr_reg[1]) begin // SH
                store_wdata = {rs2_data[15:0], 16'd0}; store_wstrb = 4'b1100;
            end else begin
                store_wdata = {16'd0, rs2_data[15:0]}; store_wstrb = 4'b0011;
            end
            3'b010: begin store_wdata = rs2_data; store_wstrb = 4'b1111; end // SW
            default: begin store_wdata = rs2_data; store_wstrb = 4'b1111; end
        endcase
    end

    // ---------------- Main FSM ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IF_ADDR;
            pc_reg        <= RESET_ADDR;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            rd_we         <= 1'b0;
            instr_reg     <= 32'd0;
            m_axi_araddr  <= 32'd0;
            m_axi_awaddr  <= 32'd0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            mem_addr_reg  <= 32'd0;
            mem_rdata_reg <= 32'd0;
            mem_is_load_r <= 1'b0;
            rd_waddr      <= 5'd0;
            rd_wdata      <= 32'd0;
            mstatus_mie   <= 1'b0;
            mstatus_mpie  <= 1'b0;
            mie_mtie      <= 1'b0;
            mtvec         <= 32'd0;
            mscratch      <= 32'd0;
            mepc          <= 32'd0;
            mcause        <= 32'd0;
            mcycle        <= 64'd0;
            minstret      <= 64'd0;
        end else begin
            rd_we  <= 1'b0; // default; only pulsed high in S_WB
            mcycle <= mcycle + 64'd1;

            case (state)

            S_IF_ADDR: begin
                m_axi_araddr  <= pc_reg;
                m_axi_arvalid <= 1'b1;
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b1;
                    state         <= S_IF_DATA;
                end
            end

            S_IF_DATA: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    instr_reg    <= m_axi_rdata;
                    m_axi_rready <= 1'b0;
                    state        <= S_EXEC;
                end
            end

            S_EXEC: begin
                if (is_load || is_store) begin
                    mem_addr_reg  <= alu_result; // rs1 + imm
                    mem_is_load_r <= is_load;
                    state         <= S_MEM_ADDR;
                end else begin
                    state <= S_WB;
                end
            end

            S_MEM_ADDR: begin
                if (mem_is_load_r) begin
                    m_axi_araddr  <= mem_addr_reg;
                    m_axi_arvalid <= 1'b1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_MEM_DATA;
                    end
                end else begin
                    // AW and W channels can complete independently in AXI-Lite
                    m_axi_awaddr <= mem_addr_reg;
                    m_axi_wdata  <= store_wdata;
                    m_axi_wstrb  <= store_wstrb;
                    if (!aw_done) m_axi_awvalid <= 1'b1;
                    if (!w_done)  m_axi_wvalid  <= 1'b1;

                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_done       <= 1'b1;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        aw_done      <= 1'b0;
                        w_done       <= 1'b0;
                        state        <= S_MEM_DATA;
                    end
                end
            end

            S_MEM_DATA: begin
                if (mem_is_load_r) begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        mem_rdata_reg <= m_axi_rdata;
                        m_axi_rready  <= 1'b0;
                        state         <= S_WB;
                    end
                end else begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        state        <= S_WB;
                    end
                end
            end

            S_WB: begin
                minstret <= minstret + 64'd1;
                if (!is_store && !is_branch && !(is_system && !is_csr) && opcode != OP_FENCE) begin
                    rd_waddr <= rd;
                    rd_wdata <= wb_data;
                    rd_we    <= 1'b1;
                end
                if (csr_we) begin
                    case (csr_addr)
                        CSR_MSTATUS:  begin mstatus_mie <= csr_wdata[3]; mstatus_mpie <= csr_wdata[7]; end
                        CSR_MIE:      mie_mtie <= csr_wdata[7];
                        CSR_MTVEC:    mtvec    <= {csr_wdata[31:2], 2'b00};   // direct mode only
                        CSR_MSCRATCH: mscratch <= csr_wdata;
                        CSR_MEPC:     mepc     <= {csr_wdata[31:2], 2'b00};
                        CSR_MCAUSE:   mcause   <= csr_wdata;
                        default: ;
                    endcase
                end

                // Next PC: synchronous trap > mret > interrupt > normal flow.
                if (is_ecall || is_ebreak) begin
                    mepc         <= pc_reg;
                    mcause       <= is_ecall ? 32'd11 : 32'd3;   // env call / breakpoint from M-mode
                    mstatus_mpie <= mstatus_mie;
                    mstatus_mie  <= 1'b0;
                    pc_reg       <= mtvec;
                end else if (is_mret) begin
                    mstatus_mie  <= mstatus_mpie;
                    mstatus_mpie <= 1'b1;
                    pc_reg       <= mepc;
                end else if (irq_take) begin
                    mepc         <= pc_next;                      // resume at the next instruction
                    mcause       <= 32'h8000_0007;                // machine timer interrupt
                    mstatus_mpie <= mstatus_mie;
                    mstatus_mie  <= 1'b0;
                    pc_reg       <= mtvec;
                end else begin
                    pc_reg <= pc_next;
                end
                state <= S_IF_ADDR;
            end

            default: state <= S_IF_ADDR;
            endcase
        end
    end

endmodule