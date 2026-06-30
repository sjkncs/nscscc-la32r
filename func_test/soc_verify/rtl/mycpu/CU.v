`timescale 1ns / 1ps

`include "mycpu_inst.vh"
`include "defines.vh"

module CU (
    input  wire [31:15] inst_31_15,
    output wire [ 1: 0] npc_op    ,
    output wire         is_br_jmp ,
    output wire [ 2: 0] ext_op    ,
    output wire         r2_sel    ,
    output wire         rR1_re    ,
    output wire         rR2_re    ,
    output wire         alua_sel  ,
    output wire         alub_sel  ,
    output wire [ 4: 0] alu_op    ,
    output wire [ 2: 0] ram_ext_op,
    output wire [ 3: 0] ram_we    ,
    output wire         rf_we     ,
    output wire         wr_sel    ,
    output wire [ 1: 0] wd_sel    
);

    // =====================================================================
    // Instruction Decoding (LA32R encoding)
    // =====================================================================
    // 3R-type: inst[31:15] = 17-bit opcode
    wire ADD_W     = (inst_31_15[31:15] == 17'h00020);
    wire SUB_W     = (inst_31_15[31:15] == 17'h00022);
    wire SLT       = (inst_31_15[31:15] == 17'h00024);
    wire SLTU      = (inst_31_15[31:15] == 17'h00025);
    wire AND_      = (inst_31_15[31:15] == 17'h00029);
    wire OR_       = (inst_31_15[31:15] == 17'h0002A);
    wire XOR_      = (inst_31_15[31:15] == 17'h0002B);
    wire NOR_      = (inst_31_15[31:15] == 17'h00028);
    wire SLL_W     = (inst_31_15[31:15] == 17'h0002E);
    wire SRL_W     = (inst_31_15[31:15] == 17'h0002F);
    wire SRA_W     = (inst_31_15[31:15] == 17'h00030);
    wire MUL_W     = (inst_31_15[31:15] == 17'h00038);
    wire MULH_W    = (inst_31_15[31:15] == 17'h00039);
    wire MULH_WU   = (inst_31_15[31:15] == 17'h0003A);
    wire DIV_W     = (inst_31_15[31:15] == 17'h00040);
    wire DIV_WU    = (inst_31_15[31:15] == 17'h00042);
    wire MOD_W     = (inst_31_15[31:15] == 17'h00041);
    wire MOD_WU    = (inst_31_15[31:15] == 17'h00043);

    // 2RI5-type: inst[31:15] = 17-bit opcode (shift immediate)
    wire SLLI_W    = (inst_31_15[31:15] == 17'h00081);
    wire SRLI_W    = (inst_31_15[31:15] == 17'h00089);
    wire SRAI_W    = (inst_31_15[31:15] == 17'h00091);

    // 2RI12-type: inst[31:22] = 10-bit opcode
    wire ADDI_W    = (inst_31_15[31:22] == 10'h00A);
    wire SLTI      = (inst_31_15[31:22] == 10'h008);
    wire SLTUI     = (inst_31_15[31:22] == 10'h009);
    wire ANDI      = (inst_31_15[31:22] == 10'h00D);
    wire ORI       = (inst_31_15[31:22] == 10'h00E);
    wire XORI      = (inst_31_15[31:22] == 10'h00F);

    // Load: inst[31:22] = 10-bit opcode
    wire LD_W      = (inst_31_15[31:22] == 10'h0A2);
    wire LD_B      = (inst_31_15[31:22] == 10'h0A0);
    wire LD_H      = (inst_31_15[31:22] == 10'h0A1);
    wire LD_BU     = (inst_31_15[31:22] == 10'h0A8);
    wire LD_HU     = (inst_31_15[31:22] == 10'h0A9);

    // Store: inst[31:22] = 10-bit opcode
    wire ST_W      = (inst_31_15[31:22] == 10'h0A6);
    wire ST_B      = (inst_31_15[31:22] == 10'h0A4);
    wire ST_H      = (inst_31_15[31:22] == 10'h0A5);

    // 1RI20-type: inst[31:25] = 7-bit opcode
    wire LU12I_W   = (inst_31_15[31:25] == 7'h0A);
    wire PCADDU12I = (inst_31_15[31:25] == 7'h0E);

    // Branch: inst[31:26] = 6-bit opcode
    wire BEQ       = (inst_31_15[31:26] == 6'h16);
    wire BNE       = (inst_31_15[31:26] == 6'h17);
    wire BLT       = (inst_31_15[31:26] == 6'h18);
    wire BGE       = (inst_31_15[31:26] == 6'h19);
    wire BLTU      = (inst_31_15[31:26] == 6'h1A);
    wire BGEU      = (inst_31_15[31:26] == 6'h1B);

    // Jump: inst[31:26] = 6-bit opcode
    wire B_        = (inst_31_15[31:26] == 6'h14);
    wire BL        = (inst_31_15[31:26] == 6'h15);
    wire JIRL      = (inst_31_15[31:26] == 6'h13);

    // =====================================================================
    // Instruction Groups
    // =====================================================================
    wire TYPE_3R    = ADD_W | SUB_W | SLT | SLTU | AND_ | OR_ | XOR_ | NOR_
                    | SLL_W | SRL_W | SRA_W
                    | MUL_W | MULH_W | MULH_WU | DIV_W | DIV_WU | MOD_W | MOD_WU;
    wire TYPE_2RI5  = SLLI_W | SRLI_W | SRAI_W;
    wire TYPE_2RI12 = ADDI_W | SLTI | SLTUI | ANDI | ORI | XORI;
    wire TYPE_1RI20 = LU12I_W | PCADDU12I;
    wire LOAD       = LD_W | LD_B | LD_H | LD_BU | LD_HU;
    wire STORE      = ST_W | ST_B | ST_H;
    wire BRANCH     = BEQ | BNE | BLT | BGE | BLTU | BGEU;
    wire JUMP       = B_ | BL | JIRL;

    // =====================================================================
    // NPC Operation
    // =====================================================================
    wire NPC_OP_PC4  = TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | TYPE_1RI20 | LOAD | STORE;
    wire NPC_OP_BR   = BRANCH;
    wire NPC_OP_JIRL = JIRL;
    wire NPC_OP_B    = B_ | BL;

    assign npc_op = {2{NPC_OP_PC4 }} & `NPC_PC4  |
                    {2{NPC_OP_BR  }} & `NPC_BR   |
                    {2{NPC_OP_JIRL}} & `NPC_JIRL |
                    {2{NPC_OP_B   }} & `NPC_B    ;

    // =====================================================================
    // Branch/Jump flag
    // =====================================================================
    assign is_br_jmp = BRANCH | JUMP;

    // =====================================================================
    // Immediate Extension Type
    // =====================================================================
    wire EXT_OP_5   = TYPE_2RI5;
    wire EXT_OP_12  = ADDI_W | SLTI | SLTUI | LOAD | STORE;
    wire EXT_OP_12U = ANDI | ORI | XORI;
    wire EXT_OP_16  = BRANCH | JIRL;
    wire EXT_OP_20  = TYPE_1RI20;
    wire EXT_OP_26  = B_ | BL;

    assign ext_op = {3{EXT_OP_5  }} & `EXT_5   |
                    {3{EXT_OP_12 }} & `EXT_12  |
                    {3{EXT_OP_12U}} & `EXT_12U |
                    {3{EXT_OP_16 }} & `EXT_16  |
                    {3{EXT_OP_20 }} & `EXT_20  |
                    {3{EXT_OP_26 }} & `EXT_26  ;

    // =====================================================================
    // Source Register 2 Selection (rk field vs rd field)
    // =====================================================================
    assign r2_sel = (STORE | BRANCH) ? `R2_RD : `R2_RK;

    // =====================================================================
    // Register Read Enable
    // =====================================================================
    assign rR1_re = !(TYPE_1RI20 | B_ | BL);

    assign rR2_re = TYPE_3R | STORE | BRANCH;

    // =====================================================================
    // ALU Operand A Selection
    // =====================================================================
    assign alua_sel = (PCADDU12I | B_ | BL) ? `ALUA_PC : `ALUA_R1;

    // =====================================================================
    // ALU Operand B Selection
    // =====================================================================
    assign alub_sel = (TYPE_3R | BRANCH) ? `ALUB_R2 : `ALUB_EXT;

    // =====================================================================
    // ALU Operation
    // =====================================================================
    wire ALU_OP_ADD   = ADD_W | ADDI_W | PCADDU12I | LOAD | STORE | JIRL | B_ | BL;
    wire ALU_OP_SUB   = SUB_W | BEQ;
    wire ALU_OP_SUNE  = BNE;
    wire ALU_OP_SLT   = SLT | SLTI | BLT;
    wire ALU_OP_SGE   = BGE;
    wire ALU_OP_SLTU  = SLTU | SLTUI | BLTU;
    wire ALU_OP_SGEU  = BGEU;
    wire ALU_OP_AND   = AND_ | ANDI;
    wire ALU_OP_OR    = OR_ | ORI;
    wire ALU_OP_XOR   = XOR_ | XORI;
    wire ALU_OP_NOR   = NOR_;
    wire ALU_OP_SLL   = SLL_W | SLLI_W;
    wire ALU_OP_SRL   = SRL_W | SRLI_W;
    wire ALU_OP_SRA   = SRA_W | SRAI_W;
    wire ALU_OP_MUL   = MUL_W;
    wire ALU_OP_MULH  = MULH_W;
    wire ALU_OP_MULHU = MULH_WU;
    wire ALU_OP_DIV   = DIV_W;
    wire ALU_OP_DIVU  = DIV_WU;
    wire ALU_OP_MOD   = MOD_W;
    wire ALU_OP_MODU  = MOD_WU;
    wire ALU_OP_LU12I = LU12I_W;

    assign alu_op = {5{ALU_OP_ADD  }} & `ALU_ADD   |
                    {5{ALU_OP_SUB  }} & `ALU_SUB   |
                    {5{ALU_OP_SUNE }} & `ALU_SUNE  |
                    {5{ALU_OP_SLT  }} & `ALU_SLT   |
                    {5{ALU_OP_SGE  }} & `ALU_SGE   |
                    {5{ALU_OP_SLTU }} & `ALU_SLTU  |
                    {5{ALU_OP_SGEU }} & `ALU_SGEU  |
                    {5{ALU_OP_AND  }} & `ALU_AND   |
                    {5{ALU_OP_OR   }} & `ALU_OR    |
                    {5{ALU_OP_XOR  }} & `ALU_XOR   |
                    {5{ALU_OP_NOR  }} & `ALU_NOR   |
                    {5{ALU_OP_SLL  }} & `ALU_SLL   |
                    {5{ALU_OP_SRL  }} & `ALU_SRL   |
                    {5{ALU_OP_SRA  }} & `ALU_SRA   |
                    {5{ALU_OP_MUL  }} & `ALU_MUL   |
                    {5{ALU_OP_MULH }} & `ALU_MULH  |
                    {5{ALU_OP_MULHU}} & `ALU_MULHU |
                    {5{ALU_OP_DIV  }} & `ALU_DIV   |
                    {5{ALU_OP_DIVU }} & `ALU_DIVU  |
                    {5{ALU_OP_MOD  }} & `ALU_MOD   |
                    {5{ALU_OP_MODU }} & `ALU_MODU  |
                    {5{ALU_OP_LU12I}} & `ALU_LU12I ;

    // =====================================================================
    // RAM Read Extension Type
    // =====================================================================
    assign ram_ext_op = {3{LD_W }} & `RAM_EXT_W  |
                        {3{LD_B }} & `RAM_EXT_B  |
                        {3{LD_H }} & `RAM_EXT_H  |
                        {3{LD_BU}} & `RAM_EXT_BU |
                        {3{LD_HU}} & `RAM_EXT_HU ;

    // =====================================================================
    // RAM Write Enable
    // =====================================================================
    assign ram_we = {4{ST_W}} & `RAM_WE_W |
                    {4{ST_H}} & `RAM_WE_H |
                    {4{ST_B}} & `RAM_WE_B ;

    // =====================================================================
    // Register File Write Enable
    // =====================================================================
    assign rf_we = TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | TYPE_1RI20 | LOAD | BL | JIRL;

    // =====================================================================
    // Write-back Register Selection
    // =====================================================================
    assign wr_sel = BL ? `WR_Rr1 : `WR_RD;

    // =====================================================================
    // Write-back Data Selection
    // =====================================================================
    wire WD_SEL_ALU = TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | LU12I_W | PCADDU12I;
    wire WD_SEL_RAM = LOAD;
    wire WD_SEL_PC4 = BL | JIRL;

    assign wd_sel = {2{WD_SEL_ALU}} & `WD_ALU |
                    {2{WD_SEL_RAM}} & `WD_RAM |
                    {2{WD_SEL_PC4}} & `WD_PC4 ;

endmodule
