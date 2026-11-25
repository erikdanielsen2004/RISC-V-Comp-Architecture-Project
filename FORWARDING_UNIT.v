module FORWARDING_UNIT(
    input  wire [4:0] iExRs1,
    input  wire [4:0] iExRs2,
    input  wire [4:0] iMemRd,
    input  wire [4:0] iWbRd,
    input  wire       iMemRegWrite,
    input  wire       iWbRegWrite,
    output reg  [1:0] oForwardA,
    output reg  [1:0] oForwardB
);
    always @(*) begin
        oForwardA = 2'b00;
        oForwardB = 2'b00;

        if (iMemRegWrite && (iMemRd != 5'd0) && (iMemRd == iExRs1))
            oForwardA = 2'b10;
        else if (iWbRegWrite && (iWbRd != 5'd0) && (iWbRd == iExRs1))
            oForwardA = 2'b01;

        if (iMemRegWrite && (iMemRd != 5'd0) && (iMemRd == iExRs2))
            oForwardB = 2'b10;
        else if (iWbRegWrite && (iWbRd != 5'd0) && (iWbRd == iExRs2))
            oForwardB = 2'b01;
    end
endmodule
