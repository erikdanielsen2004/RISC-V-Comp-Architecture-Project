module DATA_MEMORY #(
    parameter BLOCK_SIZE = 64
)(
    input          iClk,
    input          iRstN,

    // Legacy word interface, kept for compatibility with older phase code.
    input  [31:0]  iAddress,
    input  [31:0]  iWriteData,
    input  [2:0]   iFunct3,
    input          iMemWrite,
    input          iMemRead,
    output [31:0]  oReadData,

    // Cache block interface.
    input          iBlockRead,
    input          iBlockWrite,
    input  [31:0]  iBlockAddr,
    input  [511:0] iBlockWriteData,
    output reg [511:0] oBlockReadData,
    output         oMemReady,
    output         oMemValid
);

    localparam B = 8;
    localparam K = 1024;

    // 4KB byte-addressable data memory.  Autograder expects this exact name.
    reg [B-1:0] rDataMem [0:(K*4)-1];

    integer data_fd;
    integer n;
    integer base;

    initial begin
        data_fd = $fopen("data.txt", "r");
        if (data_fd) begin
            $fclose(data_fd);
            $readmemh("data.txt", rDataMem);
        end
    end

    wire [11:0] a = iAddress[11:0];

    always @(posedge iClk or negedge iRstN) begin
        if (!iRstN) begin
            // Keep initialized memory contents.
        end else begin
            if (iMemWrite) begin
                case (iFunct3)
                    3'b000: rDataMem[a] <= iWriteData[7:0];
                    3'b001: begin
                        rDataMem[a]       <= iWriteData[7:0];
                        rDataMem[a+12'd1] <= iWriteData[15:8];
                    end
                    3'b010: begin
                        rDataMem[a]       <= iWriteData[7:0];
                        rDataMem[a+12'd1] <= iWriteData[15:8];
                        rDataMem[a+12'd2] <= iWriteData[23:16];
                        rDataMem[a+12'd3] <= iWriteData[31:24];
                    end
                    default: begin end
                endcase
            end

            if (iBlockWrite) begin
                base = iBlockAddr[11:0] & ~(BLOCK_SIZE-1);
                for (n = 0; n < 64; n = n + 1)
                    rDataMem[(base + n) & 12'hfff] <= iBlockWriteData[n*8 +: 8];
            end
        end
    end

    always @(*) begin
        base = iBlockAddr[11:0] & ~(BLOCK_SIZE-1);
        for (n = 0; n < 64; n = n + 1)
            oBlockReadData[n*8 +: 8] = rDataMem[(base + n) & 12'hfff];
    end

    wire [7:0]  b0 = rDataMem[a];
    wire [7:0]  b1 = rDataMem[a+12'd1];
    wire [7:0]  b2 = rDataMem[a+12'd2];
    wire [7:0]  b3 = rDataMem[a+12'd3];
    wire [15:0] h  = {b1, b0};
    wire [31:0] w  = {b3, b2, b1, b0};

    reg [31:0] rRead;
    always @(*) begin
        rRead = 32'b0;
        if (iMemRead) begin
            case (iFunct3)
                3'b000: rRead = {{24{b0[7]}}, b0};
                3'b001: rRead = {{16{h[15]}}, h};
                3'b010: rRead = w;
                3'b100: rRead = {24'b0, b0};
                3'b101: rRead = {16'b0, h};
                default: rRead = 32'b0;
            endcase
        end
    end

    assign oReadData = rRead;
    assign oMemReady = 1'b1;
    assign oMemValid = iBlockRead;

endmodule
