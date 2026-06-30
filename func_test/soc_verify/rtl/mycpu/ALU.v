`timescale 1ns / 1ps

`include "defines.vh"

module ALU (
    input  wire [ 4:0]  alu_op,
    input  wire [31:0]  A     ,
    input  wire [31:0]  B     ,
    input  wire [31:0]  div_quotient,   // from multi-cycle divider
    input  wire [31:0]  div_remainder,  // from multi-cycle divider
    output reg  [31:0]  C     ,
    output reg          f     ,
    output wire         is_div_mod      // signals a div/mod operation
);

    wire [31:0] sum   = A + B;
    wire [31:0] diff  = A - B;
    wire        slt   = ($signed(A) < $signed(B)) ? 1'b1 : 1'b0;
    wire        sltu  = (A < B) ? 1'b1 : 1'b0;
    wire [31:0] sll_r = A << B[4:0];
    wire [31:0] srl_r = A >> B[4:0];
    wire [31:0] sra_r = $signed(A) >>> B[4:0];

    wire [63:0] mul_ss = $signed(A) * $signed(B);
    wire [63:0] mul_uu = {32'b0, A} * {32'b0, B};

    assign is_div_mod = (alu_op == `ALU_DIV) || (alu_op == `ALU_DIVU) ||
                         (alu_op == `ALU_MOD) || (alu_op == `ALU_MODU);

    always @(*) begin
        case (alu_op)
            `ALU_ADD   : C = sum;
            `ALU_SUB   : C = diff;
            `ALU_SLT   : C = {31'h0, slt};
            `ALU_SLTU  : C = {31'h0, sltu};
            `ALU_AND   : C = A & B;
            `ALU_OR    : C = A | B;
            `ALU_XOR   : C = A ^ B;
            `ALU_NOR   : C = ~(A | B);
            `ALU_SLL   : C = sll_r;
            `ALU_SRL   : C = srl_r;
            `ALU_SRA   : C = sra_r;
            `ALU_MUL   : C = mul_ss[31:0];
            `ALU_MULH  : C = mul_ss[63:32];
            `ALU_MULHU : C = mul_uu[63:32];
            `ALU_DIV   : C = div_quotient;
            `ALU_DIVU  : C = div_quotient;
            `ALU_MOD   : C = div_remainder;
            `ALU_MODU  : C = div_remainder;
            `ALU_LU12I : C = B;
            `ALU_SUNE  : C = diff;
            `ALU_SGE   : C = {31'h0, slt};
            `ALU_SGEU  : C = {31'h0, sltu};
            default    : C = 32'h0;
        endcase
    end

    always @(*) begin
        case (alu_op)
            `ALU_SUB   : f = (diff == 32'h0) ? 1'b1 : 1'b0;
            `ALU_SUNE  : f = (diff != 32'h0) ? 1'b1 : 1'b0;
            `ALU_SLT   : f = slt;
            `ALU_SGE   : f = ~slt;
            `ALU_SLTU  : f = sltu;
            `ALU_SGEU  : f = ~sltu;
            default    : f = 1'b0;
        endcase
    end

endmodule
