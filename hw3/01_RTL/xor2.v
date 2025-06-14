module xor2 #(
    parameter ID = 0
) (
    output [63:0] o_ID,
    input  [ 1:0] a,
    input  [ 1:0] b,
    output [ 1:0] z
);

    `ifdef RTL
        initial begin
            $display("ID = %d", ID);
        end
    `endif

    assign o_ID = ID;
    assign z = a ^ b;

endmodule

// module faulty_xor2 #(
//     parameter ID = 0
// ) (
//     output [63:0] o_ID,
//     input  [ 1:0] a,
//     input  [ 1:0] b,
//     output [ 1:0] z
// );

//     `ifdef RTL
//         initial begin
//             $display("ID = %d", ID);
//         end
//     `endif

//     assign o_ID = ID;
//     assign z = (a==2'b11 && b==2'b11) ? 1 : a^b;

// endmodule

