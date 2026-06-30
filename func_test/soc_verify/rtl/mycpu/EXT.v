`timescale 1ns / 1ps

`include "defines.vh"

module EXT (
    input  wire [ 2:0]  ext_op,
    input  wire [25:0]  din   ,
    output reg  [31:0]  ext   
);

    always @(*) begin
        case (ext_op)
            `EXT_5  : ext = {27'h0, din[14:10]};
            `EXT_12U: ext = {20'h0, din[21:10]};
            `EXT_12 : ext = {{20{din[21]}}, din[21:10]};
            `EXT_16 : ext = {{14{din[25]}}, din[25:10], 2'b00};
            `EXT_26 : ext = {{4{din[9]}}, din[9:0], din[25:10], 2'b00};
            `EXT_20 : ext = {din[24:5], 12'h000};
            default : ext = 32'h0;
        endcase
    end

endmodule
