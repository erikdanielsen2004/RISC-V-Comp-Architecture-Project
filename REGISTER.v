module REGISTER (
    input         iClk,
    input         iRstN,
    input         iWriteEn,
    input  [4:0]  iRdAddr,
    input  [4:0]  iRs1Addr,
    input  [4:0]  iRs2Addr,
    input  [31:0] iWriteData,
    output [31:0] oRs1Data,
    output [31:0] oRs2Data
);

    // IMPORTANT: autograder expects this exact name: registers
    reg [31:0] registers [0:31];
    integer i;

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else begin
            registers[0] <= 32'b0;
            if (iWriteEn && (iRdAddr != 5'd0))
                registers[iRdAddr] <= iWriteData;
        end
    end

    assign oRs1Data = (iRs1Addr == 5'd0) ? 32'b0 : registers[iRs1Addr];
    assign oRs2Data = (iRs2Addr == 5'd0) ? 32'b0 : registers[iRs2Addr];

endmodule