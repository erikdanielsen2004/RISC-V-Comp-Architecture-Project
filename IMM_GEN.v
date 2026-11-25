module IMM_GEN(
    input  wire [31:0] iInstr,
    output reg  [31:0] oImm
);
    wire [6:0] opcode = iInstr[6:0];
    always @(*) begin
        case (opcode)
            7'b0010011,
            7'b0000011,
            7'b1100111: oImm = {{20{iInstr[31]}}, iInstr[31:20]};
            7'b0100011: oImm = {{20{iInstr[31]}}, iInstr[31:25], iInstr[11:7]};
            7'b1100011: oImm = {{19{iInstr[31]}}, iInstr[31], iInstr[7], iInstr[30:25], iInstr[11:8], 1'b0};
            7'b0110111,
            7'b0010111: oImm = {iInstr[31:12], 12'b0};
            7'b1101111: oImm = {{11{iInstr[31]}}, iInstr[31], iInstr[19:12], iInstr[20], iInstr[30:21], 1'b0};
            default:    oImm = 32'd0;
        endcase
    end
endmodule
