module HAZARD_DETECTION (
    input [4:0] iIdRs1,
    input [4:0] iIdRs2,
    input [4:0] iExRd,
    input       iExMemRead,
    input       iIdIsStore,
    output reg  oStallPC,
    output reg  oStallIFID,
    output reg  oFlushIDEX
);
    always @(*) begin
        oStallPC   = 1'b0;
        oStallIFID = 1'b0;
        oFlushIDEX = 1'b0;

        if (iExMemRead && (iExRd != 5'd0) &&
            ((iExRd == iIdRs1) || ((iExRd == iIdRs2) && !iIdIsStore))) begin
            oStallPC   = 1'b1;
            oStallIFID = 1'b1;
            oFlushIDEX = 1'b1;
        end
    end
endmodule
