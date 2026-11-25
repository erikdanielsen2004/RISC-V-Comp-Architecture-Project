module ALU_CONTROL (
    input  [2:0] iAluOp,
    input  [2:0] iFunct3,
    input  [6:0] iFunct7,
    output [3:0] oAluCtrl
);

    localparam ADD  = 4'b0000;
    localparam SLL  = 4'b0001;
    localparam SLT  = 4'b0010;
    localparam SLTU = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam OR   = 4'b0110;
    localparam AND  = 4'b0111;

    localparam SUB  = 4'b1000;
    localparam SRL  = 4'b1001;
    localparam BLT  = 4'b1010;
    localparam BLTU = 4'b1011;
    localparam BNE  = 4'b1100;
    localparam SRA  = 4'b1101;
    localparam BGE  = 4'b1110;
    localparam BGEU = 4'b1111;

    reg [3:0] rCtrl;

    always @(*) begin
        rCtrl = ADD;

        case (iAluOp)
            3'b000: rCtrl = ADD;

            3'b001: begin
                case (iFunct3)
                    3'b000: rCtrl = SUB;   // BEQ
                    3'b001: rCtrl = BNE;
                    3'b100: rCtrl = BLT;
                    3'b101: rCtrl = BGE;
                    3'b110: rCtrl = BLTU;
                    3'b111: rCtrl = BGEU;
                    default: rCtrl = SUB;
                endcase
            end

            3'b010: begin
                case (iFunct3)
                    3'b000: rCtrl = (iFunct7[5]) ? SUB : ADD;
                    3'b001: rCtrl = SLL;
                    3'b010: rCtrl = SLT;
                    3'b011: rCtrl = SLTU;
                    3'b100: rCtrl = XOR;
                    3'b101: rCtrl = (iFunct7[5]) ? SRA : SRL;
                    3'b110: rCtrl = OR;
                    3'b111: rCtrl = AND;
                    default: rCtrl = ADD;
                endcase
            end

            3'b011: begin
                case (iFunct3)
                    3'b000: rCtrl = ADD;
                    3'b001: rCtrl = SLL;
                    3'b010: rCtrl = SLT;
                    3'b011: rCtrl = SLTU;
                    3'b100: rCtrl = XOR;
                    3'b101: rCtrl = (iFunct7[5]) ? SRA : SRL;
                    3'b110: rCtrl = OR;
                    3'b111: rCtrl = AND;
                    default: rCtrl = ADD;
                endcase
            end

            default: rCtrl = ADD;
        endcase
    end

    assign oAluCtrl = rCtrl;

endmodule