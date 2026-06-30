`timescale 1ns / 1ps

// Multi-cycle restoring divider for DIV.W/DIVU.W/MOD.W/MODU.W
// 2-bit-per-cycle unrolled: Latency 18 cycles (1 init + 16 iterate + 1 finalize)
// Interface: start pulse -> busy -> done pulse with result
module divider (
    input  wire         clk,
    input  wire         rstn,
    input  wire         start,      // 1-cycle pulse to begin division
    input  wire         is_signed,  // 1 = signed (DIV/MOD), 0 = unsigned (DIVU/MODU)
    input  wire [31:0]  dividend,
    input  wire [31:0]  divisor,
    output reg  [31:0]  quotient,
    output reg  [31:0]  remainder,
    output reg          busy,       // high while dividing
    output reg          done        // 1-cycle pulse when result ready
);

    reg [31:0] A;           // partial remainder (upper)
    reg [31:0] Q;           // quotient being built (lower)
    reg [31:0] M;           // absolute divisor
    reg [ 4:0] count;       // iteration counter (16 double-steps)
    reg        sign_q;      // sign of quotient
    reg        sign_r;      // sign of remainder
    reg        div_by_zero;

    // ---- 2-bit-per-cycle unrolled combinational logic ----
    // Step 1: process Q[31]
    wire [32:0] s1_AQ  = {A, Q[31]};
    wire [32:0] s1_sub = s1_AQ - {1'b0, M};
    wire        s1_ge  = ~s1_sub[32];
    wire [31:0] s1_A   = s1_ge ? s1_sub[31:0] : s1_AQ[31:0];

    // Step 2: process Q[30] using step1 result
    wire [32:0] s2_AQ  = {s1_A, Q[30]};
    wire [32:0] s2_sub = s2_AQ - {1'b0, M};
    wire        s2_ge  = ~s2_sub[32];
    wire [31:0] s2_A   = s2_ge ? s2_sub[31:0] : s2_AQ[31:0];

    localparam S_IDLE = 2'd0;
    localparam S_ITER = 2'd1;
    localparam S_DONE = 2'd2;
    reg [1:0] state;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            quotient  <= 32'h0;
            remainder <= 32'h0;
        end else begin
            done <= 1'b0;  // default: clear done pulse

            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        // Handle divide by zero
                        if (divisor == 32'h0) begin
                            quotient  <= 32'h0;
                            remainder <= 32'h0;
                            div_by_zero <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            div_by_zero <= 1'b0;
                            // Convert to absolute values for signed division
                            if (is_signed && dividend[31])
                                Q <= ~dividend + 1'b1;
                            else
                                Q <= dividend;

                            if (is_signed && divisor[31])
                                M <= ~divisor + 1'b1;
                            else
                                M <= divisor;

                            A     <= 32'h0;
                            count <= 5'd16;
                            sign_q <= is_signed & (dividend[31] ^ divisor[31]);
                            sign_r <= is_signed & dividend[31];
                            state  <= S_ITER;
                        end
                    end
                end

                S_ITER: begin
                    // 2-bit unrolled restoring division:
                    // Step 1 & 2 computed combinationally above
                    A <= s2_A;
                    Q <= {Q[29:0], s1_ge, s2_ge};

                    count <= count - 5'd1;
                    if (count == 5'd1)
                        state <= S_DONE;
                end

                S_DONE: begin
                    if (!div_by_zero) begin
                        quotient  <= sign_q ? (~Q + 1'b1) : Q;
                        remainder <= sign_r ? (~A + 1'b1) : A;
                    end
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
