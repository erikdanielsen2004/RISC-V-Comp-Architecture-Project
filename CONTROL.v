module CONTROL (
    input  [6:0] iOpcode,
    output reg   oLui,
    output reg   oPcSrc,
    output reg   oMemRd,
    output reg   oMemWr,
    output reg [2:0] oAluOp,
    output reg   oMemtoReg,
    output reg   oAluSrc1,
    output reg   oAluSrc2,
    output reg   oRegWrite,
    output reg   oBranch,
    output reg   oJump
);
    always @(*) begin
        oLui=0; oPcSrc=0; oMemRd=0; oMemWr=0; oAluOp=0;
        oMemtoReg=0; oAluSrc1=0; oAluSrc2=0;
        oRegWrite=0; oBranch=0; oJump=0;

        case (iOpcode)
            7'b0110011: begin oAluOp=3'b010; oRegWrite=1; end
            7'b0010011: begin oAluOp=3'b011; oAluSrc2=1; oRegWrite=1; end
            7'b0000011: begin oAluOp=3'b000; oAluSrc2=1; oMemRd=1; oMemtoReg=1; oRegWrite=1; end
            7'b0100011: begin oAluOp=3'b000; oAluSrc2=1; oMemWr=1; end
            7'b1100011: begin oAluOp=3'b001; oBranch=1; end
            7'b1101111: begin oJump=1; oRegWrite=1; end
            7'b1100111: begin oJump=1; oPcSrc=1; oAluSrc2=1; oRegWrite=1; end
            7'b0110111: begin oLui=1; oRegWrite=1; end
            7'b0010111: begin oAluSrc1=1; oAluSrc2=1; oRegWrite=1; end
            default: begin end
        endcase
    end
endmodule
