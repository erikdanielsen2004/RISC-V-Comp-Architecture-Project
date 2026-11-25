/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */
module CACHE #(
    parameter integer BLOCK_SIZE   = 64,
    parameter integer CACHE_SIZE   = 1,
    parameter integer NUM_WAYS     = 4,
    parameter integer EVICT_POLICY = 0,
    parameter integer PREFETCH     = 1,
    parameter integer WRITE_BACK   = 1
)(
    input i_clk,
    input i_rstn,

    input i_read,
    input i_write,
    input [2:0] i_funct,
    input [31:0] i_addr,
    input [31:0] i_cpu_data,

    input i_mem_ready,
    input i_mem_valid,
    input [511:0] i_mem_rd_data,

    output reg o_hit,
    output reg o_miss,
    output reg o_mem_rd,
    output reg o_mem_wr,
    output reg [31:0] o_cpu_data,
    output reg [31:0] o_mem_rd_addr,
    output reg [31:0] o_mem_wr_addr,
    output reg [511:0] o_mem_wr_data
);

    localparam integer SETS = (CACHE_SIZE * 1024) / (BLOCK_SIZE * NUM_WAYS);
    localparam integer OFFSET_BITS = clog2_const(BLOCK_SIZE);
    localparam integer INDEX_BITS = clog2_const(SETS);
    localparam integer TAG_BITS = 32 - OFFSET_BITS - INDEX_BITS;

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_MEM = 2'd1;

    reg [TAG_BITS-1:0] rTag   [0:SETS-1][0:NUM_WAYS-1];
    reg rValid [0:SETS-1][0:NUM_WAYS-1];
    reg rDirty [0:SETS-1][0:NUM_WAYS-1];
    reg [511:0] rData [0:SETS-1][0:NUM_WAYS-1];
    reg [31:0] rLRU  [0:SETS-1][0:NUM_WAYS-1];

    reg [1:0]  rState;
    reg rRead;
    reg rWrite;
    reg [2:0]  rFunct;
    reg [31:0] rAddr;
    reg [31:0] rWriteData;
    reg [31:0] rCpuData;
    reg [31:0] rMemAddr;
    reg [31:0] rPrefetchAddr;
    reg rLruUpdate;

    integer i, s, w, b;

    function integer clog2_const;
        input integer value;
        integer tmp;
        begin
            tmp = value - 1;
            clog2_const = 0;
            while (tmp > 0) begin
                clog2_const = clog2_const + 1;
                tmp = tmp >> 1;
            end
        end
    endfunction

    function [31:0] base_addr;
        input [31:0] addr;
        begin
            base_addr = addr & ~((32'd1 << OFFSET_BITS) - 32'd1);
        end
    endfunction

    function [31:0] get_set32;
        input [31:0] addr;
        begin
            if (INDEX_BITS == 0)
                get_set32 = 32'd0;
            else
                get_set32 = (addr >> OFFSET_BITS) & ((32'd1 << INDEX_BITS) - 32'd1);
        end
    endfunction

    function [TAG_BITS-1:0] get_tag;
        input [31:0] addr;
        begin
            get_tag = addr[31:(OFFSET_BITS + INDEX_BITS)];
        end
    endfunction

    function [31:0] get_offset32;
        input [31:0] addr;
        begin
            get_offset32 = addr & ((32'd1 << OFFSET_BITS) - 32'd1);
        end
    endfunction

    function [31:0] make_addr;
        input [TAG_BITS-1:0] tag;
        input [31:0] setidx;
        begin
            make_addr = ({ {(32-TAG_BITS){1'b0}}, tag } << (OFFSET_BITS + INDEX_BITS)) |
                        (setidx << OFFSET_BITS);
        end
    endfunction

    function [31:0] read_bytes;
        input [511:0] block;
        input [31:0]  offset;
        input [2:0]   funct;
        reg [31:0] val;
        integer n;
        begin
            val = 32'd0;
            for (n = 0; n < 4; n = n + 1) begin
                if ((n < (32'd1 << (funct & 3))) && ((offset + n) < BLOCK_SIZE))
                    val = val | ({24'd0, block[((offset+n)*8) +: 8]} << (8*n));
            end
            read_bytes = val;
        end
    endfunction

    task write_bytes;
        input [31:0] setidx;
        input [31:0] wayidx;
        input [31:0] offset;
        input [2:0]  funct;
        input [31:0] value;
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1) begin
                if ((n < (32'd1 << (funct & 3))) && ((offset + n) < BLOCK_SIZE))
                    rData[setidx][wayidx][((offset+n)*8) +: 8] <= value[(8*n) +: 8];
            end
            rDirty[setidx][wayidx] <= 1'b1;
        end
    endtask

    task update_lru;
        input [31:0] setidx;
        input [31:0] wayidx;
        reg [31:0] prev;
        integer ww;
        begin
            prev = rLRU[setidx][wayidx];
            for (ww = 0; ww < NUM_WAYS; ww = ww + 1) begin
                if ((ww != wayidx) && (rLRU[setidx][ww] <= prev)) begin
                    if (rLRU[setidx][ww] < (NUM_WAYS - 1))
                        rLRU[setidx][ww] <= rLRU[setidx][ww] + 1;
                    else
                        rLRU[setidx][ww] <= NUM_WAYS - 1;
                end
            end
            rLRU[setidx][wayidx] <= 32'd0;
        end
    endtask

    task update_mru_for_prefetch;
        input [31:0] setidx;
        input [31:0] wayidx;
        begin
            rLRU[setidx][wayidx] <= NUM_WAYS - 1;
        end
    endtask

    task choose_victim;
        input  [31:0] setidx;
        output [31:0] victim;
        integer ww;
        reg found;
        begin
            victim = 32'd0;
            found = 1'b0;
            for (ww = 0; ww < NUM_WAYS; ww = ww + 1) begin
                if (!found && !rValid[setidx][ww]) begin
                    victim = ww;
                    found = 1'b1;
                end
            end
            if (!found) begin
                victim = 32'd0;
                for (ww = 1; ww < NUM_WAYS; ww = ww + 1) begin
                    if (rLRU[setidx][ww] > rLRU[setidx][victim])
                        victim = ww;
                end
            end
        end
    endtask

    task find_hit;
        input  [31:0] setidx;
        input  [TAG_BITS-1:0] tag;
        output [31:0] wayidx;
        output hit;
        integer ww;
        begin
            wayidx = 32'd0;
            hit = 1'b0;
            for (ww = 0; ww < NUM_WAYS; ww = ww + 1) begin
                if (!hit && rValid[setidx][ww] && (rTag[setidx][ww] == tag)) begin
                    wayidx = ww;
                    hit = 1'b1;
                end
            end
        end
    endtask

    task maybe_writeback;
        input [31:0] setidx;
        input [31:0] wayidx;
        begin
            if (WRITE_BACK && rDirty[setidx][wayidx]) begin
                o_mem_wr      <= 1'b1;
                o_mem_wr_addr <= make_addr(rTag[setidx][wayidx], setidx);
                o_mem_wr_data <= rData[setidx][wayidx];
                rDirty[setidx][wayidx] <= 1'b0;
            end
        end
    endtask

    task insert_block;
        input [31:0] setidx;
        input [31:0] wayidx;
        input [TAG_BITS-1:0] tag;
        input [511:0] block;
        begin
            rTag[setidx][wayidx]   <= tag;
            rData[setidx][wayidx]  <= block;
            rValid[setidx][wayidx] <= 1'b1;
            rDirty[setidx][wayidx] <= 1'b0;
        end
    endtask

    reg [31:0] tSet;
    reg [31:0] tOffset;
    reg [31:0] tWay;
    reg [31:0] tVictim;
    reg [31:0] tMemSet;
    reg [31:0] tMemOffset;
    reg [TAG_BITS-1:0] tTag;
    reg [TAG_BITS-1:0] tMemTag;
    reg tHit;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            rState <= S_IDLE;
            rRead <= 1'b0;
            rWrite <= 1'b0;
            rFunct <= 3'd0;
            rAddr <= 32'd0;
            rWriteData <= 32'd0;
            rCpuData <= 32'd0;
            rMemAddr <= 32'd0;
            rPrefetchAddr <= 32'd0;
            rLruUpdate <= 1'b1;

            o_hit <= 1'b0;
            o_miss <= 1'b0;
            o_mem_rd <= 1'b0;
            o_mem_wr <= 1'b0;
            o_cpu_data <= 32'd0;
            o_mem_rd_addr <= 32'd0;
            o_mem_wr_addr <= 32'd0;
            o_mem_wr_data <= 512'd0;

            for (s = 0; s < SETS; s = s + 1) begin
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    rTag[s][w] <= {TAG_BITS{1'b0}};
                    rValid[s][w] <= 1'b0;
                    rDirty[s][w] <= 1'b0;
                    rData[s][w] <= 512'd0;
                    rLRU[s][w] <= 32'd0;
                end
            end
        end else begin
            o_mem_wr <= 1'b0;
            o_mem_wr_addr <= 32'd0;
            o_mem_wr_data <= 512'd0;

            if (rState == S_IDLE) begin
                o_hit <= 1'b0;
                o_miss <= 1'b0;
                o_cpu_data <= 32'd0;
                o_mem_rd <= 1'b0;
                o_mem_rd_addr <= 32'd0;
                rLruUpdate <= 1'b1;

                if (i_read || i_write) begin
                    tSet = get_set32(i_addr);
                    tOffset = get_offset32(i_addr);
                    tTag = get_tag(i_addr);
                    find_hit(tSet, tTag, tWay, tHit);

                    rRead <= i_read;
                    rWrite <= i_write;
                    rFunct <= i_funct;
                    rAddr <= i_addr;
                    rWriteData <= i_cpu_data;

                    if (tHit) begin
                        o_hit <= 1'b1;
                        o_miss <= 1'b0;
                        if (i_read) begin
                            o_cpu_data <= read_bytes(rData[tSet][tWay], tOffset, i_funct);
                        end else begin
                            write_bytes(tSet, tWay, tOffset, i_funct, i_cpu_data);
                        end
                        update_lru(tSet, tWay);
                    end else begin
                        o_hit <= 1'b0;
                        o_miss <= 1'b1;
                        o_mem_rd <= 1'b1;
                        o_mem_rd_addr <= base_addr(i_addr);
                        rMemAddr <= base_addr(i_addr);
                        rPrefetchAddr <= base_addr(i_addr) + BLOCK_SIZE;
                        rState <= S_MEM;
                    end
                end
            end

            if (rState == S_MEM || ((rState == S_IDLE) && (i_read || i_write) && !tHit)) begin
                if (i_mem_ready && i_mem_valid) begin
                    tMemSet = get_set32(o_mem_rd_addr);
                    tMemOffset = get_offset32(rAddr);
                    tMemTag = get_tag(o_mem_rd_addr);
                    choose_victim(tMemSet, tVictim);
                    maybe_writeback(tMemSet, tVictim);
                    rValid[tMemSet][tVictim] <= 1'b0;
                    insert_block(tMemSet, tVictim, tMemTag, i_mem_rd_data);

                    if (rLruUpdate) begin
                        if (rRead) begin
                            rCpuData <= read_bytes(i_mem_rd_data, tMemOffset, rFunct);
                        end else if (rWrite) begin
                            for (b = 0; b < 4; b = b + 1) begin
                                if ((b < (32'd1 << (rFunct & 3))) && ((tMemOffset + b) < BLOCK_SIZE))
                                    rData[tMemSet][tVictim][((tMemOffset+b)*8) +: 8] <= rWriteData[(8*b) +: 8];
                            end
                            rDirty[tMemSet][tVictim] <= 1'b1;
                        end
                        update_lru(tMemSet, tVictim);

                        if (PREFETCH) begin
                            o_mem_rd_addr <= rPrefetchAddr;
                            rMemAddr <= 32'd0;
                            rLruUpdate <= 1'b0;
                            rState <= S_MEM;
                            o_miss <= 1'b1;
                            o_mem_rd <= 1'b1;
                            o_hit <= 1'b0;
                        end else begin
                            rState <= S_IDLE;
                            o_miss <= 1'b0;
                            o_mem_rd <= 1'b0;
                            rMemAddr <= 32'd0;
                            rPrefetchAddr <= 32'd0;
                            o_cpu_data <= (rRead) ? read_bytes(i_mem_rd_data, tMemOffset, rFunct) : 32'd0;
                        end
                    end else begin
                        update_mru_for_prefetch(tMemSet, tVictim);
                        rState <= S_IDLE;
                        o_miss <= 1'b0;
                        o_mem_rd <= 1'b0;
                        rMemAddr <= 32'd0;
                        rPrefetchAddr <= 32'd0;
                        o_cpu_data <= rCpuData;
                        rLruUpdate <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
/* verilator lint_on BLKSEQ */
/* verilator lint_on WIDTH */