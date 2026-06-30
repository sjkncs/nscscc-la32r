`timescale 1ns / 1ps

`include "defines.vh"

module IF_ID (
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire         suspend ,

    input  wire         valid_in,
    input  wire [31:0]  pc_in   ,
    input  wire         pred_taken_in ,
    input  wire [31:0]  pred_target_in,
    output reg  [31:0]  pc_out  ,
    output reg          pred_taken_out ,
    output reg  [31:0]  pred_target_out
);

    always @(posedge cpu_clk) begin
        pc_out          <= !cpu_rstn ? 32'h0 : (suspend | !valid_in) ? pc_out          : pc_in;
        pred_taken_out  <= !cpu_rstn ?  1'h0 : (suspend | !valid_in) ? pred_taken_out  : pred_taken_in;
        pred_target_out <= !cpu_rstn ? 32'h0 : (suspend | !valid_in) ? pred_target_out : pred_target_in;
    end

endmodule
