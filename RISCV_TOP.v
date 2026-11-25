module RISCV_TOP #(
    parameter BLOCK_SIZE   = 64,
    parameter CACHE_SIZE   = 1,
    parameter NUM_WAYS     = 4,
    parameter EVICT_POLICY = 0
)(
    input iClk,
    input iRstN
);
    localparam NOP = 32'h00000013;

    reg  [31:0] rPC;
    wire [31:0] wPCPlus4F;
    assign wPCPlus4F = rPC + 32'd4;

    wire [31:0] wInstrF;
    INSTRUCTION_MEMORY if_stage (
        .iRdAddr(rPC),
        .oInstr(wInstrF)
    );

    reg [31:0] wInstr;
    reg [31:0] wPc;

    wire [6:0]  wOpcodeD = wInstr[6:0];
    wire [4:0]  wRdD     = wInstr[11:7];
    wire [2:0]  wFunct3D = wInstr[14:12];
    wire [4:0]  wRs1D    = wInstr[19:15];
    wire [4:0]  wRs2D    = wInstr[24:20];
    wire [6:0]  wFunct7D = wInstr[31:25];
    wire [31:0] wImmD;
    wire        wIdIsStore;
    assign wIdIsStore = (wOpcodeD == 7'b0100011);

    IMM_GEN id_stage (
        .iInstr(wInstr),
        .oImm(wImmD)
    );

    wire       wLuiD, wPcSrcD, wMemRdD, wMemWrD, wMemtoRegD, wAluSrc1D, wAluSrc2D, wRegWriteD, wBranchD, wJumpD;
    wire [2:0] wAluOpD;

    CONTROL control (
        .iOpcode(wOpcodeD),
        .oLui(wLuiD),
        .oPcSrc(wPcSrcD),
        .oMemRd(wMemRdD),
        .oMemWr(wMemWrD),
        .oAluOp(wAluOpD),
        .oMemtoReg(wMemtoRegD),
        .oAluSrc1(wAluSrc1D),
        .oAluSrc2(wAluSrc2D),
        .oRegWrite(wRegWriteD),
        .oBranch(wBranchD),
        .oJump(wJumpD)
    );

    wire [31:0] wRs1DataD_raw, wRs2DataD_raw;
    wire [31:0] wRs1DataD, wRs2DataD;
    wire [31:0] wWriteBackW;
    wire        wRegWriteW;
    wire [4:0]  wRdW;

    REGISTER register (
        .iClk(iClk),
        .iRstN(iRstN),
        .iWriteEn(wRegWriteW),
        .iRdAddr(wRdW),
        .iRs1Addr(wRs1D),
        .iRs2Addr(wRs2D),
        .iWriteData(wWriteBackW),
        .oRs1Data(wRs1DataD_raw),
        .oRs2Data(wRs2DataD_raw)
    );

    wire wStallPC;
    wire wStallIFID;
    wire wFlushIDEX;

    reg [31:0] rPcE, rRs1DataE, rRs2DataE, rImmE;
    reg [4:0]  rRs1E, rRs2E, rRdE;
    reg [2:0]  rFunct3E, rAluOpE;
    reg [6:0]  rFunct7E, rOpcodeE;
    reg        rLuiE, rPcSrcE, rMemRdE, rMemWrE, rMemtoRegE, rAluSrc1E, rAluSrc2E, rRegWriteE, rBranchE, rJumpE;

    HAZARD_DETECTION hd (
        .iIdRs1(wRs1D),
        .iIdRs2(wRs2D),
        .iExRd(rRdE),
        .iExMemRead(rMemRdE),
        .iIdIsStore(wIdIsStore),
        .oStallPC(wStallPC),
        .oStallIFID(wStallIFID),
        .oFlushIDEX(wFlushIDEX)
    );

    wire [1:0] wForwardAE;
    wire [1:0] wForwardBE;

    reg [4:0]  rRdM;
    reg        rRegWriteM;
    reg [4:0]  rRdW_reg;
    reg        rRegWriteW_reg;

    assign wRdW = rRdW_reg;
    assign wRegWriteW = rRegWriteW_reg;

    assign wRs1DataD = (wRegWriteW && (wRdW != 5'd0) && (wRdW == wRs1D)) ? wWriteBackW : wRs1DataD_raw;
    assign wRs2DataD = (wRegWriteW && (wRdW != 5'd0) && (wRdW == wRs2D)) ? wWriteBackW : wRs2DataD_raw;

    FORWARDING_UNIT fwd (
        .iExRs1(rRs1E),
        .iExRs2(rRs2E),
        .iMemRd(rRdM),
        .iWbRd(rRdW_reg),
        .iMemRegWrite(rRegWriteM),
        .iWbRegWrite(rRegWriteW_reg),
        .oForwardA(wForwardAE),
        .oForwardB(wForwardBE)
    );

    function [31:0] fwd_mux;
        input [1:0]  sel;
        input [31:0] reg_data;
        input [31:0] mem_data;
        input [31:0] wb_data;
        begin
            case (sel)
                2'b10: fwd_mux = mem_data;
                2'b01: fwd_mux = wb_data;
                default: fwd_mux = reg_data;
            endcase
        end
    endfunction

    wire [31:0] wAluAE;
    wire [31:0] wAluBE;
    wire [3:0]  wAluCtrlE;
    wire [31:0] wAluOutE;
    wire        wZeroE;
    wire [31:0] wBranchTargetE;
    wire [31:0] wJumpTargetE;
    wire        wTakeBranchE;
    wire        wSignedLessE;
    wire        wUnsignedLessE;

    reg [31:0] rPcM, rAluOutM, rStoreDataM, rImmM, rBranchTargetM;
    reg [2:0]  rFunct3M;
    reg        rLuiM, rMemRdM, rMemWrM, rMemtoRegM, rRegWriteM_local, rBranchTakenM, rJumpM;
    reg [4:0]  rStoreRs2M;

    wire [31:0] wMemWriteDataM;
    wire [31:0] wMemReadDataM;
    wire        wTakeCtrlM;
    reg  [31:0] rPcW, rAluOutW, rMemReadDataW, rImmW;
    reg         rLuiW, rMemtoRegW, rJumpW;

    wire [31:0] wResultM;

    assign wWriteBackW =
        rJumpW     ? (rPcW + 32'd4) :
        rLuiW      ? rImmW :
        rMemtoRegW ? rMemReadDataW :
                     rAluOutW;

    assign wResultM =
        rJumpM     ? (rPcM + 32'd4) :
        rLuiM      ? rImmM :
        rMemtoRegM ? wMemReadDataM :
                     rAluOutM;

    wire [31:0] wRs1ForwardE;
    wire [31:0] wRs2ForwardE;
    assign wRs1ForwardE = fwd_mux(wForwardAE, rRs1DataE, wResultM, wWriteBackW);
    assign wRs2ForwardE = fwd_mux(wForwardBE, rRs2DataE, wResultM, wWriteBackW);

    assign wAluAE = rAluSrc1E ? rPcE : wRs1ForwardE;
    assign wAluBE = rAluSrc2E ? rImmE : wRs2ForwardE;

    ALU_CONTROL alu_control (
        .iAluOp(rAluOpE),
        .iFunct3(rFunct3E),
        .iFunct7(rFunct7E),
        .oAluCtrl(wAluCtrlE)
    );

    ALU alu (
        .iDataA(wAluAE),
        .iDataB(wAluBE),
        .iAluCtrl(wAluCtrlE),
        .oData(wAluOutE),
        .oZero(wZeroE)
    );

    assign wBranchTargetE = rPcE + rImmE;
    assign wJumpTargetE = rPcSrcE ? ((wRs1ForwardE + rImmE) & ~32'd1) : wBranchTargetE;
    assign wSignedLessE   = ($signed(wRs1ForwardE) < $signed(wRs2ForwardE));
    assign wUnsignedLessE = (wRs1ForwardE < wRs2ForwardE);
    assign wTakeBranchE = rBranchE & (
        ((rFunct3E == 3'b000) &&  wZeroE)         |
        ((rFunct3E == 3'b001) && !wZeroE)         |
        ((rFunct3E == 3'b100) &&  wSignedLessE)   |
        ((rFunct3E == 3'b101) && !wSignedLessE)   |
        ((rFunct3E == 3'b110) &&  wUnsignedLessE) |
        ((rFunct3E == 3'b111) && !wUnsignedLessE)
    );

    assign wMemWriteDataM =
        (rMemWrM && rRegWriteW_reg && (rRdW_reg != 5'd0) && (rRdW_reg == rStoreRs2M))
            ? wWriteBackW
            : rStoreDataM;

    wire wMemStall;

    MEM #(
        .BLOCK_SIZE(BLOCK_SIZE),
        .CACHE_SIZE(CACHE_SIZE),
        .NUM_WAYS(NUM_WAYS),
        .EVICT_POLICY(EVICT_POLICY)
    ) mem_stage (
        .iClk(iClk),
        .iRstN(iRstN),
        .iAddress(rAluOutM),
        .iWriteData(wMemWriteDataM),
        .iFunct3(rFunct3M),
        .iMemWrite(rMemWrM),
        .iMemRead(rMemRdM),
        .oReadData(wMemReadDataM),
        .oStall(wMemStall)
    );

    assign wTakeCtrlM = rBranchTakenM | rJumpM;

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            rPC <= 32'd0;

            wInstr <= NOP;
            wPc    <= 32'd0;

            rPcE <= 32'd0;
            rRs1DataE <= 32'd0;
            rRs2DataE <= 32'd0;
            rImmE <= 32'd0;
            rRs1E <= 5'd0;
            rRs2E <= 5'd0;
            rRdE <= 5'd0;
            rFunct3E <= 3'd0;
            rAluOpE <= 3'd0;
            rFunct7E <= 7'd0;
            rOpcodeE <= 7'd0;
            rLuiE <= 1'b0;
            rPcSrcE <= 1'b0;
            rMemRdE <= 1'b0;
            rMemWrE <= 1'b0;
            rMemtoRegE <= 1'b0;
            rAluSrc1E <= 1'b0;
            rAluSrc2E <= 1'b0;
            rRegWriteE <= 1'b0;
            rBranchE <= 1'b0;
            rJumpE <= 1'b0;

            rPcM <= 32'd0;
            rAluOutM <= 32'd0;
            rStoreDataM <= 32'd0;
            rImmM <= 32'd0;
            rBranchTargetM <= 32'd0;
            rFunct3M <= 3'd0;
            rRdM <= 5'd0;
            rLuiM <= 1'b0;
            rMemRdM <= 1'b0;
            rMemWrM <= 1'b0;
            rMemtoRegM <= 1'b0;
            rRegWriteM <= 1'b0;
            rRegWriteM_local <= 1'b0;
            rBranchTakenM <= 1'b0;
            rJumpM <= 1'b0;
            rStoreRs2M <= 5'd0;

            rPcW <= 32'd0;
            rAluOutW <= 32'd0;
            rMemReadDataW <= 32'd0;
            rImmW <= 32'd0;
            rRdW_reg <= 5'd0;
            rLuiW <= 1'b0;
            rMemtoRegW <= 1'b0;
            rJumpW <= 1'b0;
            rRegWriteW_reg <= 1'b0;
        end else begin
            if (wMemStall) begin
                // Hold the pipeline while the cache is servicing a miss/write-back/prefetch.
            end else begin
            if (!wStallPC) begin
                if (wTakeCtrlM)
                    rPC <= rBranchTargetM;
                else
                    rPC <= wPCPlus4F;
            end

            if (wTakeCtrlM) begin
                wInstr <= NOP;
                wPc    <= 32'd0;
            end else if (!wStallIFID) begin
                wInstr <= wInstrF;
                wPc    <= rPC;
            end

            if (wFlushIDEX || wTakeCtrlM) begin
                rPcE <= 32'd0;
                rRs1DataE <= 32'd0;
                rRs2DataE <= 32'd0;
                rImmE <= 32'd0;
                rRs1E <= 5'd0;
                rRs2E <= 5'd0;
                rRdE <= 5'd0;
                rFunct3E <= 3'd0;
                rAluOpE <= 3'd0;
                rFunct7E <= 7'd0;
                rOpcodeE <= 7'd0;
                rLuiE <= 1'b0;
                rPcSrcE <= 1'b0;
                rMemRdE <= 1'b0;
                rMemWrE <= 1'b0;
                rMemtoRegE <= 1'b0;
                rAluSrc1E <= 1'b0;
                rAluSrc2E <= 1'b0;
                rRegWriteE <= 1'b0;
                rBranchE <= 1'b0;
                rJumpE <= 1'b0;
            end else begin
                rPcE <= wPc;
                rRs1DataE <= wRs1DataD;
                rRs2DataE <= wRs2DataD;
                rImmE <= wImmD;
                rRs1E <= wRs1D;
                rRs2E <= wRs2D;
                rRdE <= wRdD;
                rFunct3E <= wFunct3D;
                rAluOpE <= wAluOpD;
                rFunct7E <= wFunct7D;
                rOpcodeE <= wOpcodeD;
                rLuiE <= wLuiD;
                rPcSrcE <= wPcSrcD;
                rMemRdE <= wMemRdD;
                rMemWrE <= wMemWrD;
                rMemtoRegE <= wMemtoRegD;
                rAluSrc1E <= wAluSrc1D;
                rAluSrc2E <= wAluSrc2D;
                rRegWriteE <= wRegWriteD;
                rBranchE <= wBranchD;
                rJumpE <= wJumpD;
            end

                        if (wTakeCtrlM) begin
                rPcM <= 32'd0;
                rAluOutM <= 32'd0;
                rStoreDataM <= 32'd0;
                rImmM <= 32'd0;
                rBranchTargetM <= 32'd0;
                rFunct3M <= 3'd0;
                rRdM <= 5'd0;
                rLuiM <= 1'b0;
                rMemRdM <= 1'b0;
                rMemWrM <= 1'b0;
                rMemtoRegM <= 1'b0;
                rRegWriteM <= 1'b0;
                rRegWriteM_local <= 1'b0;
                rBranchTakenM <= 1'b0;
                rJumpM <= 1'b0;
                rStoreRs2M <= 5'd0;
            end else begin
                rPcM <= rPcE;
                rAluOutM <= wAluOutE;
                rStoreDataM <= wRs2ForwardE;
                rImmM <= rImmE;
                rBranchTargetM <= rJumpE ? wJumpTargetE : wBranchTargetE;
                rFunct3M <= rFunct3E;
                rRdM <= rRdE;
                rLuiM <= rLuiE;
                rMemRdM <= rMemRdE;
                rMemWrM <= rMemWrE;
                rMemtoRegM <= rMemtoRegE;
                rRegWriteM <= rRegWriteE;
                rRegWriteM_local <= rRegWriteE;
                rBranchTakenM <= wTakeBranchE;
                rJumpM <= rJumpE;
                rStoreRs2M <= rRs2E;
            end

            rPcW <= rPcM;
            rAluOutW <= rAluOutM;
            rMemReadDataW <= wMemReadDataM;
            rImmW <= rImmM;
            rRdW_reg <= rRdM;
            rLuiW <= rLuiM;
            rMemtoRegW <= rMemtoRegM;
            rJumpW <= rJumpM;
            rRegWriteW_reg <= rRegWriteM_local;
            end
        end
    end
endmodule