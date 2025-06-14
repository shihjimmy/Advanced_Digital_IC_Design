`celldefine
module memory #(
    parameter CELL_SIZE  = 22,
    parameter CELL_NUM   = 256,
    parameter ADDR_WIDTH = 8, 
    parameter SRAM_NAME  = ""
) (
    // A block
    input  wire                     clka,
    input  wire                     cena,
    input  wire [ADDR_WIDTH-1:0]    aa,
    output reg  [CELL_SIZE -1:0]    qa,

    // B block
    input  wire                     clkb,
    input  wire                     cenb,
    input  wire [ADDR_WIDTH-1:0]    ab,
    input  wire [CELL_SIZE -1:0]    db
);

//=======================================
// reg & wire
//=======================================
reg [CELL_SIZE-1:0] memory_reg [CELL_NUM-1:0];
reg [CELL_SIZE-1:0] qa_temp;

//=======================================
// block a
//=======================================
always @(posedge clka) begin
    if(!cena) begin
        qa_temp = memory_reg[aa];
        #(2.0) qa = qa_temp;
    end else begin
        #(2.0) qa = qa;
    end
end

//=======================================
// block b
//=======================================
always @(posedge clkb) begin
    if(!cenb) begin
        if(^db === 1'bx) begin
            $display("====================================================");
            $display("%s", SRAM_NAME);
            $display("                        fatal                       ");
            $display("                 sram unknown storage               ");
            $display("====================================================");
            $finish();
        end
        memory_reg[ab] <= db;
    end 
end

//=======================================
// collision
//=======================================
always @(posedge clka or posedge clkb) begin
    if((!cena) && (!cenb)) begin
        if(aa == ab) begin
            $display("====================================================");
            $display("%s", SRAM_NAME);
            $display("                        fatal                       ");
            $display("                 read/write collision               ");
            $display("====================================================");
            $finish();
        end
    end
end

endmodule
`endcelldefine