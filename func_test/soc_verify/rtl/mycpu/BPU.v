`timescale 1ns / 1ps

`include "defines.vh"

module BPU (
    input  wire         cpu_clk    ,
    input  wire         cpu_rstn   ,
    input  wire [31:0]  if_pc      ,    // IF阶段的PC值
    input  wire         if_valid   ,    // IF阶段的有效信号
    input  wire         id_valid   ,    // ID阶段的有效信号
    input  wire         pl_suspend ,    // 流水线暂停信号
    // predict branch direction and target
    output wire         pred_taken ,    // 预测是否跳转
    output wire [31:0]  pred_target,    // 预测的下一条指令地址
    output wire         pred_error ,    // 预测是否失败
    // signals from EX stage (pipeline-carried prediction + actual result)
    input  wire         ex_valid   ,    // EX阶段的有效信号
    input  wire         ex_is_bj   ,    // EX阶段是否是条件分支或直接跳转指令
    input  wire [31:0]  ex_pc      ,    // EX阶段的PC值
    input  wire         real_taken ,    // EX阶段指令实际是否发生跳转
    input  wire [31:0]  real_target,    // EX阶段指令发生跳转时的目标地址
    input  wire         ex_pred_taken,  // EX阶段指令的BPU预测方向 (从流水线回传)
    input  wire [31:0]  ex_pred_target, // EX阶段指令的BPU预测目标 (从流水线回传)
    // RAS signals from EX stage
    input  wire         ex_is_call ,    // EX阶段是否是call指令 (push RAS)
    input  wire         ex_is_ret       // EX阶段是否是ret指令 (pop RAS)
);

`ifdef ENABLE_BPU

    // =========================================================================
    // BTB: Direct-mapped, 256 entries, 2-bit saturating counter
    // Address folding: index = PC[9:2] ^ PC[17:10] (8-bit XOR hash)
    // Tag = PC[31:10] (22 bits) for disambiguation
    // =========================================================================
    localparam BTB_SIZE = 256;
    localparam IDX_W    = 8;
    localparam TAG_W    = 22;   // 32 - 10 = 22 (tag from bit 10 upward)

    reg [TAG_W-1:0] btb_tag     [BTB_SIZE-1:0];
    reg             btb_valid   [BTB_SIZE-1:0];
    reg [1:0]       btb_counter [BTB_SIZE-1:0];
    reg [31:0]      btb_target  [BTB_SIZE-1:0];
    reg             btb_is_ret  [BTB_SIZE-1:0];   // is this a return instruction?

    // =========================================================================
    // RAS: 4-entry circular stack, managed non-speculatively from EX stage
    // =========================================================================
    localparam RAS_DEPTH = 4;
    localparam RAS_PTR_W = 2;
    reg [31:0]      ras_stack [RAS_DEPTH-1:0];
    reg [RAS_PTR_W-1:0] ras_tos;   // top-of-stack pointer

    wire [31:0] ras_top = ras_stack[ras_tos];   // current RAS top for prediction

    // ----- Address folding hash function -----
    wire [IDX_W-1:0] hash_idx_if = if_pc[9:2] ^ if_pc[17:10];
    wire [IDX_W-1:0] hash_idx_ex = ex_pc[9:2] ^ ex_pc[17:10];

    // ----- Prediction (combinational lookup with if_pc) -----
    wire [IDX_W-1:0] pred_idx    = hash_idx_if;
    wire [TAG_W-1:0] pred_tag    = if_pc[31:10];
    wire             pred_hit    = btb_valid[pred_idx] && (btb_tag[pred_idx] == pred_tag);
    wire             pred_taken_i = pred_hit && btb_counter[pred_idx][1];
    wire             pred_is_ret  = pred_hit && btb_is_ret[pred_idx];

    assign pred_taken  = pred_taken_i;
    // For returns: override BTB target with RAS top
    assign pred_target = pred_taken_i ? (pred_is_ret ? ras_top : btb_target[pred_idx])
                                      : (if_pc + 32'h4);

    // ----- Misprediction detection (using pipeline-carried prediction) -----
    wire ex_branch_valid  = ex_valid & ex_is_bj & !pl_suspend;
    wire direction_error  = ex_branch_valid & (ex_pred_taken != real_taken);
    wire target_error     = ex_branch_valid & ex_pred_taken & real_taken &
                            (ex_pred_target != real_target);
    assign pred_error     = direction_error | target_error;

    // ----- BTB Update (on branch resolution from EX, using folded hash) -----
    wire [IDX_W-1:0] up_idx  = hash_idx_ex;
    wire [TAG_W-1:0] up_tag  = ex_pc[31:10];
    wire             up_hit  = btb_valid[up_idx] && (btb_tag[up_idx] == up_tag);
    wire [1:0]       old_cnt = btb_counter[up_idx];

    // 2-bit saturating counter update
    wire [1:0] new_cnt = real_taken ?
                         (old_cnt == 2'b11 ? 2'b11 : old_cnt + 2'b01) :
                         (old_cnt == 2'b00 ? 2'b00 : old_cnt - 2'b01) ;

    // RAS push/pop signals (non-speculative, from EX resolution)
    wire ras_push = ex_valid & ex_is_call & !pl_suspend;
    wire ras_pop  = ex_valid & ex_is_ret  & !pl_suspend;

    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            for (i = 0; i < BTB_SIZE; i = i + 1) begin
                btb_valid[i]   <= 1'b0;
                btb_tag[i]     <= {TAG_W{1'b0}};
                btb_target[i]  <= 32'h0;
                btb_counter[i] <= 2'b01;   // weakly not-taken
                btb_is_ret[i]  <= 1'b0;
            end
            for (i = 0; i < RAS_DEPTH; i = i + 1)
                ras_stack[i] <= 32'h0;
            ras_tos <= {RAS_PTR_W{1'b0}};
        end else begin
            // BTB update on branch/jump resolution
            if (ex_branch_valid) begin
                if (up_hit) begin
                    btb_counter[up_idx] <= new_cnt;
                    btb_is_ret[up_idx]  <= ex_is_ret;
                    if (real_taken)
                        btb_target[up_idx] <= real_target;
                end else if (real_taken) begin
                    btb_valid[up_idx]   <= 1'b1;
                    btb_tag[up_idx]     <= up_tag;
                    btb_target[up_idx]  <= real_target;
                    btb_counter[up_idx] <= 2'b10;   // weakly taken
                    btb_is_ret[up_idx]  <= ex_is_ret;
                end
            end
            // RAS management
            if (ras_push) begin
                ras_tos <= ras_tos + 1'b1;
                ras_stack[ras_tos + 1'b1] <= ex_pc + 32'h4;
            end else if (ras_pop) begin
                ras_tos <= ras_tos - 1'b1;
            end
        end
    end

`else

    assign pred_taken  = 1'b0;
    assign pred_target = if_pc + 32'h4;

    wire direction_error = ex_valid & ex_is_bj & !pl_suspend & (ex_pred_taken != real_taken);
    assign pred_error    = direction_error;

`endif

endmodule
