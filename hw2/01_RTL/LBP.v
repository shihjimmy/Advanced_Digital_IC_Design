module LBP # (
    parameter DATA_WIDTH = 8,              // AXI4 data width
    parameter ADDR_WIDTH = 15,             // AXI4 address width
    parameter STRB_WIDTH = (DATA_WIDTH/8)  // AXI4 strobe width
)
(
    // Clock and synchronous high reset
    input                   clk_A,
    input                   clk_B,
    input                   rst,
    input                   start,
    output                  finish,

    // Data AXI4 master interface
    output [ADDR_WIDTH-1:0] data_awaddr,
    output [           7:0] data_awlen,
    output [           2:0] data_awsize,
    output [           1:0] data_awburst,
    output                  data_awvalid,
    input                   data_awready,

    output [DATA_WIDTH-1:0] data_wdata,
    output [STRB_WIDTH-1:0] data_wstrb,
    output                  data_wlast,
    output                  data_wvalid,
    input                   data_wready,

    // input  [           1:0] data_bresp,
    // input                   data_bvalid,
    // output                  data_bready,

    output [ADDR_WIDTH-1:0] data_araddr,
    output [           7:0] data_arlen,
    output [           2:0] data_arsize,
    output [           1:0] data_arburst,
    output                  data_arvalid,
    input                   data_arready,

    input  [DATA_WIDTH-1:0] data_rdata,
    input  [           1:0] data_rresp,
    input                   data_rlast,
    input                   data_rvalid,
    output                  data_rready
);  
    localparam S_IDLE = 0;
    localparam S_CALC = 1;
    localparam S_FINISH = 2;

    reg [1:0] state_r, state_w;

    // CDC for control signal
    wire start_CDC, finish_or_not;
    wire handshake;
    reg handshake_r;

    CDC_control u_CDC(
        .clk_A(clk_A),
        .clk_B(clk_B),
        .rst(rst),
        .start(start),
        .finish(finish_or_not),
        .start_CDC(start_CDC),
        .finish_CDC(finish),
        .handshake(handshake)
    );

    // AXI control
    wire [7:0] data1, data2, data3, data4, data5, data6, data7, data8, center, LBP_out;
    wire LBP_start, AXI_read_finish, AXI_write_finish;

    AXI_Read_Control u_AXI_Read(
        .clk_B(clk_B),
        .rst(rst),
        .start(start_CDC),
        .LBP_start(LBP_start),
        .finish(AXI_read_finish),
        .data1(data1),
        .data2(data2),
        .data3(data3),
        .data4(data4),
        .data5(data5),
        .data6(data6),
        .data7(data7),
        .data8(data8),
        .center(center),

        .data_araddr(data_araddr),
        .data_arlen(data_arlen),
        .data_arsize(data_arsize),
        .data_arburst(data_arburst),
        .data_arvalid(data_arvalid),
        .data_arready(data_arready),

        .data_rdata(data_rdata),
        .data_rresp(data_rresp),
        .data_rlast(data_rlast),
        .data_rvalid(data_rvalid),
        .data_rready(data_rready)
    );

    AXI_Write_Control u_AXI_Write(
        .clk_B(clk_B),
        .rst(rst),
        .start(start_CDC),
        .write_start(LBP_start),
        .write_data(LBP_out),
        .finish(AXI_write_finish),

        .data_awaddr(data_awaddr),
        .data_awlen(data_awlen),
        .data_awsize(data_awsize),
        .data_awburst(data_awburst),
        .data_awvalid(data_awvalid),
        .data_awready(data_awready),

        .data_wdata(data_wdata),
        .data_wstrb(data_wstrb),
        .data_wlast(data_wlast),
        .data_wvalid(data_wvalid),
        .data_wready(data_wready)
    );

    // LBP calculation unit
    LBP_calc u_LBP_calc(
        .data1(data1),
        .data2(data2),
        .data3(data3),
        .data4(data4),
        .data5(data5),
        .data6(data6),
        .data7(data7),
        .data8(data8),
        .center(center),
        .out(LBP_out)
    );

    assign finish_or_not = (state_r==S_CALC && state_w==S_FINISH) || (state_r==S_FINISH && handshake && !handshake_r);

    // state transition
    always@ (*) begin
      case(state_r)
        S_IDLE:   state_w = (start_CDC) ? S_CALC : S_IDLE;
        S_CALC:   state_w = (AXI_read_finish && AXI_write_finish) ? S_FINISH : S_CALC;
        S_FINISH: state_w = S_FINISH;
        default : state_w = S_IDLE;
      endcase
    end 

    always@ (posedge clk_B or posedge rst) begin
        if(rst) begin
            state_r <= 0;
            handshake_r <= 0;
        end
        else begin
            state_r <= state_w;
            handshake_r <= handshake;
        end
    end
endmodule


module AXI_Read_Control(
    input           clk_B,
    input           rst,
    input           start,
    output reg      LBP_start,
    output          finish,
    output [ 7:0]   data1,
    output [ 7:0]   data2,
    output [ 7:0]   data3,
    output [ 7:0]   data4,
    output [ 7:0]   data5,
    output [ 7:0]   data6,
    output [ 7:0]   data7,
    output [ 7:0]   data8,
    output [ 7:0]   center,
    
    output reg [14:0]   data_araddr,
    output reg [ 7:0]   data_arlen,
    output reg [ 2:0]   data_arsize,
    output reg [ 1:0]   data_arburst,
    output reg          data_arvalid,
    input               data_arready,

    input  [7:0]        data_rdata,
    input  [1:0]        data_rresp,
    input               data_rlast,
    input               data_rvalid,
    output reg          data_rready
);
    localparam S_IDLE = 0;
    localparam S_PREP1 = 1;
    localparam S_READ1 = 2;
    localparam S_PREP2 = 3;
    localparam S_READ2 = 4;
    localparam S_PREP3 = 5;
    localparam S_READ3 = 6;
    localparam S_FINISH = 7;

    reg [2:0] state_r, state_w;

    // store input data from AXI ram
    reg [7:0] indata_r[0:8], indata_w[0:9];
    // counter
    reg [6:0]  countx_r;
    wire [6:0] countx_w;
    reg [6:0]  county_r;
    wire [6:0] county_w;
    wire [6:0] temp1, temp2;

    assign finish = state_r==S_FINISH;
    
    assign countx_w = (state_r==S_READ3 && state_w==S_PREP1 && countx_r==7'd125) ? 7'd0 : (state_r==S_READ3 && state_w==S_PREP1) ? countx_r + 1 : countx_r;
    assign county_w = (state_r==S_READ3 && state_w==S_PREP1 && countx_r==7'd125) ? county_r + 1 : county_r;
    assign temp1 = county_r + 1;
    assign temp2 = county_r + 2;

    assign data1 = indata_r[0];
    assign data2 = indata_r[1];
    assign data3 = indata_r[2];
    assign data4 = indata_r[3];
    assign data5 = indata_r[5];
    assign data6 = indata_r[6];
    assign data7 = indata_r[7];
    assign data8 = indata_r[8];
    assign center = indata_r[4];

    wire   LBP_start_w;
    assign LBP_start_w = (state_r==S_READ3 && data_rlast && data_rvalid);
    
    always@ (*) begin
        if(data_rvalid) begin
            indata_w[0] = indata_r[1];
            indata_w[1] = indata_r[2];
            indata_w[2] = indata_r[3];
            indata_w[3] = indata_r[4];
            indata_w[4] = indata_r[5];
            indata_w[5] = indata_r[6];
            indata_w[6] = indata_r[7];
            indata_w[7] = indata_r[8];
            indata_w[8] = data_rdata;
        end
        else begin
            indata_w[0] = indata_r[0];
            indata_w[1] = indata_r[1];
            indata_w[2] = indata_r[2];
            indata_w[3] = indata_r[3];
            indata_w[4] = indata_r[4];
            indata_w[5] = indata_r[5];
            indata_w[6] = indata_r[6];
            indata_w[7] = indata_r[7];
            indata_w[8] = indata_r[8];
        end
    end

    always@ (*) begin
        case(state_r)
            S_IDLE:   state_w = (start) ? S_PREP1 : S_IDLE;
            S_PREP1:  state_w = (data_arready && data_arvalid) ? S_READ1 : S_PREP1;
            S_READ1:  state_w = (data_rlast && data_rvalid) ? S_PREP2 : S_READ1;
            S_PREP2:  state_w = (data_arready && data_arvalid) ? S_READ2 : S_PREP2;
            S_READ2:  state_w = (data_rlast && data_rvalid) ? S_PREP3 : S_READ2;
            S_PREP3:  state_w = (data_arready && data_arvalid) ? S_READ3 : S_PREP3;
            S_READ3:  state_w = (data_rlast && data_rvalid && (county_r==7'd125 && countx_r==7'd125)) ? S_FINISH : (data_rlast && data_rvalid) ? S_PREP1 : S_READ3;
            S_FINISH: state_w = S_FINISH;
            default:  state_w = S_IDLE;
        endcase
    end

    always@ (posedge clk_B or posedge rst) begin
        if(rst) begin
            state_r <= 0;
            LBP_start <= 0;
            countx_r <= 0;
            county_r <= 0;

            indata_r[0] <= 0;
            indata_r[1] <= 0;
            indata_r[2] <= 0;
            indata_r[3] <= 0;
            indata_r[4] <= 0;
            indata_r[5] <= 0;
            indata_r[6] <= 0;
            indata_r[7] <= 0;
            indata_r[8] <= 0;
        end
        else begin
            state_r <= state_w;
            LBP_start <= LBP_start_w;
            countx_r <= countx_w;
            county_r <= county_w;

            indata_r[0] <= indata_w[0];
            indata_r[1] <= indata_w[1];
            indata_r[2] <= indata_w[2];
            indata_r[3] <= indata_w[3];
            indata_r[4] <= indata_w[4];
            indata_r[5] <= indata_w[5];
            indata_r[6] <= indata_w[6];
            indata_r[7] <= indata_w[7];
            indata_r[8] <= indata_w[8];
        end
    end

    // for ar channel control
    always@ (*) begin
        // some unchanged ports
        data_arsize = 3'd0;
        data_arburst = 2'b01;
        data_arlen = 8'd2;
        //other
        data_arvalid = 0;
        data_araddr = 0;

        case(state_r)
            S_PREP1: begin
                data_arvalid = 1;
                data_araddr = {1'b0, county_r, countx_r};
            end

            S_PREP2: begin
                data_arvalid = 1;
                data_araddr = {1'b0, temp1, countx_r};
            end

            S_PREP3: begin
                data_arvalid = 1;
                data_araddr = {1'b0, temp2, countx_r};
            end
        endcase
    end

    // for r channel control
    always@ (*) begin
        case(state_r)
            S_READ1, S_READ2, S_READ3: data_rready = 1;
            default: data_rready = 0;
        endcase
    end
endmodule

module AXI_Write_Control(
    input           clk_B,
    input           rst,
    input           start,
    input           write_start,
    input  [7:0]    write_data,
    output          finish,
    
    output reg [14:0]   data_awaddr,
    output reg [ 7:0]   data_awlen,
    output reg [ 2:0]   data_awsize,
    output reg [ 1:0]   data_awburst,
    output reg          data_awvalid,
    input               data_awready,

    output reg [ 7:0]   data_wdata,
    output reg          data_wstrb,
    output reg          data_wlast,
    output reg          data_wvalid,
    input               data_wready
);
    localparam S_IDLE = 0;
    localparam S_PREP = 1;
    localparam S_WRITE = 2;
    localparam S_FINISH = 3;

    reg [1:0] state_r, state_w;
    reg [6:0] count_r;
    wire [6:0] count_w;
    wire [13:0] temp, temp2;

    assign finish = state_r==S_FINISH;
    assign count_w = (state_w==S_PREP && state_r==S_WRITE) ? count_r + 1 : count_r;
    assign temp2 = count_r << 7;
    assign temp = (14'd129) + temp2;

    always@ (*) begin
        case(state_r)
            S_IDLE:     state_w = (start) ? S_PREP : S_IDLE;
            S_PREP:     state_w = (data_awvalid && data_awready) ? S_WRITE : S_PREP;
            S_WRITE:    state_w = (data_wready) ? S_WRITE : (count_r==7'd125) ? S_FINISH : S_PREP;
            S_FINISH:   state_w = S_FINISH;
            default:    state_w = S_IDLE;
        endcase
    end

    always @(posedge clk_B or posedge rst) begin
        if(rst) begin
            state_r <= S_IDLE;
            count_r <= 0;
        end
        else begin
            state_r <= state_w;
            count_r <= count_w;
        end
    end

    // aw channel control
    always@ (*) begin
        // some unchanged ports
        data_awsize = 3'd0;
        data_awburst = 2'b01;
        data_awlen = 8'd125;
        // other
        data_awaddr = 0;
        data_awvalid = 0;

        if(state_r == S_PREP) begin
            data_awvalid = 1;
            data_awaddr = {1'b1, temp};
        end
    end

    // w channel control
    always@ (*) begin
        // some unchanged ports
        data_wstrb = 1'b1;
        data_wlast = 1'b0;
        // other
        data_wdata = 0;
        data_wvalid = 0;
        
        if(state_r == S_WRITE && write_start) begin
            data_wdata = write_data;
            data_wvalid = 1;
        end
    end
endmodule


module CDC_control(
    input clk_A,
    input clk_B,
    input rst,
    input start,
    input finish,
    output start_CDC,
    output finish_CDC,
    output handshake
);
    // For normal 2FF
    reg start_clkB1_r, start_clkB2_r;
    assign start_CDC = start_clkB2_r;

    always@ (posedge clk_B or posedge rst) begin
        if(rst) begin
            start_clkB1_r <= 0;
            start_clkB2_r <= 0;
        end
        else begin
            start_clkB1_r <= start;
            start_clkB2_r <= start_clkB1_r;
        end
    end
    
    // For Pulse Synchronizer
    reg  pulse_clkB_r;
    wire pulse_clkB_w;
    reg  pulse_clkA1_r, pulse_clkA2_r, pulse_clkA3_r;
    assign pulse_clkB_w = pulse_clkB_r ^ finish;
    assign finish_CDC = pulse_clkA3_r ^ pulse_clkA2_r;
    
    always@ (posedge clk_B or posedge rst) begin
        if(rst) pulse_clkB_r  <= 0;
        else    pulse_clkB_r  <= pulse_clkB_w;
    end

    always@ (posedge clk_A or posedge rst) begin
        if(rst) begin
            pulse_clkA1_r <= 0;
            pulse_clkA2_r <= 0;
            pulse_clkA3_r <= 0;
        end
        else begin
            pulse_clkA1_r <= pulse_clkB_r;
            pulse_clkA2_r <= pulse_clkA1_r;
            pulse_clkA3_r <= pulse_clkA2_r;
        end
    end

    // Another 2FF for sending handshake data back to clk B
    reg finish_clkB1_r, finish_clkB2_r;
    assign handshake = finish_clkB2_r;
    
    always@ (posedge clk_B or posedge rst) begin
        if(rst) begin
            finish_clkB1_r <= 0;
            finish_clkB2_r <= 0;
        end
        else begin
            finish_clkB1_r <= finish_CDC;
            finish_clkB2_r <= finish_clkB1_r;
        end
    end
endmodule


module LBP_calc (
    input [7:0] data1,
    input [7:0] data2,
    input [7:0] data3,
    input [7:0] data4,
    input [7:0] data5,
    input [7:0] data6,
    input [7:0] data7,
    input [7:0] data8,
    input [7:0] center,
    output [7:0] out
);  
    wire temp1, temp2, temp3, temp4, temp5, temp6, temp7, temp8;
    assign temp1 = data1 >= center;
    assign temp2 = data2 >= center;
    assign temp3 = data3 >= center;
    assign temp4 = data4 >= center;
    assign temp5 = data5 >= center;
    assign temp6 = data6 >= center;
    assign temp7 = data7 >= center;
    assign temp8 = data8 >= center;
    assign out   = {temp8, temp7, temp6, temp5, temp4, temp3, temp2, temp1};
endmodule
