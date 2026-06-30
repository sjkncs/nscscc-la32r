`ifndef DEFINES_VH
`define DEFINES_VH

`define ENABLE_ICACHE
`define ENABLE_DCACHE
`define ENABLE_BPU

`define CACHE_BLK_LEN   4
`define CACHE_BLK_SIZE  (`CACHE_BLK_LEN*32)
`define CACHE_BLK_NUM   32

`define PC_INIT_VAL 32'h1C000000

// NPC operation
`define NPC_PC4     2'b00
`define NPC_BR      2'b01
`define NPC_JIRL    2'b10
`define NPC_B       2'b11

// Immediate extension type
`define EXT_12      3'b011
`define EXT_20      3'b110
`define EXT_5       3'b001
`define EXT_12U     3'b010
`define EXT_16      3'b100
`define EXT_26      3'b101

// ALU operation
`define ALU_ADD     5'b00000
`define ALU_SUB     5'b00001
`define ALU_SLT     5'b00010
`define ALU_SLTU    5'b00011
`define ALU_AND     5'b00100
`define ALU_OR      5'b00101
`define ALU_XOR     5'b00110
`define ALU_NOR     5'b00111
`define ALU_SLL     5'b01000
`define ALU_SRL     5'b01001
`define ALU_SRA     5'b01010
`define ALU_MUL     5'b01011
`define ALU_MULH    5'b01100
`define ALU_MULHU   5'b01101
`define ALU_DIV     5'b01110
`define ALU_DIVU    5'b01111
`define ALU_MOD     5'b10000
`define ALU_MODU    5'b10001
`define ALU_LU12I   5'b10010
`define ALU_SUNE    5'b10011
`define ALU_SGE     5'b10100
`define ALU_SGEU    5'b10101

// RAM read-data extension type
`define RAM_EXT_N   3'b000
`define RAM_EXT_W   3'b001
`define RAM_EXT_B   3'b010
`define RAM_EXT_BU  3'b011
`define RAM_EXT_H   3'b100
`define RAM_EXT_HU  3'b101

// RAM write enable patterns
`define RAM_WE_N    4'b0000
`define RAM_WE_W    4'b1111
`define RAM_WE_H    4'b0011
`define RAM_WE_B    4'b0001

// Source register 2 selection
`define R2_RK       1'b1
`define R2_RD       1'b0

// ALU operand A selection
`define ALUA_R1     1'b1
`define ALUA_PC     1'b0

// ALU operand B selection
`define ALUB_R2     1'b1
`define ALUB_EXT    1'b0

// Write-back register selection
`define WR_RD       1'b1
`define WR_Rr1      1'b0

// Write-back data selection
`define WD_ALU      2'b11
`define WD_RAM      2'b01
`define WD_PC4      2'b10
`define WD_EXT      2'b00

`endif
