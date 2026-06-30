`timescale 1ns / 1ps

`include "defines.vh"

module DCache (
    input  wire         cpu_rstn,       // low active
    input  wire         cpu_clk,
    // Interface to CPU
    input  wire [ 3:0]  data_ren,
    input  wire [31:0]  data_addr,
    output reg          data_valid,
    output reg  [31:0]  data_rdata,
    input  wire [ 3:0]  data_wen,
    input  wire [31:0]  data_wdata,
    output reg          data_wresp,
    // Interface to Write Bus
    input  wire         dev_wrdy,       // device ready to be written (device: main memory or peripherals)
    output reg  [ 3:0]  cpu_wen,        // cpu write enable
    output reg  [31:0]  cpu_waddr,      // cpu write data address
    output reg  [31:0]  cpu_wdata,      // cpu write data
    // Interface to Read Bus
    input  wire         dev_rrdy,       // device ready to be read
    output reg  [ 3:0]  cpu_ren,        // cpu read mask
    output reg  [31:0]  cpu_raddr,      // cpu read data address
    input  wire         dev_rvalid,     // device data valid
    input  wire [31:0]  dev_rdata       // data to be read
);

`ifdef ENABLE_DCACHE

    // =========================================================================
    // Direct-mapped DCache, 32 entries, 4-word (128-bit) cache lines
    // Write-through, write-around: stores bypass cache, invalidate on hit
    // Peripheral (0xBFAF_xxxx) bypasses cache entirely (1-word read)
    // Tag=addr[31:9](23b), Index=addr[8:4](5b), WOff=addr[3:2](2b)
    // =========================================================================
    localparam CACHE_SIZE = 32;
    localparam IDX_W  = 5;
    localparam TAG_W  = 23;
    localparam BLK_W  = `CACHE_BLK_LEN;

    reg [TAG_W-1:0]     cache_tag   [CACHE_SIZE-1:0];
    reg                 cache_valid [CACHE_SIZE-1:0];
    reg [BLK_W*32-1:0] cache_data  [CACHE_SIZE-1:0];

    // Address decomposition
    wire [1:0]       addr_woff  = data_addr[3:2];
    wire [IDX_W-1:0] addr_index = data_addr[IDX_W+3:4];
    wire [TAG_W-1:0] addr_tag   = data_addr[31:IDX_W+4];
    wire is_cacheable = (data_addr[31:16] != 16'hBFAF);

    // Cache hit (only for cacheable addresses)
    wire rd_cache_hit = (|data_ren) & is_cacheable &
                        cache_valid[addr_index] & (cache_tag[addr_index] == addr_tag);
    wire wr_cache_hit = (|data_wen) & is_cacheable &
                        cache_valid[addr_index] & (cache_tag[addr_index] == addr_tag);

    // Word select from cache line
    reg [31:0] hit_word;
    always @(*) begin
        case (addr_woff)
            2'd0: hit_word = cache_data[addr_index][ 31:  0];
            2'd1: hit_word = cache_data[addr_index][ 63: 32];
            2'd2: hit_word = cache_data[addr_index][ 95: 64];
            2'd3: hit_word = cache_data[addr_index][127: 96];
        endcase
    end

    // ========== Read Path ==========
    localparam R_IDLE        = 2'b00;
    localparam R_REFILL_REQ  = 2'b01;
    localparam R_REFILL_WAIT = 2'b10;
    reg [1:0] r_state, r_nstat;
    // Testbench compatibility aliases
    wire [1:0] current_state = r_state;
    localparam REFILL = R_REFILL_REQ;

    reg [31:0] refill_addr;
    reg        rf_is_cacheable;
    wire [IDX_W-1:0] rf_index = refill_addr[IDX_W+3:4];
    wire [TAG_W-1:0] rf_tag   = refill_addr[31:IDX_W+4];
    wire [1:0]       rf_woff  = refill_addr[3:2];

    reg [BLK_W*32-1:0] refill_buf;
    reg [2:0]           refill_cnt;
    // Peripheral: 1 word, cacheable memory: BLK_W words
    wire refill_done = rf_is_cacheable ? (refill_cnt == BLK_W) : (refill_cnt == 3'd1);

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        r_state <= !cpu_rstn ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:        r_nstat = ((|data_ren) & !rd_cache_hit) ? R_REFILL_REQ : R_IDLE;
            R_REFILL_REQ:  r_nstat = dev_rrdy      ? R_REFILL_WAIT : R_REFILL_REQ;
            R_REFILL_WAIT: r_nstat = refill_done    ? R_IDLE        : R_REFILL_WAIT;
            default:       r_nstat = R_IDLE;
        endcase
    end

    // Latch refill address & cacheability
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            refill_addr     <= 32'h0;
            rf_is_cacheable <= 1'b0;
        end else if (r_state == R_IDLE && (|data_ren) && !rd_cache_hit) begin
            refill_addr     <= data_addr;
            rf_is_cacheable <= is_cacheable;
        end
    end

    // Refill word collection
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            refill_cnt <= 3'd0;
            refill_buf <= 128'h0;
        end else if (r_state == R_IDLE) begin
            refill_cnt <= 3'd0;
        end else if (r_state == R_REFILL_WAIT && dev_rvalid && !refill_done) begin
            case (refill_cnt)
                3'd0: refill_buf[ 31:  0] <= dev_rdata;
                3'd1: refill_buf[ 63: 32] <= dev_rdata;
                3'd2: refill_buf[ 95: 64] <= dev_rdata;
                3'd3: refill_buf[127: 96] <= dev_rdata;
            endcase
            refill_cnt <= refill_cnt + 3'd1;
        end
    end

    // Cache fill (only for cacheable) & store invalidation
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin : dc_reset
            integer i;
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_tag[i]   <= {TAG_W{1'b0}};
                cache_data[i]  <= 128'h0;
            end
        end else if (r_state == R_REFILL_WAIT && refill_done && rf_is_cacheable) begin
            cache_valid[rf_index] <= 1'b1;
            cache_tag[rf_index]   <= rf_tag;
            cache_data[rf_index]  <= refill_buf;
        end else if (wr_cache_hit) begin
            cache_valid[addr_index] <= 1'b0;
        end
    end

    // Read output to CPU
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_valid <= 1'b0;
            data_rdata <= 32'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (rd_cache_hit) begin
                        data_valid <= 1'b1;
                        data_rdata <= hit_word;
                    end else begin
                        data_valid <= 1'b0;
                    end
                end
                R_REFILL_WAIT: begin
                    if (refill_done) begin
                        data_valid <= 1'b1;
                        if (rf_is_cacheable) begin
                            case (rf_woff)
                                2'd0: data_rdata <= refill_buf[ 31:  0];
                                2'd1: data_rdata <= refill_buf[ 63: 32];
                                2'd2: data_rdata <= refill_buf[ 95: 64];
                                2'd3: data_rdata <= refill_buf[127: 96];
                            endcase
                        end else begin
                            data_rdata <= refill_buf[31:0];
                        end
                    end else begin
                        data_valid <= 1'b0;
                    end
                end
                default: data_valid <= 1'b0;
            endcase
        end
    end

    // Read bus interface (line-aligned for cacheable, word-aligned for peripheral)
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            cpu_ren   <= 4'h0;
            cpu_raddr <= 32'h0;
        end else begin
            if (r_state == R_REFILL_REQ && dev_rrdy) begin
                cpu_ren   <= 4'hF;
                cpu_raddr <= rf_is_cacheable ? {refill_addr[31:4], 4'b0000} : refill_addr;
            end else begin
                cpu_ren   <= 4'h0;
            end
        end
    end

    // ========== Write Path (write-through, pass to bus via FIFO) ==========
    // Optimized: 2-cycle store (W_IDLE→W_DONE→W_IDLE) when bus ready
    localparam W_IDLE = 2'b00;
    localparam W_WAIT = 2'b01;   // waiting for dev_wrdy (FIFO not empty)
    localparam W_DONE = 2'b10;   // cpu_wen pulsed, signal completion
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        w_state <= !cpu_rstn ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_DONE : W_WAIT) : W_IDLE;
            W_WAIT:  w_nstat = dev_wrdy ? W_DONE : W_WAIT;
            W_DONE:  w_nstat = W_IDLE;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;
                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;
                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_WAIT: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_DONE: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= 1'b1;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        r_state <= !cpu_rstn ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        w_state <= !cpu_rstn ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;
                        
                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule
