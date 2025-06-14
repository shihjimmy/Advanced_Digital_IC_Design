`timescale 1ns / 1ps

module top #(
    parameter IN_DATA_WIDTH = 8,
    parameter OUT_DATA_WIDTH = 18
)( 
    input i_rst_n, 
    input i_clk, 
    input i_valid, 
    input [IN_DATA_WIDTH-1:0] i_data_r, 
    input [IN_DATA_WIDTH-1:0] i_data_g, 
    input [IN_DATA_WIDTH-1:0] i_data_b, 
    output [OUT_DATA_WIDTH-1:0] o_data, 
    output o_valid,
    output PGEN_RLE
);  
    localparam S_START = 0;
    localparam S_CALC_WRITE = 1;
    localparam S_STALL1 = 2;
    localparam S_STALL2 = 3;
    localparam S_OUT_PREP = 4;
    localparam S_OUT_READ = 5;
    localparam S_EXIT = 6;

    reg [2:0] state_r, state_w;
    reg  o_valid_r;
    wire o_valid_w;
    reg [OUT_DATA_WIDTH-1:0] o_data_r, o_data_w;

    assign o_data = o_data_r;
    assign o_valid = o_valid_r;
    assign o_valid_w = state_r==S_OUT_READ;

    reg  [10:0] r_count_r, r_count_w;
    reg  [10:0] g_count_r, g_count_w;
    reg  [10:0] b_count_r, b_count_w;
    reg  [44:0] dataout;

    /*---------------------------------------------------------*/
    //  For Run-Length Encoder and write controller
    wire i_start;
    wire o_rvalid, o_gvalid, o_bvalid;
    wire [44:0] o_r_datain, o_g_datain, o_b_datain;
    wire        r_select_r, g_select_r, b_select_r;
    wire [8:0]  r_index_r, g_index_r, b_index_r; 
    wire [44:0] o_r_bweb, o_g_bweb, o_b_bweb;

    RLE u_RLE(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n), 
        .i_start(i_start),
        .i_valid(i_valid),
        .i_data_r(i_data_r), 
        .i_data_g(i_data_g), 
        .i_data_b(i_data_b), 
        .o_rvalid(o_rvalid),
        .o_gvalid(o_gvalid), 
        .o_bvalid(o_bvalid),
        .o_r_bweb(o_r_bweb),
        .o_g_bweb(o_g_bweb),
        .o_b_bweb(o_b_bweb),
        .o_r_datain(o_r_datain),
        .o_g_datain(o_g_datain),
        .o_b_datain(o_b_datain),
        .r_select_r(r_select_r),
        .g_select_r(g_select_r),
        .b_select_r(b_select_r),
        .r_index_r(r_index_r),
        .g_index_r(g_index_r),
        .b_index_r(b_index_r)
    );

    /*---------------------------------------------------------*/


    /*---------------------------------------------------------*/
    // For Output controller
    wire i_output_start;
    wire r_now, g_now, b_now;
    wire out_select_r;
    wire out_select_past;
    wire [8:0] out_index_r;
    wire r_past, g_past, b_past;
    wire out_num;
    wire finish;
    
    assign i_output_start = (state_r==S_OUT_PREP || state_r==S_OUT_READ);

    OUTPUT_CONTROLLER u_OUTPUT_CONTROLLER(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n), 
        .i_start(i_output_start),
        .r_count(r_count_r),
        .g_count(g_count_r),
        .b_count(b_count_r),
        .r_now(r_now),
        .g_now(g_now),
        .b_now(b_now),
        .r_past(r_past),
        .g_past(g_past),
        .b_past(b_past),
        .out_select_r(out_select_r),
        .out_select_past(out_select_past),
        .out_index_r(out_index_r),
        .out_num(out_num),
        .finish(finish)  
    );
    /*---------------------------------------------------------*/

    /*---------------------------------------------------------*/
    //  For SRAMS
    reg [8:0] r_sram1_address, r_sram2_address;
    reg [8:0] g_sram1_address, g_sram2_address;
    reg [8:0] b_sram1_address, b_sram2_address;

    reg r_sram1_ceb, r_sram2_ceb;
    reg g_sram1_ceb, g_sram2_ceb;
    reg b_sram1_ceb, b_sram2_ceb;

    reg r_sram1_web, r_sram2_web;
    reg g_sram1_web, g_sram2_web;
    reg b_sram1_web, b_sram2_web;

    reg [44:0] r_sram1_datain, r_sram2_datain;
    reg [44:0] g_sram1_datain, g_sram2_datain;
    reg [44:0] b_sram1_datain, b_sram2_datain;

    reg [44:0] r_sram1_bweb, r_sram2_bweb;
    reg [44:0] g_sram1_bweb, g_sram2_bweb;
    reg [44:0] b_sram1_bweb, b_sram2_bweb;

    wire [44:0] r_sram1_dataout, r_sram2_dataout;
    wire [44:0] g_sram1_dataout, g_sram2_dataout;
    wire [44:0] b_sram1_dataout, b_sram2_dataout;

    wire r_sram1_finish, r_sram2_finish;
    wire g_sram1_finish, g_sram2_finish;
    wire b_sram1_finish, b_sram2_finish;

    TS1N16ADFPCLLLVTA512X45M4SWSHOD r_sram1( 
        .A       (r_sram1_address),
        .CEB     (r_sram1_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (r_sram1_web),  // write: low, read: high
        .D       (r_sram1_datain),
        .Q       (r_sram1_dataout),
        .BWEB    (r_sram1_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (r_sram1_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    TS1N16ADFPCLLLVTA512X45M4SWSHOD r_sram2( 
        .A       (r_sram2_address),
        .CEB     (r_sram2_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (r_sram2_web),  // write: low, read: high
        .D       (r_sram2_datain),
        .Q       (r_sram2_dataout),
        .BWEB    (r_sram2_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (r_sram2_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    TS1N16ADFPCLLLVTA512X45M4SWSHOD g_sram1( 
        .A       (g_sram1_address),
        .CEB     (g_sram1_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (g_sram1_web),  // write: low, read: high
        .D       (g_sram1_datain),
        .Q       (g_sram1_dataout),
        .BWEB    (g_sram1_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (g_sram1_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    TS1N16ADFPCLLLVTA512X45M4SWSHOD g_sram2( 
        .A       (g_sram2_address),
        .CEB     (g_sram2_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (g_sram2_web),  // write: low, read: high
        .D       (g_sram2_datain),
        .Q       (g_sram2_dataout),
        .BWEB    (g_sram2_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (g_sram2_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    TS1N16ADFPCLLLVTA512X45M4SWSHOD b_sram1( 
        .A       (b_sram1_address),
        .CEB     (b_sram1_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (b_sram1_web),  // write: low, read: high
        .D       (b_sram1_datain),
        .Q       (b_sram1_dataout),
        .BWEB    (b_sram1_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (b_sram1_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    TS1N16ADFPCLLLVTA512X45M4SWSHOD b_sram2( 
        .A       (b_sram2_address),
        .CEB     (b_sram2_ceb),  // active low
        .CLK     (i_clk),
        .WEB     (b_sram2_web),  // write: low, read: high
        .D       (b_sram2_datain),
        .Q       (b_sram2_dataout),
        .BWEB    (b_sram2_bweb),
        .RTSEL   (2'b01),
        .WTSEL   (2'b01),
        .SLP     (1'b0),
        .DSLP    (b_sram2_finish),
        .SD      (1'b0),
        .PUDELAY ()
    );

    /*---------------------------------------------------------*/
    // Power Gating
    assign PGEN_RLE = (state_r == S_OUT_PREP || state_r == S_OUT_READ || state_r == S_EXIT);


    assign r_sram1_finish = ( r_now && i_output_start && out_select_r && out_select_past ) || (g_now && (!r_past)) || (b_now);
    assign r_sram2_finish = ( ( (g_now) || (b_now) ) && (!r_past) ) || ( r_count_r<=10'd1023 && i_output_start);

    assign g_sram1_finish = ( g_now && i_output_start && out_select_r && out_select_past ) || (b_now && (!g_past));
    assign g_sram2_finish = ( (b_now) && (!g_past) ) || ( g_count_r<=10'd1023 && i_output_start);

    assign b_sram1_finish = ( b_now && i_output_start && out_select_r && out_select_past );
    assign b_sram2_finish = ( b_count_r<=10'd1023 && i_output_start);


    // CEB
    // For Sram Chip Enable
    always@ (*) begin
        r_sram1_ceb = 1'd1;

        if( (o_rvalid && !r_select_r) || (!r_sram1_finish && state_r>=S_OUT_PREP) )
            r_sram1_ceb = 1'b0;
    end

    always@ (*) begin
        r_sram2_ceb = 1'd1;

        if( (o_rvalid && r_select_r) || (!r_sram2_finish && state_r>=S_OUT_PREP) ) 
            r_sram2_ceb = 1'b0;
    end

    always@ (*) begin
        g_sram1_ceb = 1'd1;

        if( (o_gvalid && !g_select_r) || (!g_sram1_finish && state_r>=S_OUT_PREP) ) 
            g_sram1_ceb = 1'b0;
    end

    always@ (*) begin
        g_sram2_ceb = 1'd1;

        if( (o_gvalid && g_select_r) || (!g_sram2_finish && state_r>=S_OUT_PREP) ) 
            g_sram2_ceb = 1'b0;
    end

    always@ (*) begin
        b_sram1_ceb = 1'd1;

        if( (o_bvalid && !b_select_r) || (!b_sram1_finish && state_r>=S_OUT_PREP) ) 
            b_sram1_ceb = 1'b0;
    end

    always@ (*) begin
        b_sram2_ceb = 1'd1;

        if( (o_bvalid && b_select_r) || (!b_sram2_finish && state_r>=S_OUT_PREP) ) 
            b_sram2_ceb = 1'b0;
    end

    /*---------------------------------------------------------*/

    always@ (*) begin
        case( {r_past, g_past, b_past} )
            3'b100:     dataout = out_select_past ? r_sram2_dataout : r_sram1_dataout;
            3'b010:     dataout = out_select_past ? g_sram2_dataout : g_sram1_dataout;
            3'b001:     dataout = out_select_past ? b_sram2_dataout : b_sram1_dataout;
            default:    dataout = 0;
        endcase
    end


    always@ (*) begin
        case(out_num)
            1'd0:       o_data_w = dataout[0 +: 18];
            1'd1:       o_data_w = dataout[18 +: 18];
            default:    o_data_w = 0;       
        endcase
    end

    /*---------------------------------------------------------*/
    always@ (*) begin
        if(o_rvalid)                r_count_w = r_count_r + 1;
        else if(state_r==S_STALL2)  r_count_w = r_count_r - 1;
        else                        r_count_w = r_count_r;
    end

    always@ (*) begin
        if(o_gvalid)                g_count_w = g_count_r + 1;
        else if(state_r==S_STALL2)  g_count_w = g_count_r - 1;
        else                        g_count_w = g_count_r;
    end

    always@ (*) begin
        if(o_bvalid)                b_count_w = b_count_r + 1;
        else if(state_r==S_STALL2)  b_count_w = b_count_r - 1;
        else                        b_count_w = b_count_r;
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n)            r_count_r <= 0;
        else                    r_count_r <= r_count_w;
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n)            g_count_r <= 0;
        else                    g_count_r <= g_count_w;
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n)            b_count_r <= 0;
        else                    b_count_r <= b_count_w;
    end

    /*---------------------------------------------------------*/

    always@ (*) begin
        r_sram1_address = 0;

        if(o_rvalid && !r_select_r) 
            r_sram1_address = r_index_r;
        else if(r_now && i_output_start && !out_select_r)
            r_sram1_address = out_index_r;
    end

    always@ (*) begin
        r_sram2_address = 0;

        if(o_rvalid && r_select_r) 
            r_sram2_address = r_index_r;
        else if(r_now && i_output_start && out_select_r)
            r_sram2_address = out_index_r;
    end

    always@ (*) begin
        g_sram1_address = 0;

        if(o_gvalid && !g_select_r) 
            g_sram1_address = g_index_r;
        else if(g_now && i_output_start && !out_select_r)
            g_sram1_address = out_index_r;
    end

    always@ (*) begin
        g_sram2_address = 0;

        if(o_gvalid && g_select_r) 
            g_sram2_address = g_index_r;
        else if(g_now && i_output_start && out_select_r)
            g_sram2_address = out_index_r;
    end

    always@ (*) begin
        b_sram1_address = 0;

        if(o_bvalid && !b_select_r) 
            b_sram1_address = b_index_r;
        else if(b_now && i_output_start && !out_select_r)
            b_sram1_address = out_index_r;
    end

    always@ (*) begin
        b_sram2_address = 0;

        if(o_bvalid && b_select_r) 
            b_sram2_address = b_index_r;
        else if(b_now && i_output_start && out_select_r)
            b_sram2_address = out_index_r;
    end
    
    /*---------------------------------------------------------*/

    /*---------------------------------------------------------*/
    // For read/write
    always@ (*) begin
        r_sram1_web = 1'd1;

        if(o_rvalid && !r_select_r) 
            r_sram1_web = 1'b0;
    end

    always@ (*) begin
        r_sram2_web = 1'd1;

        if(o_rvalid && r_select_r) 
            r_sram2_web = 1'b0;
    end

    always@ (*) begin
        g_sram1_web = 1'd1;

        if(o_gvalid && !g_select_r) 
            g_sram1_web = 1'b0;
    end

    always@ (*) begin
        g_sram2_web = 1'd1;

        if(o_gvalid && g_select_r) 
            g_sram2_web = 1'b0;
    end

    always@ (*) begin
        b_sram1_web = 1'd1;

        if(o_bvalid && !b_select_r) 
            b_sram1_web = 1'b0;
    end

    always@ (*) begin
        b_sram2_web = 1'd1;

        if(o_bvalid && b_select_r) 
            b_sram2_web = 1'b0;
    end

    /*---------------------------------------------------------*/

    /*---------------------------------------------------------*/

    always@ (*) begin
        r_sram1_datain = 0;

        if(o_rvalid && !r_select_r) 
            r_sram1_datain = o_r_datain;
    end

    always@ (*) begin
        r_sram2_datain = 0;

        if(o_rvalid && r_select_r) 
            r_sram2_datain = o_r_datain;
    end

    always@ (*) begin
        g_sram1_datain = 0;

        if(o_gvalid && !g_select_r) 
            g_sram1_datain = o_g_datain;
    end

    always@ (*) begin
        g_sram2_datain = 0;

        if(o_gvalid && g_select_r) 
            g_sram2_datain = o_g_datain;
    end

    always@ (*) begin
        b_sram1_datain = 0;

        if(o_bvalid && !b_select_r) 
            b_sram1_datain = o_b_datain;
    end

    always@ (*) begin
        b_sram2_datain = 0;

        if(o_bvalid && b_select_r) 
            b_sram2_datain = o_b_datain;
    end

    /*---------------------------------------------------------*/

    always@ (*) begin
        r_sram1_bweb = {45{1'd1}};

        if(o_rvalid && !r_select_r) 
            r_sram1_bweb = o_r_bweb;
    end

    always@ (*) begin
        r_sram2_bweb = {45{1'd1}};

        if(o_rvalid && r_select_r) 
            r_sram2_bweb = o_r_bweb;
    end

    always@ (*) begin
        g_sram1_bweb = {45{1'd1}};

        if(o_gvalid && !g_select_r) 
            g_sram1_bweb = o_g_bweb;
    end

    always@ (*) begin
        g_sram2_bweb = {45{1'd1}};

        if(o_gvalid && g_select_r) 
            g_sram2_bweb = o_g_bweb;
    end

    always@ (*) begin
        b_sram1_bweb = {45{1'd1}};

        if(o_bvalid && !b_select_r) 
            b_sram1_bweb = o_b_bweb;
    end

    always@ (*) begin
        b_sram2_bweb = {45{1'd1}};

        if(o_bvalid && b_select_r) 
            b_sram2_bweb = o_b_bweb;
    end

    /*---------------------------------------------------------*/

    always@ (*) begin
        case(state_r)
            S_START:        state_w = (i_valid) ? S_CALC_WRITE : S_START;
            S_CALC_WRITE:   state_w = (!i_valid) ? S_STALL1 : S_CALC_WRITE;
            S_STALL1:       state_w = S_STALL2;
            S_STALL2:       state_w = S_OUT_PREP;
            S_OUT_PREP:     state_w = S_OUT_READ;
            S_OUT_READ:     state_w = (finish) ? S_EXIT : S_OUT_READ;
            S_EXIT:         state_w = S_EXIT;
            default:        state_w = S_START;
        endcase
    end

    assign i_start = (state_r==S_START && i_valid) || (state_r==S_CALC_WRITE && (!i_valid));

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            state_r <= S_START;
            o_valid_r <= 0;
            o_data_r  <= 0;
        end
        else begin
            state_r <= state_w;
            o_valid_r <= o_valid_w;
            o_data_r  <= o_data_w;
        end
    end

endmodule

module RLE #(
    parameter IN_DATA_WIDTH = 8,
    parameter OUT_DATA_WIDTH = 18
)(
    input                       i_clk,
    input                       i_rst_n, 
    input                       i_start,
    input                       i_valid,
    input [IN_DATA_WIDTH-1:0]   i_data_r, 
    input [IN_DATA_WIDTH-1:0]   i_data_g, 
    input [IN_DATA_WIDTH-1:0]   i_data_b, 
    output                      o_rvalid,
    output                      o_gvalid,
    output                      o_bvalid,
    output reg [44:0]           o_r_bweb,
    output reg [44:0]           o_g_bweb,
    output reg [44:0]           o_b_bweb,
    output reg [44:0]           o_r_datain,
    output reg [44:0]           o_g_datain,
    output reg [44:0]           o_b_datain,
    output reg                  r_select_r,
    output reg                  g_select_r,
    output reg                  b_select_r,
    output reg [8:0]            r_index_r,
    output reg [8:0]            g_index_r,
    output reg [8:0]            b_index_r
);
    reg i_start_r, i_valid_r;
    reg [IN_DATA_WIDTH-1:0] i_data_r_r;
    reg [IN_DATA_WIDTH-1:0] i_data_g_r;
    reg [IN_DATA_WIDTH-1:0] i_data_b_r; 
    
    reg [9:0] r_length_r, r_length_w;
    reg [9:0] g_length_r, g_length_w;
    reg [9:0] b_length_r, b_length_w;

    reg [7:0] r_data_r, r_data_w;
    reg [7:0] g_data_r, g_data_w;
    reg [7:0] b_data_r, b_data_w;

    reg         r_num_r, r_num_w, g_num_r, g_num_w, b_num_r, b_num_w;
    reg  [8:0]  r_index_w, g_index_w, b_index_w;
    reg         r_select_w, g_select_w, b_select_w;

    wire [OUT_DATA_WIDTH-1:0] o_rdata, o_gdata, o_bdata;

    wire switch_r, switch_b, switch_g;

    assign o_rvalid = (switch_r & i_valid_r & (!i_start_r)) || (!i_valid_r && i_start_r);
    assign o_gvalid = (switch_g & i_valid_r & (!i_start_r)) || (!i_valid_r && i_start_r);
    assign o_bvalid = (switch_b & i_valid_r & (!i_start_r)) || (!i_valid_r && i_start_r);
    assign o_rdata  = {r_data_r, r_length_r};
    assign o_gdata  = {g_data_r, g_length_r};
    assign o_bdata  = {b_data_r, b_length_r};

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            i_start_r  <= 0;
            i_valid_r  <= 0;
            i_data_r_r <= 0;
            i_data_g_r <= 0;
            i_data_b_r <= 0;
        end
        else begin
            i_start_r  <= i_start;
            i_valid_r  <= i_valid;
            i_data_r_r <= i_data_r;
            i_data_g_r <= i_data_g;
            i_data_b_r <= i_data_b;
        end
    end

    assign switch_r = ( $signed({1'd0, r_data_r}) - $signed({1'd0, i_data_r_r}) > 9'sd10) || ( $signed({1'd0, i_data_r_r}) - $signed({1'd0, r_data_r}) > 9'sd10);
    assign switch_g = ( $signed({1'd0, g_data_r}) - $signed({1'd0, i_data_g_r}) > 9'sd10) || ( $signed({1'd0, i_data_g_r}) - $signed({1'd0, g_data_r}) > 9'sd10);
    assign switch_b = ( $signed({1'd0, b_data_r}) - $signed({1'd0, i_data_b_r}) > 9'sd10) || ( $signed({1'd0, i_data_b_r}) - $signed({1'd0, b_data_r}) > 9'sd10);

    always@ (*) begin
        if(i_start_r || switch_r) begin
            r_data_w = i_data_r_r;
            r_length_w = 10'd1;
        end
        else begin
            r_data_w = r_data_r;
            r_length_w = (i_valid_r) ? r_length_r + 1 : r_length_r;
        end
    end

    always@ (*) begin
        if(i_start_r || switch_g) begin
            g_data_w = i_data_g_r;
            g_length_w = 10'd1;
        end
        else begin
            g_data_w = g_data_r;
            g_length_w = (i_valid_r) ? g_length_r + 1 : g_length_r;
        end
    end

    always@ (*) begin
        if(i_start_r || switch_b) begin
            b_data_w = i_data_b_r;
            b_length_w = 10'd1;
        end
        else begin
            b_data_w = b_data_r;
            b_length_w = (i_valid_r) ? b_length_r + 1 : b_length_r;
        end
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            r_data_r <= 0;
            g_data_r <= 0;
            b_data_r <= 0;

            r_length_r <= 0;
            g_length_r <= 0;
            b_length_r <= 0;
        end
        else begin
            r_data_r <= r_data_w;
            g_data_r <= g_data_w;
            b_data_r <= b_data_w;

            r_length_r <= r_length_w;
            g_length_r <= g_length_w;
            b_length_r <= b_length_w;
        end
    end

    /*----------------------------------------------*/
    // For Write Control
    always@ (*) begin
        if(o_rvalid)    r_num_w = ~r_num_r ;
        else            r_num_w = r_num_r;
    end

    always@ (*) begin
        if(o_gvalid)    g_num_w = ~g_num_r;
        else            g_num_w = g_num_r;
    end

    always@ (*) begin
        if(o_bvalid)    b_num_w = ~b_num_r;
        else            b_num_w = b_num_r;
    end

    always@ (*) begin
        if(o_rvalid) begin
            case(r_num_r)
                1'd0:       o_r_bweb = { {36{1'd1}}, 18'd0};
                1'd1:       o_r_bweb = { {9{1'd1}}, 18'd0, {18{1'd1}} };
                default:    o_r_bweb = 0;
            endcase
        end
        else begin
            o_r_bweb = {45{1'd1}};
        end
    end

    always@ (*) begin
        if(o_gvalid) begin
            case(g_num_r)
                1'd0:       o_g_bweb = { {36{1'd1}}, 18'd0};
                1'd1:       o_g_bweb = { {9{1'd1}}, 18'd0, {18{1'd1}} };
                default:    o_g_bweb = 0;
            endcase
        end
        else begin
            o_g_bweb = {45{1'd1}};
        end
    end

    always@ (*) begin
        if(o_bvalid) begin
            case(b_num_r)
                1'd0:       o_b_bweb = { {36{1'd1}}, 18'd0};
                1'd1:       o_b_bweb = { {9{1'd1}}, 18'd0, {18{1'd1}} };
                default:    o_b_bweb = 0;
            endcase
        end
        else begin
            o_b_bweb = {45{1'd1}};
        end
    end

    always@ (*) begin
        if(o_rvalid) begin
            case(r_num_r)
                1'd0:       o_r_datain = {36'd0, o_rdata};
                1'd1:       o_r_datain = {9'd0, o_rdata, 18'd0};
                default:    o_r_datain = 0;
            endcase
        end
        else begin
            o_r_datain = 0;
        end
    end

    always@ (*) begin
        if(o_gvalid) begin
            case(g_num_r)
                1'd0:       o_g_datain = {36'd0, o_gdata};
                1'd1:       o_g_datain = {9'd0, o_gdata, 18'd0};
                default:    o_g_datain = 0;
            endcase
        end
        else begin
            o_g_datain = 0;
        end
    end

    always@ (*) begin
        if(o_bvalid) begin
            case(b_num_r)
                1'd0:       o_b_datain = {36'd0, o_bdata};
                1'd1:       o_b_datain = {9'd0, o_bdata, 18'd0};
                default:    o_b_datain = 0;
            endcase
        end
        else begin
            o_b_datain = 0;
        end
    end

    always@ (*) begin
        if( o_rvalid && (&r_index_r) && (r_num_r))         
            r_select_w = ~r_select_r;
        else                                                
            r_select_w = r_select_r;
    end

    always@ (*) begin
        if( o_gvalid && (&g_index_r) && (g_num_r))    
            g_select_w = ~g_select_r;
        else                                              
            g_select_w = g_select_r;
    end

    always@ (*) begin
        if( o_bvalid && (&b_index_r) && (b_num_r))    
            b_select_w = ~b_select_r;
        else                                              
            b_select_w = b_select_r;
    end

    always@ (*) begin
        if( o_rvalid && (r_num_r) )      
            r_index_w = r_index_r + 1;
        else                                 
            r_index_w = r_index_r;
    end

    always@ (*) begin
        if( o_gvalid && (g_num_r) )      
            g_index_w = g_index_r + 1;
        else                                 
            g_index_w = g_index_r;
    end

    always@ (*) begin
        if( o_bvalid && (b_num_r) )      
            b_index_w = b_index_r + 1;
        else                                 
            b_index_w = b_index_r;
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            r_num_r <= 0;
            g_num_r <= 0;
            b_num_r <= 0;

            r_index_r <= 0;
            g_index_r <= 0;
            b_index_r <= 0;

            r_select_r <= 0;
            g_select_r <= 0;
            b_select_r <= 0;
        end
        else begin
            r_num_r <= r_num_w;
            g_num_r <= g_num_w;
            b_num_r <= b_num_w;

            r_index_r <= r_index_w;
            g_index_r <= g_index_w;
            b_index_r <= b_index_w;

            r_select_r <= r_select_w;
            g_select_r <= g_select_w;
            b_select_r <= b_select_w;
        end
    end

endmodule


module OUTPUT_CONTROLLER(
    input               i_clk,
    input               i_rst_n,
    input               i_start,
    input [10:0]        r_count,
    input [10:0]        g_count,
    input [10:0]        b_count,
    output              r_now,
    output              g_now,
    output              b_now,
    output reg          r_past,
    output reg          g_past,
    output reg          b_past,
    output reg          out_select_r,
    output reg          out_select_past,
    output reg [8:0]    out_index_r,
    output reg          out_num,
    output              finish
);
    reg       out_select_w;
    reg [8:0] out_index_w;
    reg       out_num_r, out_num_w;
    wire cross_r2g_w, cross_g2b_w, cross_b2finish_w;
    reg  cross_g2b_r, cross_r2g_r, cross_b2finish_r;

    assign r_now =  i_start && (!cross_r2g_r);
    assign g_now =  i_start && (!cross_g2b_r) && cross_r2g_r;
    assign b_now =  i_start && cross_g2b_r    && cross_r2g_r;

    assign cross_r2g_w      = (({out_select_r, out_index_r, out_num_r} == r_count) && r_now) || (cross_r2g_r);
    assign cross_g2b_w      = (({out_select_r, out_index_r, out_num_r} == g_count) && g_now) || (cross_g2b_r);
    assign cross_b2finish_w = (({out_select_r, out_index_r, out_num_r} == b_count) && b_now) || (cross_b2finish_r);
    assign finish = cross_b2finish_r;

    always@ (*) begin
        if(i_start) begin
            if ( (cross_r2g_w && (!cross_r2g_r)) || (cross_g2b_w && (!cross_g2b_r)) )
                out_num_w = 0;
            else
                out_num_w = ~out_num_r;  
        end   
        else                                    
            out_num_w = 0;
    end

    always@ (*) begin
        if(i_start) begin
            if ( (cross_r2g_w && (!cross_r2g_r)) || (cross_g2b_w && (!cross_g2b_r)) )
                out_index_w = 0;
            else if (out_num_r)
                out_index_w = out_index_r + 1;  
            else
                out_index_w = out_index_r;   
        end
        else                                    
            out_index_w = 0;
    end

    always@ (*) begin
        if(i_start) begin
            if ( (cross_r2g_w && (!cross_r2g_r)) || (cross_g2b_w && (!cross_g2b_r)) )
                out_select_w = 0;
            else if ((&out_index_r) && (out_num_r))
                out_select_w = ~out_select_r;  
            else
                out_select_w = out_select_r;   
        end
        else                                    
            out_select_w = 0;
    end

    always@ (posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            out_select_r <= 0;
            out_select_past <= 0;
            out_index_r  <= 0;

            cross_r2g_r <= 0;
            cross_g2b_r <= 0;
            cross_b2finish_r <= 0;

            out_num_r <= 0;
            out_num   <= 0;

            r_past    <= 0;
            g_past    <= 0;
            b_past    <= 0;
        end
        else begin
            out_select_r <= out_select_w;
            out_select_past <= out_select_r;
            out_index_r  <= out_index_w;

            cross_r2g_r <= cross_r2g_w;
            cross_g2b_r <= cross_g2b_w;
            cross_b2finish_r <= cross_b2finish_w;

            out_num_r <= out_num_w;
            out_num   <= out_num_r;

            r_past    <= r_now;
            g_past    <= g_now;
            b_past    <= b_now;
        end
    end

endmodule

