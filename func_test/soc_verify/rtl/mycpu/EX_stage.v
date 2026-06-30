`timescale 1ns / 1ps

`include "defines.vh"

module EX_stage (
    input  wire         cpu_rstn     ,
    input  wire         cpu_clk      ,
    // pipeline control
    input  wire         pl_suspend   ,      // 流水线暂停信号
    input  wire         load_use_stall,     // Load-Use暂停信号
    output reg          ldst_unalign ,      // 访存地址是否不满足对齐条件
    // From ID
    input  wire         id_valid     ,      // ID阶段有效信号
    input  wire [31:0]  id_pc        ,      // ID阶段PC值
    input  wire [ 1:0]  id_npc_op    ,      // ID阶段的npc_op，用于控制下一条指令PC值的生成
    input  wire [31:0]  id_ext       ,      // ID阶段的扩展后的立即数
    input  wire [31:0]  id_real_rD1  ,      // ID阶段的源操作数1的实际值
    input  wire [31:0]  id_real_rD2  ,      // ID阶段的源操作数2的实际值
    input  wire [ 4:0]  id_alu_op    ,      // ID阶段的alu_op，用于控制ALU进行何种运算
    input  wire         id_alua_sel  ,      // ID阶段的ALU操作数A选择信号（选择源寄存器1的值或扩展后的立即数或其他）
    input  wire         id_alub_sel  ,      // ID阶段的ALU操作数B选择信号（选择源寄存器2的值或扩展后的立即数或其他）
    input  wire         id_rf_we     ,      // ID阶段的寄存器写使能（指令需要写回时rf_we为1）
    input  wire [ 4:0]  id_wR        ,      // ID阶段的目标寄存器
    input  wire [ 1:0]  id_wd_sel    ,      // ID阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    input  wire [ 3:0]  id_ram_we    ,      // ID阶段的主存写使能信号（针对store指令）
    input  wire [ 2:0]  id_ram_ext_op,      // ID阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    input  wire         id_is_br_jmp ,      // ID阶段是否是条件分支或直接跳转指令
    input  wire         id_pred_taken,       // ID阶段的BPU预测方向
    input  wire [31:0]  id_pred_target,      // ID阶段的BPU预测目标地址
    input  wire         id_is_call   ,       // ID阶段是否是call指令
    input  wire         id_is_ret    ,       // ID阶段是否是ret指令
    // To IF
    output wire [ 1:0]  ex_npc_op    ,      // EX阶段的npc_op，用于控制下一条指令PC值的生成
    output wire         ex_alu_f     ,      // EX阶段的标志位
    output wire         ex_is_ld_st  ,      // EX阶段是否是Load/Store指令
    output wire         ex_is_br_jmp ,      // EX阶段是否是条件分支或直接跳转指令
    output wire         ex_br_jmp_f  ,      // EX阶段分支跳转指令实际是否会发生跳转
    output wire         ex_pred_taken,       // EX阶段的BPU预测方向
    output wire [31:0]  ex_pred_target,      // EX阶段的BPU预测目标地址
    output wire         ex_is_call   ,       // EX阶段是否是call指令
    output wire         ex_is_ret    ,       // EX阶段是否是ret指令
    // To MEM
    output wire         ex_valid     ,      // EX阶段有效信号
    output wire [31:0]  ex_pc        ,      // EX阶段PC值
    output wire [31:0]  ex_rD1       ,      // EX阶段的源寄存器1的值
    output wire [31:0]  ex_rD2       ,      // EX阶段的源寄存器2的值
    output wire [31:0]  ex_ext       ,      // EX阶段的扩展后的立即数
    output wire [31:0]  ex_alu_C     ,      // EX阶段的ALU运算结果
    output wire         ex_rf_we     ,      // EX阶段的寄存器写使能（指令需要写回时rf_we为1）
    output wire [ 4:0]  ex_wR        ,      // EX阶段的目的寄存器
    output wire [ 1:0]  ex_wd_sel    ,      // EX阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    output wire [ 3:0]  ex_ram_we    ,      // EX阶段的主存写使能信号（针对store指令）
    output wire [ 2:0]  ex_ram_ext_op,      // EX阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    // Divider pipeline control
    output wire         div_suspend  ,      // 除法器正在运算，暂停流水线
    output wire         div_done     ,      // 除法器运算完成
    // Data Forward
    output reg  [31:0]  ex_wd        ,      // EX阶段的待写回数据
    output wire         ex_sel_ram          // EX阶段是否是访存指令 (特指Load指令, 用于Load-Use处理)
);

    wire [ 4:0] ex_alu_op;
    assign      ex_is_ld_st = ex_valid & ((ex_wd_sel == `WD_RAM) | (ex_ram_we != `RAM_WE_N));
    wire        ex_alua_sel, ex_alub_sel;
    wire [31:0] ex_alu_A = ex_alua_sel ? ex_rD1 : ex_pc;
    wire [31:0] ex_alu_B = ex_alub_sel ? ex_rD2 : ex_ext;
    assign      ex_br_jmp_f = ex_is_br_jmp & ((ex_npc_op == `NPC_BR) ? ex_alu_f : 1'b1);
    assign      ex_sel_ram  = ex_valid & (ex_wd_sel == `WD_RAM) & (ex_ram_we == `RAM_WE_N);

    ID_EX u_ID_EX (
        .cpu_clk        (cpu_clk),
        .cpu_rstn       (cpu_rstn),
        .suspend        (pl_suspend),
        .valid_in       (id_valid & !load_use_stall),

        .wR_in          (id_wR),
        .pc_in          (id_pc),
        .rD1_in         (id_real_rD1),
        .rD2_in         (id_real_rD2),
        .ext_in         (id_ext),

        .npc_op_in      (id_npc_op),
        .rf_we_in       (id_rf_we & id_valid),
        .wd_sel_in      (id_wd_sel),
        .alu_op_in      (id_alu_op & {5{id_valid}}),
        .alua_sel_in    (id_alua_sel),
        .alub_sel_in    (id_alub_sel),
        .ram_we_in      (id_ram_we & {4{id_valid}}),
        .ram_ext_op_in  (id_ram_ext_op),
        .is_br_jmp_in   (id_is_br_jmp & id_valid),
        .pred_taken_in  (id_pred_taken & id_valid),
        .pred_target_in (id_pred_target),
        .is_call_in     (id_is_call & id_valid),
        .is_ret_in      (id_is_ret  & id_valid),

        .valid_out      (ex_valid),
        .wR_out         (ex_wR),
        .pc_out         (ex_pc),
        .rD1_out        (ex_rD1),
        .rD2_out        (ex_rD2),
        .ext_out        (ex_ext),

        .npc_op_out     (ex_npc_op),
        .rf_we_out      (ex_rf_we),
        .wd_sel_out     (ex_wd_sel),
        .alu_op_out     (ex_alu_op),
        .alua_sel_out   (ex_alua_sel),
        .alub_sel_out   (ex_alub_sel),
        .ram_we_out     (ex_ram_we),
        .ram_ext_op_out (ex_ram_ext_op),
        .is_br_jmp_out  (ex_is_br_jmp),
        .pred_taken_out (ex_pred_taken),
        .pred_target_out(ex_pred_target),
        .is_call_out    (ex_is_call),
        .is_ret_out     (ex_is_ret)
    );

    // --- Multi-cycle Divider ---
    wire        alu_is_div_mod;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire        div_busy;

    // Start divider on first cycle of a div/mod instruction (not already busy, not on done cycle)
    wire div_start = ex_valid & alu_is_div_mod & !div_busy & !div_done;
    wire div_is_signed = (ex_alu_op == `ALU_DIV) || (ex_alu_op == `ALU_MOD);

    // Suspend pipeline while divider is computing (from start until done)
    assign div_suspend = (div_start | div_busy) & !div_done;

    divider u_divider (
        .clk        (cpu_clk),
        .rstn       (cpu_rstn),
        .start      (div_start),
        .is_signed  (div_is_signed),
        .dividend   (ex_alu_A),
        .divisor    (ex_alu_B),
        .quotient   (div_quotient),
        .remainder  (div_remainder),
        .busy       (div_busy),
        .done       (div_done)
    );

    ALU u_ALU (
        .alu_op        (ex_alu_op),
        .A             (ex_alu_A ),
        .B             (ex_alu_B ),
        .div_quotient  (div_quotient),
        .div_remainder (div_remainder),
        .C             (ex_alu_C ),
        .f             (ex_alu_f ),
        .is_div_mod    (alu_is_div_mod)
    );

    always @(*) begin
        case (ex_wd_sel)
            `WD_ALU: ex_wd = ex_alu_C;
            `WD_PC4: ex_wd = ex_pc + 32'h4;
            `WD_EXT: ex_wd = ex_ext;
            default: ex_wd = 32'h0;
        endcase
    end

    // 检查访存地址是否关于 待访问数据大小 对齐, 不对齐则不访存
    always @(*) begin
        case (ex_ram_we)
            `RAM_WE_W: ldst_unalign = (ex_alu_C[1:0] != 2'h0);
            `RAM_WE_H: ldst_unalign = (ex_alu_C[0] != 1'b0);
            `RAM_WE_B: ldst_unalign = 1'b0;
            default:
                case (ex_ram_ext_op)
                    `RAM_EXT_W : ldst_unalign = (ex_alu_C[1:0] != 2'h0);
                    `RAM_EXT_H : ldst_unalign = (ex_alu_C[0] != 1'b0);
                    `RAM_EXT_HU: ldst_unalign = (ex_alu_C[0] != 1'b0);
                    default    : ldst_unalign = 1'b0;
                endcase
        endcase
    end

endmodule
