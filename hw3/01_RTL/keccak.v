module keccak #(
    parameter IN_DATA_WIDTH  = 128,
    parameter OUT_DATA_WIDTH = 64
) (
    input  i_clk,
    input  i_clk2,
    input  i_rst_n,

    input  [               1:0] i_mode,
    output reg                  o_ready,
    input                       i_valid,
    input                       i_last,
    input  [ IN_DATA_WIDTH-1:0] i_data_a,
    input  [ IN_DATA_WIDTH-1:0] i_data_b,
    output                      o_valid_a,
    output [OUT_DATA_WIDTH-1:0] o_data_a,
    output                      o_valid_b,
    output [OUT_DATA_WIDTH-1:0] o_data_b,
    output                      o_BIST_valid,
    output [OUT_DATA_WIDTH-1:0] o_BIST_data
);

    localparam S_IDLE = 0;
    localparam S_GET0 = 1;
    localparam S_GET1 = 2;
    localparam S_GET2 = 3;
    localparam S_STAGE1 = 4;
    localparam S_STAGE2 = 5;
    localparam S_OUT = 6;
    localparam S_TEST = 7;
    localparam S_TEST_OUT = 8;

    reg [3:0] state_r, state_w;
    reg is_last_r, is_last_w;
    reg A_or_B_r, A_or_B_w;
    
    reg [127:0] extra_A_r, extra_A_w;
    reg [127:0] extra_B_r, extra_B_w;

    reg [15:0] S_reg_A_r[0:24], S_reg_A_w[0:24];
    reg [15:0] S_reg_B_r[0:24], S_reg_B_w[0:24];
    
    reg [2:0] count_get_r, count_get_w;
    reg [4:0] count_iter_r, count_iter_w;

    reg i_valid_r, i_last_r;

    reg BIST_find;
    reg [63:0] o_BIST_id;
    reg [74:0] false;
    reg [1:0] golden;

    /////////////////////////////////////////////
    // for xor2
    wire [63:0] xor2_id[0:599];
    wire [1:0]  xor2_out[0:599];
    reg  [1:0]  xor2_a[0:599], xor2_b[0:599];
    wire [15:0] ROT[0:4];
    reg [15:0]  temp[0:74];

    genvar gi;
    generate
        for (gi = 0; gi < 600; gi=gi+1) begin: xor2s
            xor2 #(
                .ID (gi+1)
            ) u_xor2 (
                .o_ID   (xor2_id[gi]),
                .a      (xor2_a[gi]),
                .b      (xor2_b[gi]),
                .z      (xor2_out[gi])
            );
        end
    endgenerate


    // faulty_xor2 #(
    //     .ID (308)
    // )faulty_xor(
    //     .o_ID   (xor2_id[308]),
    //     .a      (xor2_a[308]),
    //     .b      (xor2_b[308]),
    //     .z      (xor2_out[308])
    // );


    // generate
    //     for (genvar gi = 309; gi < 600; gi=gi+1) begin
    //         xor2 #(
    //             .ID (gi)
    //         ) u_xor2 (
    //             .o_ID   (xor2_id[gi]),
    //             .a      (xor2_a[gi]),
    //             .b      (xor2_b[gi]),
    //             .z      (xor2_out[gi])
    //         );
    //     end
    // endgenerate
    /////////////////////////////////////////////

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)    begin
            i_valid_r <= 0;
            i_last_r  <= 0;
        end
        else begin
            i_valid_r <= i_valid;
            i_last_r  <= i_last;
        end
    end


    always@ (*) begin
        case(state_r)
            S_IDLE:     state_w = (i_mode == 2'b00 || i_mode == 2'b01) ? S_GET0 : S_TEST;   
            
            S_GET0:     state_w = ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00 && i_valid_r)) ? S_GET1 : state_r;
            S_GET1:     state_w = ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00 && i_valid_r)) ? S_GET2 : state_r;
            S_GET2:     state_w = ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00 && i_valid_r)) ? S_STAGE1 : state_r;
           
            S_STAGE1:   state_w = ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00)) ? S_STAGE2 : state_r;
            S_STAGE2:   state_w = ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00)) && (count_iter_r==5'd19) 
                                    ? S_OUT : ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00)) ? S_STAGE1 : state_r;
            
            S_OUT:      state_w = ( ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00)) && (is_last_r || count_get_r==0) )
                                    ? S_GET0 :  ((i_mode == 2'b01 && A_or_B_r) || (i_mode == 2'b00)) ? S_GET1 : state_r;
            
            S_TEST:     state_w = (BIST_find || &count_iter_r[3:0]) ? S_TEST_OUT : state_r;
            S_TEST_OUT: state_w = S_IDLE;
            default:    state_w = S_IDLE;
        endcase
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)    state_r <= S_IDLE;
        else            state_r <= state_w;
    end

    always@ (*) begin
        case(state_r)
            S_GET0, S_GET1, S_GET2: o_ready = ~A_or_B_r && ~i_valid_r;
            default:                o_ready = 0;
        endcase
    end

    assign o_valid_a = (state_r == S_OUT && is_last_r && ~A_or_B_r);
    assign o_valid_b = (state_r == S_OUT && is_last_r && ~A_or_B_r);
    assign o_data_a  = {S_reg_A_r[3], S_reg_A_r[2], S_reg_A_r[1], S_reg_A_r[0]};
    assign o_data_b  = {S_reg_B_r[3], S_reg_B_r[2], S_reg_B_r[1], S_reg_B_r[0]};

    assign o_BIST_valid = (state_r == S_TEST_OUT);
    assign o_BIST_data  = {S_reg_A_r[3], S_reg_A_r[2], S_reg_A_r[1], S_reg_A_r[0]};

    /////////////////////////////////////////////
    // for S_reg_A

    integer i;
    always@ (*) begin
        for(i=0; i<25; i=i+1) begin
            S_reg_A_w[i] = S_reg_A_r[i];
        end

        case(state_r)
            S_GET0:     begin
                if(i_valid_r && ~A_or_B_r) begin
                    for(i=0; i<8; i=i+1) 
                        S_reg_A_w[i] = temp[i];
                end
            end

            S_GET1:     begin
                if(i_valid_r && ~A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+8] = temp[i];
                        end

                        3'd1: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+7] = temp[i];
                        end

                        3'd2: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+6] = temp[i];
                        end

                        3'd3: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+5] = temp[i];
                        end

                        3'd4: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+4] = temp[i];
                        end

                        3'd5: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+3] = temp[i];
                        end

                        3'd6: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+2] = temp[i];
                        end

                        3'd7: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_A_w[i+1] = temp[i];
                        end
                    endcase
                end
            end

            S_GET2:     begin
                if(i_valid_r && ~A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            S_reg_A_w[16] = temp[0];
                        end
                        
                        3'd1: begin
                            S_reg_A_w[15] = temp[0];
                            S_reg_A_w[16] = temp[1];
                        end
                        
                        3'd2: begin
                            S_reg_A_w[14] = temp[0];
                            S_reg_A_w[15] = temp[1];
                            S_reg_A_w[16] = temp[2];
                        end
                        
                        3'd3: begin
                            S_reg_A_w[13] = temp[0];
                            S_reg_A_w[14] = temp[1];
                            S_reg_A_w[15] = temp[2];
                            S_reg_A_w[16] = temp[3];
                        end
                        
                        3'd4: begin
                            S_reg_A_w[12] = temp[0];
                            S_reg_A_w[13] = temp[1];
                            S_reg_A_w[14] = temp[2];
                            S_reg_A_w[15] = temp[3];
                            S_reg_A_w[16] = temp[4];
                        end
                        
                        3'd5: begin
                            S_reg_A_w[11] = temp[0];
                            S_reg_A_w[12] = temp[1];
                            S_reg_A_w[13] = temp[2];
                            S_reg_A_w[14] = temp[3];
                            S_reg_A_w[15] = temp[4];
                            S_reg_A_w[16] = temp[5];
                        end
                        
                        3'd6: begin
                            S_reg_A_w[10] = temp[0];
                            S_reg_A_w[11] = temp[1];
                            S_reg_A_w[12] = temp[2];
                            S_reg_A_w[13] = temp[3];
                            S_reg_A_w[14] = temp[4];
                            S_reg_A_w[15] = temp[5];
                            S_reg_A_w[16] = temp[6];
                        end
                        
                        3'd7: begin
                            S_reg_A_w[9]  = temp[0];
                            S_reg_A_w[10] = temp[1];
                            S_reg_A_w[11] = temp[2];
                            S_reg_A_w[12] = temp[3];
                            S_reg_A_w[13] = temp[4];
                            S_reg_A_w[14] = temp[5];
                            S_reg_A_w[15] = temp[6];
                            S_reg_A_w[16] = temp[7];
                        end
                    endcase
                end
            end

            S_STAGE1:   begin
                if(~A_or_B_r) begin
                    S_reg_A_w[0]  =  temp[5];
                    S_reg_A_w[5]  = {temp[6][0 +: 12], temp[6][12 +: 4]};
                    S_reg_A_w[10] = {temp[7][0 +: 13], temp[7][13 +: 3]};
                    S_reg_A_w[15] = {temp[8][0 +: 7],  temp[8][7 +: 9]};
                    S_reg_A_w[20] = {temp[9][0 +: 14], temp[9][14 +: 2]};

                    S_reg_A_w[1]  = {temp[20][0 +: 15], temp[20][15 +: 1]};
                    S_reg_A_w[6]  = {temp[21][0 +: 4],  temp[21][4 +: 12]};
                    S_reg_A_w[11] = {temp[22][0 +: 6],  temp[22][6 +: 10]};
                    S_reg_A_w[16] = {temp[23][0 +: 3],  temp[23][3 +: 13]};
                    S_reg_A_w[21] = {temp[24][0 +: 14], temp[24][14 +: 2]};

                    S_reg_A_w[2]  = {temp[35][0 +: 2] , temp[35][2 +: 14]};
                    S_reg_A_w[7]  = {temp[36][0 +: 10], temp[36][10 +: 6]};
                    S_reg_A_w[12] = {temp[37][0 +: 5] , temp[37][5 +: 11]};
                    S_reg_A_w[17] = {temp[38][0 +: 1] , temp[38][1 +: 15]};
                    S_reg_A_w[22] = {temp[39][0 +: 3] , temp[39][3 +: 13]};

                    S_reg_A_w[3]  = {temp[50][0 +: 4] , temp[50][4 +: 12]};
                    S_reg_A_w[8]  = {temp[51][0 +: 9] , temp[51][9 +: 7]};
                    S_reg_A_w[13] = {temp[52][0 +: 7] , temp[52][7 +: 9]};
                    S_reg_A_w[18] = {temp[53][0 +: 11], temp[53][11 +: 5]};
                    S_reg_A_w[23] = {temp[54][0 +: 8] , temp[54][8 +: 8]};

                    S_reg_A_w[4]  = {temp[65][0 +: 5] , temp[65][5 +: 11]};
                    S_reg_A_w[9]  = {temp[66][0 +: 12], temp[66][12 +: 4]};
                    S_reg_A_w[14] = {temp[67][0 +: 9] , temp[67][9 +: 7]};
                    S_reg_A_w[19] = {temp[68][0 +: 8] , temp[68][8 +: 8]};
                    S_reg_A_w[24] = {temp[69][0 +: 2] , temp[69][2 +: 14]};
                end
            end


            S_STAGE2:   begin
                if(~A_or_B_r) begin
                    S_reg_A_w[1]  = temp[1];
                    S_reg_A_w[2]  = temp[2];
                    S_reg_A_w[3]  = temp[3];
                    S_reg_A_w[4]  = temp[4]; 
                    S_reg_A_w[5]  = temp[5];
                    S_reg_A_w[6]  = temp[6];
                    S_reg_A_w[7]  = temp[7];
                    S_reg_A_w[8]  = temp[8];
                    S_reg_A_w[9]  = temp[9];
                    S_reg_A_w[10] = temp[10];  
                    S_reg_A_w[11] = temp[11]; 
                    S_reg_A_w[12] = temp[12]; 
                    S_reg_A_w[13] = temp[13]; 
                    S_reg_A_w[14] = temp[14]; 
                    S_reg_A_w[15] = temp[15];
                    S_reg_A_w[16] = temp[16];
                    S_reg_A_w[17] = temp[17];
                    S_reg_A_w[18] = temp[18];
                    S_reg_A_w[19] = temp[19];
                    S_reg_A_w[20] = temp[20];
                    S_reg_A_w[21] = temp[21];
                    S_reg_A_w[22] = temp[22];
                    S_reg_A_w[23] = temp[23];
                    S_reg_A_w[24] = temp[24];
                    S_reg_A_w[0]  = temp[25];
                end
            end

            S_OUT:      begin
                if(is_last_r) begin
                    for(i=0; i<25; i=i+1) begin
                        S_reg_A_w[i] = 0;
                    end
                end
                else if(~A_or_B_r) begin
                    case(count_get_r)
                        3'd1: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                            S_reg_A_w[2] = temp[2];
                            S_reg_A_w[3] = temp[3];
                            S_reg_A_w[4] = temp[4];
                            S_reg_A_w[5] = temp[5];
                            S_reg_A_w[6] = temp[6];
                        end

                        3'd2: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                            S_reg_A_w[2] = temp[2];
                            S_reg_A_w[3] = temp[3];
                            S_reg_A_w[4] = temp[4];
                            S_reg_A_w[5] = temp[5];
                        end

                        3'd3: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                            S_reg_A_w[2] = temp[2];
                            S_reg_A_w[3] = temp[3];
                            S_reg_A_w[4] = temp[4];
                        end

                        3'd4: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                            S_reg_A_w[2] = temp[2];
                            S_reg_A_w[3] = temp[3];
                        end

                        3'd5: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                            S_reg_A_w[2] = temp[2];
                        end

                        3'd6: begin
                            S_reg_A_w[0] = temp[0];
                            S_reg_A_w[1] = temp[1];
                        end

                        3'd7: begin
                            S_reg_A_w[0] = temp[0];
                        end
                    endcase
                end
            end

            S_TEST: begin
                S_reg_A_w[0] = o_BIST_id[0  +: 16];
                S_reg_A_w[1] = o_BIST_id[16 +: 16];
                S_reg_A_w[2] = o_BIST_id[32 +: 16];
                S_reg_A_w[3] = o_BIST_id[48 +: 16];
            end
        endcase
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n) begin
            for(i=0; i<25; i=i+1) begin
                S_reg_A_r[i] <= 0;
            end
        end
        else begin
            for(i=0; i<25; i=i+1) begin
                S_reg_A_r[i] <= S_reg_A_w[i];
            end
        end
    end


    /////////////////////////////////////////////
    // for s_reg_B

    always@ (*) begin
        for(i=0; i<25; i=i+1) begin
            S_reg_B_w[i] = S_reg_B_r[i];
        end

        case(state_r)
            S_GET0:     begin
                if(A_or_B_r) begin
                    for(i=0; i<8; i=i+1) 
                        S_reg_B_w[i] = temp[i];
                end
            end

            S_GET1:     begin
                if(A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+8] = temp[i];
                        end

                        3'd1: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+7] = temp[i];
                        end

                        3'd2: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+6] = temp[i];
                        end

                        3'd3: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+5] = temp[i];
                        end

                        3'd4: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+4] = temp[i];
                        end

                        3'd5: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+3] = temp[i];
                        end

                        3'd6: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+2] = temp[i];
                        end

                        3'd7: begin
                            for(i=0; i<8; i=i+1) 
                                S_reg_B_w[i+1] = temp[i];
                        end
                    endcase
                end
            end

            S_GET2:     begin
                if(A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            S_reg_B_w[16] = temp[0];
                        end
                        
                        3'd1: begin
                            S_reg_B_w[15] = temp[0];
                            S_reg_B_w[16] = temp[1];
                        end
                        
                        3'd2: begin
                            S_reg_B_w[14] = temp[0];
                            S_reg_B_w[15] = temp[1];
                            S_reg_B_w[16] = temp[2];
                        end
                        
                        3'd3: begin
                            S_reg_B_w[13] = temp[0];
                            S_reg_B_w[14] = temp[1];
                            S_reg_B_w[15] = temp[2];
                            S_reg_B_w[16] = temp[3];
                        end
                        
                        3'd4: begin
                            S_reg_B_w[12] = temp[0];
                            S_reg_B_w[13] = temp[1];
                            S_reg_B_w[14] = temp[2];
                            S_reg_B_w[15] = temp[3];
                            S_reg_B_w[16] = temp[4];
                        end
                        
                        3'd5: begin
                            S_reg_B_w[11] = temp[0];
                            S_reg_B_w[12] = temp[1];
                            S_reg_B_w[13] = temp[2];
                            S_reg_B_w[14] = temp[3];
                            S_reg_B_w[15] = temp[4];
                            S_reg_B_w[16] = temp[5];
                        end
                        
                        3'd6: begin
                            S_reg_B_w[10] = temp[0];
                            S_reg_B_w[11] = temp[1];
                            S_reg_B_w[12] = temp[2];
                            S_reg_B_w[13] = temp[3];
                            S_reg_B_w[14] = temp[4];
                            S_reg_B_w[15] = temp[5];
                            S_reg_B_w[16] = temp[6];
                        end
                        
                        3'd7: begin
                            S_reg_B_w[9]  = temp[0];
                            S_reg_B_w[10] = temp[1];
                            S_reg_B_w[11] = temp[2];
                            S_reg_B_w[12] = temp[3];
                            S_reg_B_w[13] = temp[4];
                            S_reg_B_w[14] = temp[5];
                            S_reg_B_w[15] = temp[6];
                            S_reg_B_w[16] = temp[7];
                        end
                    endcase
                end
            end

            S_STAGE1:   begin
                if(A_or_B_r) begin
                    S_reg_B_w[0]  =  temp[5];
                    S_reg_B_w[5]  = {temp[6][0 +: 12], temp[6][12 +: 4]};
                    S_reg_B_w[10] = {temp[7][0 +: 13], temp[7][13 +: 3]};
                    S_reg_B_w[15] = {temp[8][0 +: 7],  temp[8][7 +: 9]};
                    S_reg_B_w[20] = {temp[9][0 +: 14], temp[9][14 +: 2]};

                    S_reg_B_w[1]  = {temp[20][0 +: 15], temp[20][15 +: 1]};
                    S_reg_B_w[6]  = {temp[21][0 +: 4],  temp[21][4 +: 12]};
                    S_reg_B_w[11] = {temp[22][0 +: 6],  temp[22][6 +: 10]};
                    S_reg_B_w[16] = {temp[23][0 +: 3],  temp[23][3 +: 13]};
                    S_reg_B_w[21] = {temp[24][0 +: 14], temp[24][14 +: 2]};

                    S_reg_B_w[2]  = {temp[35][0 +: 2] , temp[35][2 +: 14]};
                    S_reg_B_w[7]  = {temp[36][0 +: 10], temp[36][10 +: 6]};
                    S_reg_B_w[12] = {temp[37][0 +: 5] , temp[37][5 +: 11]};
                    S_reg_B_w[17] = {temp[38][0 +: 1] , temp[38][1 +: 15]};
                    S_reg_B_w[22] = {temp[39][0 +: 3] , temp[39][3 +: 13]};

                    S_reg_B_w[3]  = {temp[50][0 +: 4] , temp[50][4 +: 12]};
                    S_reg_B_w[8]  = {temp[51][0 +: 9] , temp[51][9 +: 7]};
                    S_reg_B_w[13] = {temp[52][0 +: 7] , temp[52][7 +: 9]};
                    S_reg_B_w[18] = {temp[53][0 +: 11], temp[53][11 +: 5]};
                    S_reg_B_w[23] = {temp[54][0 +: 8] , temp[54][8 +: 8]};

                    S_reg_B_w[4]  = {temp[65][0 +: 5] , temp[65][5 +: 11]};
                    S_reg_B_w[9]  = {temp[66][0 +: 12], temp[66][12 +: 4]};
                    S_reg_B_w[14] = {temp[67][0 +: 9] , temp[67][9 +: 7]};
                    S_reg_B_w[19] = {temp[68][0 +: 8] , temp[68][8 +: 8]};
                    S_reg_B_w[24] = {temp[69][0 +: 2] , temp[69][2 +: 14]};
                end
            end


            S_STAGE2:   begin
                if(A_or_B_r) begin
                    S_reg_B_w[1]  = temp[1];
                    S_reg_B_w[2]  = temp[2];
                    S_reg_B_w[3]  = temp[3];
                    S_reg_B_w[4]  = temp[4]; 
                    S_reg_B_w[5]  = temp[5];
                    S_reg_B_w[6]  = temp[6];
                    S_reg_B_w[7]  = temp[7];
                    S_reg_B_w[8]  = temp[8];
                    S_reg_B_w[9]  = temp[9];
                    S_reg_B_w[10] = temp[10];  
                    S_reg_B_w[11] = temp[11]; 
                    S_reg_B_w[12] = temp[12]; 
                    S_reg_B_w[13] = temp[13]; 
                    S_reg_B_w[14] = temp[14]; 
                    S_reg_B_w[15] = temp[15];
                    S_reg_B_w[16] = temp[16];
                    S_reg_B_w[17] = temp[17];
                    S_reg_B_w[18] = temp[18];
                    S_reg_B_w[19] = temp[19];
                    S_reg_B_w[20] = temp[20];
                    S_reg_B_w[21] = temp[21];
                    S_reg_B_w[22] = temp[22];
                    S_reg_B_w[23] = temp[23];
                    S_reg_B_w[24] = temp[24];
                    S_reg_B_w[0]  = temp[25];
                end
            end

            S_OUT:      begin
                if(is_last_r) begin
                    for(i=0; i<25; i=i+1) begin
                        S_reg_B_w[i] = 0;
                    end
                end
                else if(A_or_B_r) begin
                    case(count_get_r)
                        3'd1: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                            S_reg_B_w[2] = temp[2];
                            S_reg_B_w[3] = temp[3];
                            S_reg_B_w[4] = temp[4];
                            S_reg_B_w[5] = temp[5];
                            S_reg_B_w[6] = temp[6];
                        end

                        3'd2: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                            S_reg_B_w[2] = temp[2];
                            S_reg_B_w[3] = temp[3];
                            S_reg_B_w[4] = temp[4];
                            S_reg_B_w[5] = temp[5];
                        end

                        3'd3: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                            S_reg_B_w[2] = temp[2];
                            S_reg_B_w[3] = temp[3];
                            S_reg_B_w[4] = temp[4];
                        end

                        3'd4: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                            S_reg_B_w[2] = temp[2];
                            S_reg_B_w[3] = temp[3];
                        end

                        3'd5: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                            S_reg_B_w[2] = temp[2];
                        end

                        3'd6: begin
                            S_reg_B_w[0] = temp[0];
                            S_reg_B_w[1] = temp[1];
                        end

                        3'd7: begin
                            S_reg_B_w[0] = temp[0];
                        end
                    endcase
                end
            end
        endcase
    end

    wire B_enable;
    assign B_enable = i_mode==2'b01;

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n) begin
            for(i=0; i<25; i=i+1) begin
                S_reg_B_r[i] <= 0;
            end
        end
        else if(B_enable) begin
            for(i=0; i<25; i=i+1) begin
                S_reg_B_r[i] <= S_reg_B_w[i];
            end
        end
    end

    /////////////////////////////////////////////


    /////////////////////////////////////////////
    // for xor in/output

    integer j;
    always@ (*) begin
        for (j=0; j<600; j=j+1) begin
            xor2_a[j] = 0;
            xor2_b[j] = 0;
        end

        case(state_r)
            S_GET0: begin
                if(i_valid_r && ~A_or_B_r) begin
                    for (j=0; j<64; j=j+1) begin
                        xor2_a[j] = extra_A_r[2*j +: 2];
                    end

                    for (j=0; j<8; j=j+1) begin
                        xor2_b[j]    = S_reg_A_r[0][2*j +: 2];
                        xor2_b[j+8]  = S_reg_A_r[1][2*j +: 2];
                        xor2_b[j+16] = S_reg_A_r[2][2*j +: 2];
                        xor2_b[j+24] = S_reg_A_r[3][2*j +: 2];
                        xor2_b[j+32] = S_reg_A_r[4][2*j +: 2];
                        xor2_b[j+40] = S_reg_A_r[5][2*j +: 2];
                        xor2_b[j+48] = S_reg_A_r[6][2*j +: 2];
                        xor2_b[j+56] = S_reg_A_r[7][2*j +: 2];
                    end
                end
                else if(A_or_B_r) begin
                    for (j=0; j<64; j=j+1) begin
                        xor2_a[j] = extra_B_r[2*j +: 2];
                    end

                    for (j=0; j<8; j=j+1) begin
                        xor2_b[j]    = S_reg_B_r[0][2*j +: 2];
                        xor2_b[j+8]  = S_reg_B_r[1][2*j +: 2];
                        xor2_b[j+16] = S_reg_B_r[2][2*j +: 2];
                        xor2_b[j+24] = S_reg_B_r[3][2*j +: 2];
                        xor2_b[j+32] = S_reg_B_r[4][2*j +: 2];
                        xor2_b[j+40] = S_reg_B_r[5][2*j +: 2];
                        xor2_b[j+48] = S_reg_B_r[6][2*j +: 2];
                        xor2_b[j+56] = S_reg_B_r[7][2*j +: 2];
                    end
                end
            end

            S_GET1: begin
                if(i_valid_r && ~A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[15][2*j +: 2];
                            end
                        end

                        3'd1: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[14][2*j +: 2];
                            end
                        end

                        3'd2: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[13][2*j +: 2];
                            end
                        end

                        3'd3: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[5][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[12][2*j +: 2];
                            end
                        end

                        3'd4: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[4][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[5][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[11][2*j +: 2];
                            end
                        end

                        3'd5: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[3][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[4][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[5][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[10][2*j +: 2];
                            end
                        end

                        3'd6: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[2][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[3][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[4][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[5][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[8][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[9][2*j +: 2];
                            end
                        end

                        3'd7: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[1][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[2][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[3][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[4][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[5][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[6][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[7][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[8][2*j +: 2];
                            end
                        end
                    endcase
                end
                else if(A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[15][2*j +: 2];
                            end
                        end

                        3'd1: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[14][2*j +: 2];
                            end
                        end

                        3'd2: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[13][2*j +: 2];
                            end
                        end

                        3'd3: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[5][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[12][2*j +: 2];
                            end
                        end

                        3'd4: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[4][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[5][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[11][2*j +: 2];
                            end
                        end

                        3'd5: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[3][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[4][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[5][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[10][2*j +: 2];
                            end
                        end

                        3'd6: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[2][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[3][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[4][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[5][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[8][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[9][2*j +: 2];
                            end
                        end

                        3'd7: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[1][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[2][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[3][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[4][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[5][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[6][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[7][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[8][2*j +: 2];
                            end
                        end
                    endcase
                end
            end

            S_GET2:     begin
                if(i_valid_r && ~A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for (j=0; j<8; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd1: begin
                            for (j=0; j<16; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]   = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+8] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd2: begin
                            for (j=0; j<24; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd3: begin
                            for (j=0; j<32; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd4: begin
                            for (j=0; j<40; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd5: begin
                            for (j=0; j<48; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd6: begin
                            for (j=0; j<56; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[16][2*j +: 2];
                            end
                        end

                        3'd7: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_A_r[9][2*j +: 2];
                                xor2_b[j+8]  = S_reg_A_r[10][2*j +: 2];
                                xor2_b[j+16] = S_reg_A_r[11][2*j +: 2];
                                xor2_b[j+24] = S_reg_A_r[12][2*j +: 2];
                                xor2_b[j+32] = S_reg_A_r[13][2*j +: 2];
                                xor2_b[j+40] = S_reg_A_r[14][2*j +: 2];
                                xor2_b[j+48] = S_reg_A_r[15][2*j +: 2];
                                xor2_b[j+56] = S_reg_A_r[16][2*j +: 2];
                            end
                        end
                    endcase
                end
                else if(A_or_B_r) begin
                    case(count_get_r)
                        3'd0: begin
                            for (j=0; j<8; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd1: begin
                            for (j=0; j<16; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]   = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+8] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd2: begin
                            for (j=0; j<24; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd3: begin
                            for (j=0; j<32; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd4: begin
                            for (j=0; j<40; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd5: begin
                            for (j=0; j<48; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd6: begin
                            for (j=0; j<56; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[16][2*j +: 2];
                            end
                        end

                        3'd7: begin
                            for (j=0; j<64; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for (j=0; j<8; j=j+1) begin
                                xor2_b[j]    = S_reg_B_r[9][2*j +: 2];
                                xor2_b[j+8]  = S_reg_B_r[10][2*j +: 2];
                                xor2_b[j+16] = S_reg_B_r[11][2*j +: 2];
                                xor2_b[j+24] = S_reg_B_r[12][2*j +: 2];
                                xor2_b[j+32] = S_reg_B_r[13][2*j +: 2];
                                xor2_b[j+40] = S_reg_B_r[14][2*j +: 2];
                                xor2_b[j+48] = S_reg_B_r[15][2*j +: 2];
                                xor2_b[j+56] = S_reg_B_r[16][2*j +: 2];
                            end
                        end
                    endcase
                end
            end

            S_STAGE1:   begin
                if(~A_or_B_r) begin

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[4][2*j +: 2];
                        xor2_b[j] = S_reg_A_r[9][2*j +: 2];

                        xor2_a[j+8] = temp[0][2*j +: 2];
                        xor2_b[j+8] = S_reg_A_r[14][2*j +: 2];

                        xor2_a[j+16] = temp[1][2*j +: 2];
                        xor2_b[j+16] = S_reg_A_r[19][2*j +: 2];

                        xor2_a[j+24] = temp[2][2*j +: 2];
                        xor2_b[j+24] = S_reg_A_r[24][2*j +: 2];

                        xor2_a[j+32] = temp[3][2*j +: 2];
                        xor2_b[j+32] = ROT[0][2*j +: 2];

                        xor2_a[j+40] = temp[4][2*j +: 2];
                        xor2_b[j+40] = S_reg_A_r[0][2*j +: 2];

                        xor2_a[j+48] = temp[4][2*j +: 2];
                        xor2_b[j+48] = S_reg_A_r[5][2*j +: 2];

                        xor2_a[j+56] = temp[4][2*j +: 2];
                        xor2_b[j+56] = S_reg_A_r[10][2*j +: 2];

                        xor2_a[j+64] = temp[4][2*j +: 2];
                        xor2_b[j+64] = S_reg_A_r[15][2*j +: 2];

                        xor2_a[j+72] = temp[4][2*j +: 2];
                        xor2_b[j+72] = S_reg_A_r[20][2*j +: 2];

                        xor2_a[j+80] = S_reg_A_r[1][2*j +: 2];
                        xor2_b[j+80] = S_reg_A_r[6][2*j +: 2];

                        xor2_a[j+88] = temp[10][2*j +: 2];
                        xor2_b[j+88] = S_reg_A_r[11][2*j +: 2];

                        xor2_a[j+96] = temp[11][2*j +: 2];
                        xor2_b[j+96] = S_reg_A_r[16][2*j +: 2];

                        xor2_a[j+104] = temp[12][2*j +: 2];
                        xor2_b[j+104] = S_reg_A_r[21][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+120] = S_reg_A_r[0][2*j +: 2];
                        xor2_b[j+120] = S_reg_A_r[5][2*j +: 2];

                        xor2_a[j+128] = temp[15][2*j +: 2];
                        xor2_b[j+128] = S_reg_A_r[10][2*j +: 2];

                        xor2_a[j+136] = temp[16][2*j +: 2];
                        xor2_b[j+136] = S_reg_A_r[15][2*j +: 2];

                        xor2_a[j+144] = temp[17][2*j +: 2];
                        xor2_b[j+144] = S_reg_A_r[20][2*j +: 2];

                        xor2_a[j+152] = temp[18][2*j +: 2];
                        xor2_b[j+152] = ROT[1][2*j +: 2];

                        xor2_a[j+160] = temp[19][2*j +: 2];
                        xor2_b[j+160] = S_reg_A_r[1][2*j +: 2];

                        xor2_a[j+168] = temp[19][2*j +: 2];
                        xor2_b[j+168] = S_reg_A_r[6][2*j +: 2];

                        xor2_a[j+176] = temp[19][2*j +: 2];
                        xor2_b[j+176] = S_reg_A_r[11][2*j +: 2];

                        xor2_a[j+184] = temp[19][2*j +: 2];
                        xor2_b[j+184] = S_reg_A_r[16][2*j +: 2];

                        xor2_a[j+192] = temp[19][2*j +: 2];
                        xor2_b[j+192] = S_reg_A_r[21][2*j +: 2];

                        xor2_a[j+200] = S_reg_A_r[2][2*j +: 2];
                        xor2_b[j+200] = S_reg_A_r[7][2*j +: 2];

                        xor2_a[j+208] = temp[25][2*j +: 2];
                        xor2_b[j+208] = S_reg_A_r[12][2*j +: 2];

                        xor2_a[j+216] = temp[26][2*j +: 2];
                        xor2_b[j+216] = S_reg_A_r[17][2*j +: 2];

                        xor2_a[j+224] = temp[27][2*j +: 2];
                        xor2_b[j+224] = S_reg_A_r[22][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+240] = S_reg_A_r[1][2*j +: 2];
                        xor2_b[j+240] = S_reg_A_r[6][2*j +: 2];

                        xor2_a[j+248] = temp[30][2*j +: 2];
                        xor2_b[j+248] = S_reg_A_r[11][2*j +: 2];

                        xor2_a[j+256] = temp[31][2*j +: 2];
                        xor2_b[j+256] = S_reg_A_r[16][2*j +: 2];

                        xor2_a[j+264] = temp[32][2*j +: 2];
                        xor2_b[j+264] = S_reg_A_r[21][2*j +: 2];

                        xor2_a[j+272] = temp[33][2*j +: 2];
                        xor2_b[j+272] = ROT[2][2*j +: 2];

                        xor2_a[j+280] = temp[34][2*j +: 2];
                        xor2_b[j+280] = S_reg_A_r[2][2*j +: 2];

                        xor2_a[j+288] = temp[34][2*j +: 2];
                        xor2_b[j+288] = S_reg_A_r[7][2*j +: 2];

                        xor2_a[j+296] = temp[34][2*j +: 2];
                        xor2_b[j+296] = S_reg_A_r[12][2*j +: 2];

                        xor2_a[j+304] = temp[34][2*j +: 2];
                        xor2_b[j+304] = S_reg_A_r[17][2*j +: 2];

                        xor2_a[j+312] = temp[34][2*j +: 2];
                        xor2_b[j+312] = S_reg_A_r[22][2*j +: 2];

                        xor2_a[j+320] = S_reg_A_r[3][2*j +: 2];
                        xor2_b[j+320] = S_reg_A_r[8][2*j +: 2];

                        xor2_a[j+328] = temp[40][2*j +: 2];
                        xor2_b[j+328] = S_reg_A_r[13][2*j +: 2];

                        xor2_a[j+336] = temp[41][2*j +: 2];
                        xor2_b[j+336] = S_reg_A_r[18][2*j +: 2];

                        xor2_a[j+344] = temp[42][2*j +: 2];
                        xor2_b[j+344] = S_reg_A_r[23][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+360] = S_reg_A_r[2][2*j +: 2];
                        xor2_b[j+360] = S_reg_A_r[7][2*j +: 2];

                        xor2_a[j+368] = temp[45][2*j +: 2];
                        xor2_b[j+368] = S_reg_A_r[12][2*j +: 2];

                        xor2_a[j+376] = temp[46][2*j +: 2];
                        xor2_b[j+376] = S_reg_A_r[17][2*j +: 2];

                        xor2_a[j+384] = temp[47][2*j +: 2];
                        xor2_b[j+384] = S_reg_A_r[22][2*j +: 2];

                        xor2_a[j+392] = temp[48][2*j +: 2];
                        xor2_b[j+392] = ROT[3][2*j +: 2];

                        xor2_a[j+400] = temp[49][2*j +: 2];
                        xor2_b[j+400] = S_reg_A_r[3][2*j +: 2];

                        xor2_a[j+408] = temp[49][2*j +: 2];
                        xor2_b[j+408] = S_reg_A_r[8][2*j +: 2];

                        xor2_a[j+416] = temp[49][2*j +: 2];
                        xor2_b[j+416] = S_reg_A_r[13][2*j +: 2];

                        xor2_a[j+424] = temp[49][2*j +: 2];
                        xor2_b[j+424] = S_reg_A_r[18][2*j +: 2];

                        xor2_a[j+432] = temp[49][2*j +: 2];
                        xor2_b[j+432] = S_reg_A_r[23][2*j +: 2];

                        xor2_a[j+440] = S_reg_A_r[4][2*j +: 2];
                        xor2_b[j+440] = S_reg_A_r[9][2*j +: 2];

                        xor2_a[j+448] = temp[55][2*j +: 2];
                        xor2_b[j+448] = S_reg_A_r[14][2*j +: 2];

                        xor2_a[j+456] = temp[56][2*j +: 2];
                        xor2_b[j+456] = S_reg_A_r[19][2*j +: 2];

                        xor2_a[j+464] = temp[57][2*j +: 2];
                        xor2_b[j+464] = S_reg_A_r[24][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+480] = S_reg_A_r[3][2*j +: 2];
                        xor2_b[j+480] = S_reg_A_r[8][2*j +: 2];

                        xor2_a[j+488] = temp[60][2*j +: 2];
                        xor2_b[j+488] = S_reg_A_r[13][2*j +: 2];

                        xor2_a[j+496] = temp[61][2*j +: 2];
                        xor2_b[j+496] = S_reg_A_r[18][2*j +: 2];

                        xor2_a[j+504] = temp[62][2*j +: 2];
                        xor2_b[j+504] = S_reg_A_r[23][2*j +: 2];

                        xor2_a[j+512] = temp[63][2*j +: 2];
                        xor2_b[j+512] = ROT[4][2*j +: 2];

                        xor2_a[j+520] = temp[64][2*j +: 2];
                        xor2_b[j+520] = S_reg_A_r[4][2*j +: 2];

                        xor2_a[j+528] = temp[64][2*j +: 2];
                        xor2_b[j+528] = S_reg_A_r[9][2*j +: 2];

                        xor2_a[j+536] = temp[64][2*j +: 2];
                        xor2_b[j+536] = S_reg_A_r[14][2*j +: 2];

                        xor2_a[j+544] = temp[64][2*j +: 2];
                        xor2_b[j+544] = S_reg_A_r[19][2*j +: 2];

                        xor2_a[j+552] = temp[64][2*j +: 2];
                        xor2_b[j+552] = S_reg_A_r[24][2*j +: 2];

                        xor2_a[j+560] = S_reg_A_r[0][2*j +: 2];
                        xor2_b[j+560] = S_reg_A_r[5][2*j +: 2];

                        xor2_a[j+568] = temp[70][2*j +: 2];
                        xor2_b[j+568] = S_reg_A_r[10][2*j +: 2];

                        xor2_a[j+576] = temp[71][2*j +: 2];
                        xor2_b[j+576] = S_reg_A_r[15][2*j +: 2];

                        xor2_a[j+584] = temp[72][2*j +: 2];
                        xor2_b[j+584] = S_reg_A_r[20][2*j +: 2];
                    end

                    //---------------------------------------------//
                    
                end
                else begin
                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[4][2*j +: 2];
                        xor2_b[j] = S_reg_B_r[9][2*j +: 2];

                        xor2_a[j+8] = temp[0][2*j +: 2];
                        xor2_b[j+8] = S_reg_B_r[14][2*j +: 2];

                        xor2_a[j+16] = temp[1][2*j +: 2];
                        xor2_b[j+16] = S_reg_B_r[19][2*j +: 2];

                        xor2_a[j+24] = temp[2][2*j +: 2];
                        xor2_b[j+24] = S_reg_B_r[24][2*j +: 2];

                        xor2_a[j+32] = temp[3][2*j +: 2];
                        xor2_b[j+32] = ROT[0][2*j +: 2];

                        xor2_a[j+40] = temp[4][2*j +: 2];
                        xor2_b[j+40] = S_reg_B_r[0][2*j +: 2];

                        xor2_a[j+48] = temp[4][2*j +: 2];
                        xor2_b[j+48] = S_reg_B_r[5][2*j +: 2];

                        xor2_a[j+56] = temp[4][2*j +: 2];
                        xor2_b[j+56] = S_reg_B_r[10][2*j +: 2];

                        xor2_a[j+64] = temp[4][2*j +: 2];
                        xor2_b[j+64] = S_reg_B_r[15][2*j +: 2];

                        xor2_a[j+72] = temp[4][2*j +: 2];
                        xor2_b[j+72] = S_reg_B_r[20][2*j +: 2];

                        xor2_a[j+80] = S_reg_B_r[1][2*j +: 2];
                        xor2_b[j+80] = S_reg_B_r[6][2*j +: 2];

                        xor2_a[j+88] = temp[10][2*j +: 2];
                        xor2_b[j+88] = S_reg_B_r[11][2*j +: 2];

                        xor2_a[j+96] = temp[11][2*j +: 2];
                        xor2_b[j+96] = S_reg_B_r[16][2*j +: 2];

                        xor2_a[j+104] = temp[12][2*j +: 2];
                        xor2_b[j+104] = S_reg_B_r[21][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+120] = S_reg_B_r[0][2*j +: 2];
                        xor2_b[j+120] = S_reg_B_r[5][2*j +: 2];

                        xor2_a[j+128] = temp[15][2*j +: 2];
                        xor2_b[j+128] = S_reg_B_r[10][2*j +: 2];

                        xor2_a[j+136] = temp[16][2*j +: 2];
                        xor2_b[j+136] = S_reg_B_r[15][2*j +: 2];

                        xor2_a[j+144] = temp[17][2*j +: 2];
                        xor2_b[j+144] = S_reg_B_r[20][2*j +: 2];

                        xor2_a[j+152] = temp[18][2*j +: 2];
                        xor2_b[j+152] = ROT[1][2*j +: 2];

                        xor2_a[j+160] = temp[19][2*j +: 2];
                        xor2_b[j+160] = S_reg_B_r[1][2*j +: 2];

                        xor2_a[j+168] = temp[19][2*j +: 2];
                        xor2_b[j+168] = S_reg_B_r[6][2*j +: 2];

                        xor2_a[j+176] = temp[19][2*j +: 2];
                        xor2_b[j+176] = S_reg_B_r[11][2*j +: 2];

                        xor2_a[j+184] = temp[19][2*j +: 2];
                        xor2_b[j+184] = S_reg_B_r[16][2*j +: 2];

                        xor2_a[j+192] = temp[19][2*j +: 2];
                        xor2_b[j+192] = S_reg_B_r[21][2*j +: 2];

                        xor2_a[j+200] = S_reg_B_r[2][2*j +: 2];
                        xor2_b[j+200] = S_reg_B_r[7][2*j +: 2];

                        xor2_a[j+208] = temp[25][2*j +: 2];
                        xor2_b[j+208] = S_reg_B_r[12][2*j +: 2];

                        xor2_a[j+216] = temp[26][2*j +: 2];
                        xor2_b[j+216] = S_reg_B_r[17][2*j +: 2];

                        xor2_a[j+224] = temp[27][2*j +: 2];
                        xor2_b[j+224] = S_reg_B_r[22][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+240] = S_reg_B_r[1][2*j +: 2];
                        xor2_b[j+240] = S_reg_B_r[6][2*j +: 2];

                        xor2_a[j+248] = temp[30][2*j +: 2];
                        xor2_b[j+248] = S_reg_B_r[11][2*j +: 2];

                        xor2_a[j+256] = temp[31][2*j +: 2];
                        xor2_b[j+256] = S_reg_B_r[16][2*j +: 2];

                        xor2_a[j+264] = temp[32][2*j +: 2];
                        xor2_b[j+264] = S_reg_B_r[21][2*j +: 2];

                        xor2_a[j+272] = temp[33][2*j +: 2];
                        xor2_b[j+272] = ROT[2][2*j +: 2];

                        xor2_a[j+280] = temp[34][2*j +: 2];
                        xor2_b[j+280] = S_reg_B_r[2][2*j +: 2];

                        xor2_a[j+288] = temp[34][2*j +: 2];
                        xor2_b[j+288] = S_reg_B_r[7][2*j +: 2];

                        xor2_a[j+296] = temp[34][2*j +: 2];
                        xor2_b[j+296] = S_reg_B_r[12][2*j +: 2];

                        xor2_a[j+304] = temp[34][2*j +: 2];
                        xor2_b[j+304] = S_reg_B_r[17][2*j +: 2];

                        xor2_a[j+312] = temp[34][2*j +: 2];
                        xor2_b[j+312] = S_reg_B_r[22][2*j +: 2];

                        xor2_a[j+320] = S_reg_B_r[3][2*j +: 2];
                        xor2_b[j+320] = S_reg_B_r[8][2*j +: 2];

                        xor2_a[j+328] = temp[40][2*j +: 2];
                        xor2_b[j+328] = S_reg_B_r[13][2*j +: 2];

                        xor2_a[j+336] = temp[41][2*j +: 2];
                        xor2_b[j+336] = S_reg_B_r[18][2*j +: 2];

                        xor2_a[j+344] = temp[42][2*j +: 2];
                        xor2_b[j+344] = S_reg_B_r[23][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+360] = S_reg_B_r[2][2*j +: 2];
                        xor2_b[j+360] = S_reg_B_r[7][2*j +: 2];

                        xor2_a[j+368] = temp[45][2*j +: 2];
                        xor2_b[j+368] = S_reg_B_r[12][2*j +: 2];

                        xor2_a[j+376] = temp[46][2*j +: 2];
                        xor2_b[j+376] = S_reg_B_r[17][2*j +: 2];

                        xor2_a[j+384] = temp[47][2*j +: 2];
                        xor2_b[j+384] = S_reg_B_r[22][2*j +: 2];

                        xor2_a[j+392] = temp[48][2*j +: 2];
                        xor2_b[j+392] = ROT[3][2*j +: 2];

                        xor2_a[j+400] = temp[49][2*j +: 2];
                        xor2_b[j+400] = S_reg_B_r[3][2*j +: 2];

                        xor2_a[j+408] = temp[49][2*j +: 2];
                        xor2_b[j+408] = S_reg_B_r[8][2*j +: 2];

                        xor2_a[j+416] = temp[49][2*j +: 2];
                        xor2_b[j+416] = S_reg_B_r[13][2*j +: 2];

                        xor2_a[j+424] = temp[49][2*j +: 2];
                        xor2_b[j+424] = S_reg_B_r[18][2*j +: 2];

                        xor2_a[j+432] = temp[49][2*j +: 2];
                        xor2_b[j+432] = S_reg_B_r[23][2*j +: 2];

                        xor2_a[j+440] = S_reg_B_r[4][2*j +: 2];
                        xor2_b[j+440] = S_reg_B_r[9][2*j +: 2];

                        xor2_a[j+448] = temp[55][2*j +: 2];
                        xor2_b[j+448] = S_reg_B_r[14][2*j +: 2];

                        xor2_a[j+456] = temp[56][2*j +: 2];
                        xor2_b[j+456] = S_reg_B_r[19][2*j +: 2];

                        xor2_a[j+464] = temp[57][2*j +: 2];
                        xor2_b[j+464] = S_reg_B_r[24][2*j +: 2];
                    end

                    //---------------------------------------------//

                    for(j=0; j<8; j=j+1) begin
                        xor2_a[j+480] = S_reg_B_r[3][2*j +: 2];
                        xor2_b[j+480] = S_reg_B_r[8][2*j +: 2];

                        xor2_a[j+488] = temp[60][2*j +: 2];
                        xor2_b[j+488] = S_reg_B_r[13][2*j +: 2];

                        xor2_a[j+496] = temp[61][2*j +: 2];
                        xor2_b[j+496] = S_reg_B_r[18][2*j +: 2];

                        xor2_a[j+504] = temp[62][2*j +: 2];
                        xor2_b[j+504] = S_reg_B_r[23][2*j +: 2];

                        xor2_a[j+512] = temp[63][2*j +: 2];
                        xor2_b[j+512] = ROT[4][2*j +: 2];

                        xor2_a[j+520] = temp[64][2*j +: 2];
                        xor2_b[j+520] = S_reg_B_r[4][2*j +: 2];

                        xor2_a[j+528] = temp[64][2*j +: 2];
                        xor2_b[j+528] = S_reg_B_r[9][2*j +: 2];

                        xor2_a[j+536] = temp[64][2*j +: 2];
                        xor2_b[j+536] = S_reg_B_r[14][2*j +: 2];

                        xor2_a[j+544] = temp[64][2*j +: 2];
                        xor2_b[j+544] = S_reg_B_r[19][2*j +: 2];

                        xor2_a[j+552] = temp[64][2*j +: 2];
                        xor2_b[j+552] = S_reg_B_r[24][2*j +: 2];

                        xor2_a[j+560] = S_reg_B_r[0][2*j +: 2];
                        xor2_b[j+560] = S_reg_B_r[5][2*j +: 2];

                        xor2_a[j+568] = temp[70][2*j +: 2];
                        xor2_b[j+568] = S_reg_B_r[10][2*j +: 2];

                        xor2_a[j+576] = temp[71][2*j +: 2];
                        xor2_b[j+576] = S_reg_B_r[15][2*j +: 2];

                        xor2_a[j+584] = temp[72][2*j +: 2];
                        xor2_b[j+584] = S_reg_B_r[20][2*j +: 2];
                    end

                    //---------------------------------------------//
                end
            end


            S_STAGE2:   begin
                if(~A_or_B_r) begin
                    for (j=0; j<8; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[0][2*j +: 2];
                    end

                    for (j=8; j<16; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[6][2*(j-8) +: 2];
                    end

                    for (j=16; j<24; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[12][2*(j-16) +: 2];
                    end

                    for (j=24; j<32; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[18][2*(j-24) +: 2];
                    end

                    for (j=32; j<40; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[24][2*(j-32) +: 2];
                    end 

                    for (j=40; j<48; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[3][2*(j-40) +: 2];
                    end

                    for (j=48; j<56; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[9][2*(j-48) +: 2];
                    end

                    for (j=56; j<64; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[10][2*(j-56) +: 2];
                    end

                    for (j=64; j<72; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[16][2*(j-64) +: 2];
                    end

                    for (j=72; j<80; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[22][2*(j-72) +: 2];
                    end

                    for (j=80; j<88; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[1][2*(j-80) +: 2];
                    end

                    for (j=88; j<96; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[7][2*(j-88) +: 2];
                    end

                    for (j=96; j<104; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[13][2*(j-96) +: 2];
                    end

                    for (j=104; j<112; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[19][2*(j-104) +: 2];
                    end

                    for (j=112; j<120; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[20][2*(j-112) +: 2];
                    end 

                    for (j=0; j<8; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[6][2*j +: 2] & S_reg_A_r[12][2*j +: 2];
                    end

                    for (j=8; j<16; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[12][2*(j-8) +: 2] & S_reg_A_r[18][2*(j-8) +: 2];
                    end

                    for (j=16; j<24; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[18][2*(j-16) +: 2] & S_reg_A_r[24][2*(j-16) +: 2];
                    end

                    for (j=24; j<32; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[24][2*(j-24) +: 2] & S_reg_A_r[0][2*(j-24) +: 2];
                    end

                    for (j=32; j<40; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[0][2*(j-32) +: 2] & S_reg_A_r[6][2*(j-32) +: 2];
                    end

                    for (j=40; j<48; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[9][2*(j-40) +: 2] & S_reg_A_r[10][2*(j-40) +: 2];
                    end

                    for (j=48; j<56; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[10][2*(j-48) +: 2] & S_reg_A_r[16][2*(j-48) +: 2];
                    end

                    for (j=56; j<64; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[16][2*(j-56) +: 2] & S_reg_A_r[22][2*(j-56) +: 2];
                    end

                    for (j=64; j<72; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[22][2*(j-64) +: 2] & S_reg_A_r[3][2*(j-64) +: 2];
                    end

                    for (j=72; j<80; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[3][2*(j-72) +: 2] & S_reg_A_r[9][2*(j-72) +: 2];
                    end

                    for (j=80; j<88; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[7][2*(j-80) +: 2] & S_reg_A_r[13][2*(j-80) +: 2];
                    end

                    for (j=88; j<96; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[13][2*(j-88) +: 2] & S_reg_A_r[19][2*(j-88) +: 2];
                    end

                    for (j=96; j<104; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[19][2*(j-96) +: 2] & S_reg_A_r[20][2*(j-96) +: 2];
                    end

                    for (j=104; j<112; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[20][2*(j-104) +: 2] & S_reg_A_r[1][2*(j-104) +: 2];
                    end

                    for (j=112; j<120; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[1][2*(j-112) +: 2] & S_reg_A_r[7][2*(j-112) +: 2];
                    end

                    //-------------------------------------------------//


                    for (j=120; j<128; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[4][2*(j-120) +: 2];
                    end

                    for (j=128; j<136; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[5][2*(j-128) +: 2];
                    end

                    for (j=136; j<144; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[11][2*(j-136) +: 2];
                    end

                    for (j=144; j<152; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[17][2*(j-144) +: 2];
                    end

                    for (j=152; j<160; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[23][2*(j-152) +: 2];
                    end

                    for (j=160; j<168; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[2][2*(j-160) +: 2];
                    end

                    for (j=168; j<176; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[8][2*(j-168) +: 2];
                    end

                    for (j=176; j<184; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[14][2*(j-176) +: 2];
                    end

                    for (j=184; j<192; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[15][2*(j-184) +: 2];
                    end

                    for (j=192; j<200; j=j+1) begin
                        xor2_a[j] = S_reg_A_r[21][2*(j-192) +: 2];
                    end 

                    xor2_a[200] = xor2_out[0];
                    xor2_a[201] = xor2_out[1];
                    xor2_a[202] = xor2_out[2];
                    xor2_a[203] = xor2_out[3];
                    xor2_a[204] = xor2_out[4];
                    xor2_a[205] = xor2_out[5];
                    xor2_a[206] = xor2_out[6];
                    xor2_a[207] = xor2_out[7];


                    for (j=120; j<128; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[5][2*(j-120) +: 2] & S_reg_A_r[11][2*(j-120) +: 2];
                    end

                    for (j=128; j<136; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[11][2*(j-128) +: 2] & S_reg_A_r[17][2*(j-128) +: 2];
                    end

                    for (j=136; j<144; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[17][2*(j-136) +: 2] & S_reg_A_r[23][2*(j-136) +: 2];
                    end

                    for (j=144; j<152; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[23][2*(j-144) +: 2] & S_reg_A_r[4][2*(j-144) +: 2];
                    end

                    for (j=152; j<160; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[4][2*(j-152) +: 2] & S_reg_A_r[5][2*(j-152) +: 2];
                    end

                    for (j=160; j<168; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[8][2*(j-160) +: 2] & S_reg_A_r[14][2*(j-160) +: 2];
                    end

                    for (j=168; j<176; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[14][2*(j-168) +: 2] & S_reg_A_r[15][2*(j-168) +: 2];
                    end

                    for (j=176; j<184; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[15][2*(j-176) +: 2] & S_reg_A_r[21][2*(j-176) +: 2];
                    end

                    for (j=184; j<192; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[21][2*(j-184) +: 2] & S_reg_A_r[2][2*(j-184) +: 2];
                    end

                    for (j=192; j<200; j=j+1) begin
                        xor2_b[j] = ~S_reg_A_r[2][2*(j-192) +: 2] & S_reg_A_r[8][2*(j-192) +: 2];
                    end
                    
                    case(count_iter_r)
                        5'd0, 5'd5: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd1: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd2: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd3: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd4, 5'd12: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd6: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd7, 5'd10: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd8: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd9: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd11, 5'd19: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd13: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd14: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd15: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd16: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd17: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd18: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end
                    endcase

                end
                else begin

                    for (j=0; j<8; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[0][2*j +: 2];
                    end

                    for (j=8; j<16; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[6][2*(j-8) +: 2];
                    end

                    for (j=16; j<24; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[12][2*(j-16) +: 2];
                    end

                    for (j=24; j<32; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[18][2*(j-24) +: 2];
                    end

                    for (j=32; j<40; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[24][2*(j-32) +: 2];
                    end 

                    for (j=40; j<48; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[3][2*(j-40) +: 2];
                    end

                    for (j=48; j<56; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[9][2*(j-48) +: 2];
                    end

                    for (j=56; j<64; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[10][2*(j-56) +: 2];
                    end

                    for (j=64; j<72; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[16][2*(j-64) +: 2];
                    end

                    for (j=72; j<80; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[22][2*(j-72) +: 2];
                    end

                    for (j=80; j<88; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[1][2*(j-80) +: 2];
                    end

                    for (j=88; j<96; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[7][2*(j-88) +: 2];
                    end

                    for (j=96; j<104; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[13][2*(j-96) +: 2];
                    end

                    for (j=104; j<112; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[19][2*(j-104) +: 2];
                    end

                    for (j=112; j<120; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[20][2*(j-112) +: 2];
                    end 

                    for (j=0; j<8; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[6][2*j +: 2] & S_reg_B_r[12][2*j +: 2];
                    end

                    for (j=8; j<16; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[12][2*(j-8) +: 2] & S_reg_B_r[18][2*(j-8) +: 2];
                    end

                    for (j=16; j<24; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[18][2*(j-16) +: 2] & S_reg_B_r[24][2*(j-16) +: 2];
                    end

                    for (j=24; j<32; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[24][2*(j-24) +: 2] & S_reg_B_r[0][2*(j-24) +: 2];
                    end

                    for (j=32; j<40; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[0][2*(j-32) +: 2] & S_reg_B_r[6][2*(j-32) +: 2];
                    end

                    for (j=40; j<48; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[9][2*(j-40) +: 2] & S_reg_B_r[10][2*(j-40) +: 2];
                    end

                    for (j=48; j<56; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[10][2*(j-48) +: 2] & S_reg_B_r[16][2*(j-48) +: 2];
                    end

                    for (j=56; j<64; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[16][2*(j-56) +: 2] & S_reg_B_r[22][2*(j-56) +: 2];
                    end

                    for (j=64; j<72; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[22][2*(j-64) +: 2] & S_reg_B_r[3][2*(j-64) +: 2];
                    end

                    for (j=72; j<80; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[3][2*(j-72) +: 2] & S_reg_B_r[9][2*(j-72) +: 2];
                    end

                    for (j=80; j<88; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[7][2*(j-80) +: 2] & S_reg_B_r[13][2*(j-80) +: 2];
                    end

                    for (j=88; j<96; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[13][2*(j-88) +: 2] & S_reg_B_r[19][2*(j-88) +: 2];
                    end

                    for (j=96; j<104; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[19][2*(j-96) +: 2] & S_reg_B_r[20][2*(j-96) +: 2];
                    end

                    for (j=104; j<112; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[20][2*(j-104) +: 2] & S_reg_B_r[1][2*(j-104) +: 2];
                    end

                    for (j=112; j<120; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[1][2*(j-112) +: 2] & S_reg_B_r[7][2*(j-112) +: 2];
                    end

                    //-------------------------------------------------//


                    for (j=120; j<128; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[4][2*(j-120) +: 2];
                    end

                    for (j=128; j<136; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[5][2*(j-128) +: 2];
                    end

                    for (j=136; j<144; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[11][2*(j-136) +: 2];
                    end

                    for (j=144; j<152; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[17][2*(j-144) +: 2];
                    end

                    for (j=152; j<160; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[23][2*(j-152) +: 2];
                    end

                    for (j=160; j<168; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[2][2*(j-160) +: 2];
                    end

                    for (j=168; j<176; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[8][2*(j-168) +: 2];
                    end

                    for (j=176; j<184; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[14][2*(j-176) +: 2];
                    end

                    for (j=184; j<192; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[15][2*(j-184) +: 2];
                    end

                    for (j=192; j<200; j=j+1) begin
                        xor2_a[j] = S_reg_B_r[21][2*(j-192) +: 2];
                    end 

                    xor2_a[200] = xor2_out[0];
                    xor2_a[201] = xor2_out[1];
                    xor2_a[202] = xor2_out[2];
                    xor2_a[203] = xor2_out[3];
                    xor2_a[204] = xor2_out[4];
                    xor2_a[205] = xor2_out[5];
                    xor2_a[206] = xor2_out[6];
                    xor2_a[207] = xor2_out[7];


                    for (j=120; j<128; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[5][2*(j-120) +: 2] & S_reg_B_r[11][2*(j-120) +: 2];
                    end

                    for (j=128; j<136; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[11][2*(j-128) +: 2] & S_reg_B_r[17][2*(j-128) +: 2];
                    end

                    for (j=136; j<144; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[17][2*(j-136) +: 2] & S_reg_B_r[23][2*(j-136) +: 2];
                    end

                    for (j=144; j<152; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[23][2*(j-144) +: 2] & S_reg_B_r[4][2*(j-144) +: 2];
                    end

                    for (j=152; j<160; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[4][2*(j-152) +: 2] & S_reg_B_r[5][2*(j-152) +: 2];
                    end

                    for (j=160; j<168; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[8][2*(j-160) +: 2] & S_reg_B_r[14][2*(j-160) +: 2];
                    end

                    for (j=168; j<176; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[14][2*(j-168) +: 2] & S_reg_B_r[15][2*(j-168) +: 2];
                    end

                    for (j=176; j<184; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[15][2*(j-176) +: 2] & S_reg_B_r[21][2*(j-176) +: 2];
                    end

                    for (j=184; j<192; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[21][2*(j-184) +: 2] & S_reg_B_r[2][2*(j-184) +: 2];
                    end

                    for (j=192; j<200; j=j+1) begin
                        xor2_b[j] = ~S_reg_B_r[2][2*(j-192) +: 2] & S_reg_B_r[8][2*(j-192) +: 2];
                    end
                    
                    case(count_iter_r)
                        5'd0, 5'd5: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd1: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd2: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd3: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd4, 5'd12: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd6: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd7, 5'd10: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd8: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd9: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd11, 5'd19: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd13: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd14: begin
                            xor2_b[200] = 2'b01;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd15: begin
                            xor2_b[200] = 2'b11;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd16: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end

                        5'd17: begin
                            xor2_b[200] = 2'b00;
                            xor2_b[201] = 2'b00;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b10;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b00;
                        end

                        5'd18: begin
                            xor2_b[200] = 2'b10;
                            xor2_b[201] = 2'b10;
                            xor2_b[202] = 2'b00;
                            xor2_b[203] = 2'b00;
                            xor2_b[204] = 2'b00;
                            xor2_b[205] = 2'b00;
                            xor2_b[206] = 2'b00;
                            xor2_b[207] = 2'b10;
                        end
                    endcase
                end
            end


            S_OUT:  begin
                if(~A_or_B_r) begin
                    case(count_get_r)
                        3'd1: begin
                            for(j=0; j<56; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[4][2*(j-32) +: 2];
                            end

                            for(j=40; j<48; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[5][2*(j-40) +: 2];
                            end
                            
                            for(j=48; j<56; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[6][2*(j-48) +: 2];
                            end
                        end

                        3'd2: begin
                            for(j=0; j<48; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[4][2*(j-32) +: 2];
                            end

                            for(j=40; j<48; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[5][2*(j-40) +: 2];
                            end
                        end

                        3'd3: begin
                            for(j=0; j<40; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[4][2*(j-32) +: 2];
                            end
                        end

                        3'd4: begin
                            for(j=0; j<32; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[3][2*(j-24) +: 2];
                            end  
                        end

                        3'd5: begin
                            for(j=0; j<24; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[2][2*(j-16) +: 2];
                            end
                        end

                        3'd6: begin
                            for(j=0; j<16; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[1][2*(j-8) +: 2];
                            end
                        end

                        3'd7: begin
                            for(j=0; j<8; j=j+1) begin
                                xor2_a[j] = extra_A_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_A_r[0][2*j +: 2];
                            end
                        end
                    endcase
                end
                else begin
                    case(count_get_r)
                        3'd1: begin
                            for(j=0; j<56; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[4][2*(j-32) +: 2];
                            end

                            for(j=40; j<48; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[5][2*(j-40) +: 2];
                            end
                            
                            for(j=48; j<56; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[6][2*(j-48) +: 2];
                            end
                        end

                        3'd2: begin
                            for(j=0; j<48; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[4][2*(j-32) +: 2];
                            end

                            for(j=40; j<48; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[5][2*(j-40) +: 2];
                            end
                        end

                        3'd3: begin
                            for(j=0; j<40; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[3][2*(j-24) +: 2];
                            end 
                            
                            for(j=32; j<40; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[4][2*(j-32) +: 2];
                            end
                        end

                        3'd4: begin
                            for(j=0; j<32; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[2][2*(j-16) +: 2];
                            end

                            for(j=24; j<32; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[3][2*(j-24) +: 2];
                            end  
                        end

                        3'd5: begin
                            for(j=0; j<24; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end

                            for(j=16; j<24; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[2][2*(j-16) +: 2];
                            end
                        end

                        3'd6: begin
                            for(j=0; j<16; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end

                            for(j=8; j<16; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[1][2*(j-8) +: 2];
                            end
                        end

                        3'd7: begin
                            for(j=0; j<8; j=j+1) begin
                                xor2_a[j] = extra_B_r[2*j +: 2];
                            end

                            for(j=0; j<8; j=j+1) begin
                                xor2_b[j] = S_reg_B_r[0][2*j +: 2];
                            end
                        end
                    endcase
                end
            end

            S_TEST: begin
                case(count_iter_r)
                    5'd0: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b00;
                            xor2_b[j] = 2'b00;
                        end
                    end

                    5'd1: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b00;
                            xor2_b[j] = 2'b01;
                        end
                    end

                    5'd2: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b00;
                            xor2_b[j] = 2'b10;
                        end
                    end

                    5'd3: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b00;
                            xor2_b[j] = 2'b11;
                        end
                    end

                    5'd4: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b01;
                            xor2_b[j] = 2'b00;
                        end
                    end

                    5'd5: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b01;
                            xor2_b[j] = 2'b01;
                        end
                    end

                    5'd6: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b01;
                            xor2_b[j] = 2'b10;
                        end
                    end

                    5'd7: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b01;
                            xor2_b[j] = 2'b11;
                        end
                    end

                    5'd8: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b10;
                            xor2_b[j] = 2'b00;
                        end
                    end

                    5'd9: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b10;
                            xor2_b[j] = 2'b01;
                        end
                    end

                    5'd10: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b10;
                            xor2_b[j] = 2'b10;
                        end
                    end

                    5'd11: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b10;
                            xor2_b[j] = 2'b11;
                        end
                    end

                    5'd12: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b11;
                            xor2_b[j] = 2'b00;
                        end
                    end

                    5'd13: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b11;
                            xor2_b[j] = 2'b01;
                        end
                    end

                    5'd14: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b11;
                            xor2_b[j] = 2'b10;
                        end
                    end

                    5'd15: begin
                        for(j=0; j<600; j=j+1) begin
                            xor2_a[j] = 2'b11;
                            xor2_b[j] = 2'b11;
                        end
                    end
                endcase
            end
        endcase
    end

    //  for xor output
    assign ROT[0] = {temp[13][0 +: 15], temp[13][15]};
    assign ROT[1] = {temp[28][0 +: 15], temp[28][15]};
    assign ROT[2] = {temp[43][0 +: 15], temp[43][15]};
    assign ROT[3] = {temp[58][0 +: 15], temp[58][15]};
    assign ROT[4] = {temp[73][0 +: 15], temp[73][15]};

    always@ (*) begin
        for(i=0; i<75; i=i+1)
            temp[i] = { xor2_out[i*8+7],  xor2_out[i*8+6],  xor2_out[i*8+5],  xor2_out[i*8+4],  xor2_out[i*8+3],  xor2_out[i*8+2],  xor2_out[i*8+1], xor2_out[i*8] };
    end


    /////////////////////////////////////////////


    /////////////////////////////////////////////
    //  for is_last_r & A_or_B_r

    always@ (*) begin
        if(is_last_r) begin
            if(state_r == S_OUT && state_w != S_OUT) 
                is_last_w = 0;
            else
                is_last_w = 1;
        end
        else begin
            is_last_w = i_last_r;
        end
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)    is_last_r <= 0;
        else            is_last_r <= is_last_w;
    end

    always@ (*) begin
        A_or_B_w = 0;

        if(i_mode==2'b01) begin
            case(state_r)
                S_IDLE:                     A_or_B_w = 0;
                S_GET0, S_GET1, S_GET2:     A_or_B_w = (i_valid_r && ~A_or_B_r) ? 1'b1 : 1'b0; 
                default:                    A_or_B_w = ~A_or_B_r;
            endcase
        end                       
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)    A_or_B_r <= 0;
        else            A_or_B_r <= A_or_B_w;
    end

    /////////////////////////////////////////////



    /////////////////////////////////////////////
    // for count_iter_r, count_get_r

    always@ (*) begin
        count_iter_w = count_iter_r;

        case(state_r)
            S_STAGE2:                       count_iter_w = ((i_mode==2'b01 && A_or_B_r) || (i_mode==2'b00 && ~A_or_B_r)) ? count_iter_r + 5'd1 : count_iter_r;
            S_TEST:                         count_iter_w = count_iter_r + 5'd1;
            S_IDLE, S_TEST_OUT, S_OUT:      count_iter_w = 0;
        endcase
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)    count_iter_r <= 0;
        else            count_iter_r <= count_iter_w;
    end


    wire count_get_enable;
    assign count_get_enable = state_r==S_GET2;

    always@ (*) begin
        count_get_w = count_get_r;

        case(state_r)
            S_GET2: count_get_w = ((state_w != S_GET2 && i_last_r && i_mode==2'b00) || (state_w != S_GET2 && is_last_r && i_mode==2'b01 && A_or_B_r)) 
                                    ? 0 : (state_w != S_GET2) 
                                    ? count_get_r + 3'd1 : count_get_r; 
        endcase
    end


    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)                count_get_r <= 0;
        else if(count_get_enable)   count_get_r <= count_get_w;
    end

    /////////////////////////////////////////////

    /////////////////////////////////////////////
    // for extra A/B

    wire extra_A_enable;
    assign extra_A_enable = (state_r == S_GET0 || state_r == S_GET1 || state_r == S_GET2);

    always@ (*) begin
        extra_A_w = extra_A_r;

        if((state_r == S_GET0 || state_r == S_GET1 || state_r == S_GET2) && (i_valid))
            extra_A_w = i_data_a;
        else if(state_r == S_GET2 && ~A_or_B_r && i_valid_r) begin
            case(count_get_r)
                3'd0:   extra_A_w = { 16'd0 , extra_A_r[16 +: 112]};
                3'd1:   extra_A_w = { 32'd0 , extra_A_r[32 +: 96]};
                3'd2:   extra_A_w = { 48'd0 , extra_A_r[48 +: 80]};
                3'd3:   extra_A_w = { 64'd0 , extra_A_r[64 +: 64]};
                3'd4:   extra_A_w = { 80'd0 , extra_A_r[80 +: 48]};
                3'd5:   extra_A_w = { 96'd0 , extra_A_r[96 +: 32]};
                3'd6:   extra_A_w = { 112'd0 , extra_A_r[112 +: 16]};
                3'd7:   extra_A_w = 128'd0;
            endcase
        end
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)                extra_A_r <= 0;
        else if(extra_A_enable)     extra_A_r <= extra_A_w;
    end


    wire extra_B_enable;
    assign extra_B_enable = (state_r == S_GET0 || state_r == S_GET1 || state_r == S_GET2) && (i_mode == 2'b01);


    always@ (*) begin
        extra_B_w = extra_B_r;

        case(state_r)
            S_GET0, S_GET1: begin
                if(~A_or_B_r && i_valid && i_mode==2'b01) 
                    extra_B_w = i_data_b;
            end

            S_GET2: begin
                if(~A_or_B_r && i_valid && i_mode==2'b01)
                    extra_B_w = i_data_b;
                else if(A_or_B_r) begin
                    case(count_get_r)
                        3'd0:   extra_B_w = { 16'd0 ,  extra_B_r[16 +: 112] };
                        3'd1:   extra_B_w = { 32'd0 ,  extra_B_r[32 +: 96] };
                        3'd2:   extra_B_w = { 48'd0 ,  extra_B_r[48 +: 80] };
                        3'd3:   extra_B_w = { 64'd0 ,  extra_B_r[64 +: 64] };
                        3'd4:   extra_B_w = { 80'd0 ,  extra_B_r[80 +: 48] };
                        3'd5:   extra_B_w = { 96'd0 ,  extra_B_r[96 +: 32] };
                        3'd6:   extra_B_w = { 112'd0 , extra_B_r[112 +: 16] };
                        3'd7:   extra_B_w = 128'd0;
                    endcase
                end
            end
        endcase
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(~i_rst_n)                extra_B_r <= 0;
        else if(extra_B_enable)     extra_B_r <= extra_B_w;
    end

    /////////////////////////////////////////////

    /////////////////////////////////////////////
    // for BIST

    always @(*) begin
        case(count_iter_r)
            5'd0, 5'd5, 5'd10, 5'd15:  golden = 2'b00;
            5'd1, 5'd4, 5'd11, 5'd14:  golden = 2'b01;
            5'd2, 5'd7, 5'd8,  5'd13:  golden = 2'b10; 
            5'd3, 5'd6, 5'd9,  5'd12:  golden = 2'b11; 
            default:                   golden = 2'b00;
        endcase
    end

    always @(*) begin
        if(i_mode == 2'b11 && state_r==S_TEST) begin
            for(i=0; i<=74; i=i+1) 
                false[i] = ( temp[i] != {8{golden}} );
        end
        else begin
            false = 0;
        end
    end


    always@ (*) begin
        BIST_find = (&i_mode) && (|false);
    end

    integer t;
    always@ (*) begin
        o_BIST_id = 0;

        if(i_mode == 2'b11 && state_r==S_TEST) begin
            for(i=0; i<=74; i=i+1) begin
                if(false[i]) begin
                    for(t=0; t<8; t=t+1) begin
                        if(temp[i][2*t +: 2] != golden)
                            o_BIST_id = xor2_id[i*8 + t];
                    end  
                end
            end
        end
    end

endmodule
