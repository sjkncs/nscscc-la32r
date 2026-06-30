`timescale 1ns / 1ps

`include "defines.vh"

module ICache (
    input  wire         cpu_rstn,       // low active
    input  wire         cpu_clk,
    // Interface to CPU
    input  wire         inst_rreq,
    input  wire [31:0]  inst_addr,
    output reg          inst_valid,
    output reg  [31:0]  inst_out,
    input  wire         pred_error,
    // Interface to Read Bus
    input  wire         dev_rrdy,       // device ready to be read
    output reg  [ 3:0]  cpu_ren,        // cpu read mask
    output reg  [31:0]  cpu_raddr,      // cpu read data address
    input  wire         dev_rvalid,     // device data valid
    input  wire [31:0]  dev_rdata       // data to be read
);

`ifdef ENABLE_ICACHE

    // =========================================================================
    // 2-way set-associative ICache, 32 sets × 2 ways = 64 entries
    // 4-word (128-bit) cache lines, 1-bit pseudo-LRU replacement
    // Tag=addr[31:9](23b), SetIdx=addr[8:4](5b), WOff=addr[3:2](2b)
    // =========================================================================
    localparam NUM_SETS = 32;
    localparam NUM_WAYS = 2;
    localparam IDX_W = 5;
    localparam TAG_W = 23;
    localparam BLK_W = `CACHE_BLK_LEN;

    localparam S_IDLE        = 2'b00;
    localparam S_REFILL_REQ  = 2'b01;
    localparam S_REFILL_WAIT = 2'b10;
    reg [1:0] state, nstat;
    // Testbench compatibility aliases
    wire [1:0] current_state = state;
    localparam REFILL = S_REFILL_REQ;

    // Way 0
    reg [TAG_W-1:0]     w0_tag   [NUM_SETS-1:0];
    reg                 w0_valid [NUM_SETS-1:0];
    reg [BLK_W*32-1:0] w0_data  [NUM_SETS-1:0];
    // Way 1
    reg [TAG_W-1:0]     w1_tag   [NUM_SETS-1:0];
    reg                 w1_valid [NUM_SETS-1:0];
    reg [BLK_W*32-1:0] w1_data  [NUM_SETS-1:0];
    // LRU: 0 = replace way0 next, 1 = replace way1 next
    reg                 lru      [NUM_SETS-1:0];

    // --- Combinational lookup ---
    wire [1:0]       lk_woff  = inst_addr[3:2];
    wire [IDX_W-1:0] lk_index = inst_addr[IDX_W+3:4];
    wire [TAG_W-1:0] lk_tag   = inst_addr[31:IDX_W+4];

    // Tag match (no inst_rreq gate — allows parallel word selection)
    wire w0_match = w0_valid[lk_index] & (w0_tag[lk_index] == lk_tag);
    wire w1_match = w1_valid[lk_index] & (w1_tag[lk_index] == lk_tag);
    wire cache_hit = inst_rreq & (w0_match | w1_match);

    // Word select from each way IN PARALLEL with tag compare
    reg [31:0] w0_word, w1_word;
    always @(*) begin
        case (lk_woff)
            2'd0: begin w0_word = w0_data[lk_index][ 31:  0]; w1_word = w1_data[lk_index][ 31:  0]; end
            2'd1: begin w0_word = w0_data[lk_index][ 63: 32]; w1_word = w1_data[lk_index][ 63: 32]; end
            2'd2: begin w0_word = w0_data[lk_index][ 95: 64]; w1_word = w1_data[lk_index][ 95: 64]; end
            2'd3: begin w0_word = w0_data[lk_index][127: 96]; w1_word = w1_data[lk_index][127: 96]; end
        endcase
    end
    // Way select: narrow 32-bit 2:1 mux (after tag compare settles)
    wire [31:0] hit_word = w0_match ? w0_word : w1_word;

    // --- Refill address & fields ---
    reg [31:0] refill_addr;
    reg        refill_way;   // which way to fill (from LRU at miss time)
    wire [IDX_W-1:0] rf_index = refill_addr[IDX_W+3:4];
    wire [TAG_W-1:0] rf_tag   = refill_addr[31:IDX_W+4];
    wire [1:0]       rf_woff  = refill_addr[3:2];

    // --- Refill collection ---
    reg [BLK_W*32-1:0] refill_buf;
    reg [2:0]           refill_cnt;
    wire refill_done = (refill_cnt == BLK_W);
    reg  refill_abort;
    wire do_fill = (state == S_REFILL_WAIT) & refill_done & !refill_abort;

    // --- State Machine ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)
            state <= S_IDLE;
        else if (pred_error && state != S_REFILL_WAIT)
            state <= S_IDLE;
        else if (pred_error && state == S_REFILL_WAIT && !refill_done)
            state <= S_REFILL_WAIT;
        else
            state <= nstat;
    end

    always @(*) begin
        case (state)
            S_IDLE:        nstat = (inst_rreq & !cache_hit) ? S_REFILL_REQ : S_IDLE;
            S_REFILL_REQ:  nstat = dev_rrdy     ? S_REFILL_WAIT : S_REFILL_REQ;
            S_REFILL_WAIT: nstat = refill_done   ? S_IDLE        : S_REFILL_WAIT;
            default:       nstat = S_IDLE;
        endcase
    end

    // --- Latch refill address & replacement way ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            refill_addr <= 32'h0;
            refill_way  <= 1'b0;
        end else if (state == S_IDLE && inst_rreq && !cache_hit) begin
            refill_addr <= inst_addr;
            refill_way  <= lru[lk_index];
        end
    end

    // --- Refill word collection (4 words) ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            refill_cnt <= 3'd0;
            refill_buf <= 128'h0;
        end else if (state == S_IDLE) begin
            refill_cnt <= 3'd0;
        end else if (state == S_REFILL_WAIT && dev_rvalid && !refill_done) begin
            case (refill_cnt)
                3'd0: refill_buf[ 31:  0] <= dev_rdata;
                3'd1: refill_buf[ 63: 32] <= dev_rdata;
                3'd2: refill_buf[ 95: 64] <= dev_rdata;
                3'd3: refill_buf[127: 96] <= dev_rdata;
            endcase
            refill_cnt <= refill_cnt + 3'd1;
        end
    end

    // --- Refill abort tracking ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)
            refill_abort <= 1'b0;
        else if (state == S_IDLE)
            refill_abort <= 1'b0;
        else if (pred_error && (state == S_REFILL_WAIT || state == S_REFILL_REQ))
            refill_abort <= 1'b1;
    end

    // --- Cache fill & LRU update ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin : cache_reset
            integer i;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                w0_valid[i] <= 1'b0;  w0_tag[i] <= {TAG_W{1'b0}};  w0_data[i] <= 128'h0;
                w1_valid[i] <= 1'b0;  w1_tag[i] <= {TAG_W{1'b0}};  w1_data[i] <= 128'h0;
                lru[i]      <= 1'b0;
            end
        end else begin
            // Update LRU on hit (point away from accessed way)
            if (cache_hit)
                lru[lk_index] <= w0_match ? 1'b1 : 1'b0;

            // Fill refill data into selected way
            if (do_fill) begin
                if (!refill_way) begin
                    w0_valid[rf_index] <= 1'b1;
                    w0_tag[rf_index]   <= rf_tag;
                    w0_data[rf_index]  <= refill_buf;
                end else begin
                    w1_valid[rf_index] <= 1'b1;
                    w1_tag[rf_index]   <= rf_tag;
                    w1_data[rf_index]  <= refill_buf;
                end
                lru[rf_index] <= refill_way ? 1'b0 : 1'b1;
            end
        end
    end

    // --- Output to CPU ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            inst_valid <= 1'b0;
            inst_out   <= 32'h0;
        end else if (pred_error) begin
            inst_valid <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    inst_valid <= cache_hit;
                    inst_out   <= cache_hit ? hit_word : 32'h0;
                end
                S_REFILL_WAIT: begin
                    if (refill_done && !refill_abort) begin
                        inst_valid <= 1'b1;
                        case (rf_woff)
                            2'd0: inst_out <= refill_buf[ 31:  0];
                            2'd1: inst_out <= refill_buf[ 63: 32];
                            2'd2: inst_out <= refill_buf[ 95: 64];
                            2'd3: inst_out <= refill_buf[127: 96];
                        endcase
                    end else begin
                        inst_valid <= 1'b0;
                    end
                end
                default: inst_valid <= 1'b0;
            endcase
        end
    end

    // --- Device read interface (line-aligned address) ---
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            cpu_ren   <= 4'h0;
            cpu_raddr <= 32'h0;
        end else begin
            if (!pred_error && !refill_abort && state == S_REFILL_REQ && dev_rrdy) begin
                cpu_ren   <= 4'hF;
                cpu_raddr <= {refill_addr[31:4], 4'b0000};
            end else begin
                cpu_ren   <= 4'h0;
            end
        end
    end

`else

    localparam IDLE  = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;
    reg       dev_rvalid_r;
    wire      dev_rvalid_pos = !dev_rvalid_r & dev_rvalid;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        state        <= !cpu_rstn ? IDLE : nstat;
        dev_rvalid_r <= !cpu_rstn ? 1'b0 : dev_rvalid;
    end

    always @(*) begin
        case (state)
            IDLE   : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0  : nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1  : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : (dev_rvalid_pos ? IDLE : STAT1);
            default: nstat = IDLE;
        endcase
    end

    reg cpu_ren0;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            inst_valid <= 1'b0;
            cpu_ren0   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren0   <= dev_rrdy ? 1'b1 : 1'b0;
                end
                STAT1: begin
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                    inst_valid <= dev_rvalid_pos ? 1'b1 : 1'b0;
                    inst_out   <= dev_rvalid_pos ? dev_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= 1'b0;
                end
            endcase
        end
    end

    always @(*) cpu_ren = {4{cpu_ren0 & !inst_rreq}};

`endif

endmodule
