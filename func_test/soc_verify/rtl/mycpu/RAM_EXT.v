`timescale 1ns / 1ps

`include "defines.vh"

module RAM_EXT (
    input  wire [ 2:0]  ram_ext_op ,
    input  wire [ 1:0]  byte_offset,
    input  wire [31:0]  din        ,
    output reg  [31:0]  ext_out    
);

    reg [7:0]  byte_sel;
    reg [15:0] half_sel;

    always @(*) begin
        case (byte_offset)
            2'b00: begin byte_sel = din[ 7: 0]; half_sel = din[15: 0]; end
            2'b01: begin byte_sel = din[15: 8]; half_sel = din[15: 0]; end
            2'b10: begin byte_sel = din[23:16]; half_sel = din[31:16]; end
            2'b11: begin byte_sel = din[31:24]; half_sel = din[31:16]; end
        endcase
    end

    always @(*) begin
        case (ram_ext_op)
            `RAM_EXT_W : ext_out = din;
            `RAM_EXT_B : ext_out = {{24{byte_sel[7]}}, byte_sel};
            `RAM_EXT_BU: ext_out = {24'h0, byte_sel};
            `RAM_EXT_H : ext_out = {{16{half_sel[15]}}, half_sel};
            `RAM_EXT_HU: ext_out = {16'h0, half_sel};
            default    : ext_out = din;
        endcase
    end

endmodule
