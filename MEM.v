module MEM #(
    parameter BLOCK_SIZE   = 64,
    parameter CACHE_SIZE   = 1,
    parameter NUM_WAYS     = 4,
    parameter EVICT_POLICY = 0
)(
    input         iClk,
    input         iRstN,
    input  [31:0] iAddress,
    input  [31:0] iWriteData,
    input  [2:0]  iFunct3,
    input         iMemWrite,
    input         iMemRead,
    output [31:0] oReadData,
    output        oStall
);

    wire        wHit;
    wire        wMiss;
    wire        wMemRd;
    wire        wMemWr;
    wire [31:0] wMemRdAddr;
    wire [31:0] wMemWrAddr;
    wire [511:0] wMemWrData;
    wire [511:0] wMemRdData;
    wire        wMemReady;
    wire        wMemValid;
    wire [31:0] wDirectRead;

    CACHE #(
        .BLOCK_SIZE(BLOCK_SIZE),
        .CACHE_SIZE(CACHE_SIZE),
        .NUM_WAYS(NUM_WAYS),
        .EVICT_POLICY(EVICT_POLICY)
    ) cache (
        .i_clk(iClk),
        .i_rstn(iRstN),
        .i_read(iMemRead),
        .i_write(iMemWrite),
        .i_funct(iFunct3),
        .i_addr(iAddress),
        .i_cpu_data(iMemRead ? wDirectRead : iWriteData),
        .i_mem_ready(wMemReady),
        .i_mem_valid(wMemValid),
        .i_mem_rd_data(wMemRdData),
        .o_hit(wHit),
        .o_miss(wMiss),
        .o_mem_rd(wMemRd),
        .o_mem_wr(wMemWr),
        .o_cpu_data(oReadData),
        .o_mem_rd_addr(wMemRdAddr),
        .o_mem_wr_addr(wMemWrAddr),
        .o_mem_wr_data(wMemWrData)
    );

    DATA_MEMORY #(
        .BLOCK_SIZE(BLOCK_SIZE)
    ) data_memory (
        .iClk(iClk),
        .iRstN(iRstN),
        .iAddress(iAddress),
        .iWriteData(iWriteData),
        .iFunct3(iFunct3),
        .iMemWrite(1'b0),
        .iMemRead(iMemRead),
        .oReadData(wDirectRead),
        .iBlockRead(wMemRd),
        .iBlockWrite(wMemWr),
        .iBlockAddr(wMemRd ? wMemRdAddr : wMemWrAddr),
        .iBlockWriteData(wMemWrData),
        .oBlockReadData(wMemRdData),
        .oMemReady(wMemReady),
        .oMemValid(wMemValid)
    );

    assign oStall = wMiss;

endmodule
