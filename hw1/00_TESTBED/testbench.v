`timescale 1ns/10ps
`define CYCLE 	  1.0
`define MAX_CYCLE 10000000
`define RST_DELAY 2.0

`define Y_LEN   8192
`define X_LEN   11
`define DATA_LEN 4096

`define IN_DATA_WIDTH  8
`define OUT_DATA_WIDTH 18


// Selects pattern
`ifdef p0
    `define IDATA "../00_TESTBED/p0/pat0.dat"
    `define ODATA "../00_TESTBED/p0/gold0.dat"
`elsif p1
    `define IDATA "../00_TESTBED/p1/pat1.dat"
    `define ODATA "../00_TESTBED/p1/gold1.dat"
`elsif p2
    `define IDATA "../00_TESTBED/p2/pat2.dat"
    `define ODATA "../00_TESTBED/p2/gold2.dat"
`elsif p3
    `define IDATA "../00_TESTBED/p3/pat3.dat"
    `define ODATA "../00_TESTBED/p3/gold3.dat"
`elsif p4
    `define IDATA "../00_TESTBED/p4/pat4.dat"
    `define ODATA "../00_TESTBED/p4/gold4.dat"
`else
    `define IDATA "../00_TESTBED/p0/pat0.dat"
    `define ODATA "../00_TESTBED/p0/gold0.dat"
`endif


module testbench #(
    parameter IN_DATA_WIDTH = `IN_DATA_WIDTH,
    parameter OUT_DATA_WIDTH = `OUT_DATA_WIDTH
) ();
    // Ports
    wire            clk;
    wire            rst;
    wire            rst_n;
            
    reg             in_valid;
    wire            in_ready;
    reg  [3*IN_DATA_WIDTH-1:0] in_data;

    wire            out_valid;
    wire [OUT_DATA_WIDTH-1:0] out_data;

    // TB related variables
    reg  [3*IN_DATA_WIDTH-1:0] in_vec   [0:`DATA_LEN-1];
    reg  [OUT_DATA_WIDTH-1:0] golden [0:`Y_LEN-1];
    integer out_end;
    integer i, j;
    integer correct, error;

    initial begin
        $readmemb(`IDATA, in_vec);
        $readmemb(`ODATA, golden);
    end

    `ifdef SDF
        initial begin
            $sdf_annotate("../02_GATE/Netlist/top_syn.sdf", u_top);
        end
    `endif

    // Modules
    clk_gen clk_gen_inst (
        .clk   (clk),
        .rst   (rst),
        .rst_n (rst_n)
    );
    top u_top (
        .i_clk            (clk      ),
        .i_rst_n          (rst_n    ),
        .i_valid          (in_valid ),
        .i_data_r         (in_data[23:16]),
        .i_data_g         (in_data[15:8] ),
        .i_data_b         (in_data[7:0]  ),
        .o_data           (out_data ),
        .o_valid          (out_valid)
    );
    
    initial begin
        `ifdef p0
            $fsdbDumpfile("top_p0.fsdb");
        `elsif p1
            $fsdbDumpfile("top_p1.fsdb");
        `elsif p2
            $fsdbDumpfile("top_p2.fsdb");
        `elsif p3
            $fsdbDumpfile("top_p3.fsdb");
        `elsif p4
            $fsdbDumpfile("top_p4.fsdb");
        `else
            $fsdbDumpfile("top.fsdb");
        `endif

        `ifdef UPF
            $fsdbDumpvars(0, testbench, "+power");
        `else
            $fsdbDumpvars(0, testbench);
        `endif
    end

    // Input
    initial begin
        in_valid = 0;
        // Waiting for reset to finish
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        @(posedge clk);

        // Loop for input data
        @(negedge clk);
        $display(`IDATA);
        $display("----------------------------------------------");
        $display("-                   START                    -");
        $display("----------------------------------------------");
        i = 0;
        while (i < `DATA_LEN) begin
            in_data = in_vec[i]; 
            in_valid = 1'b1;
            @(negedge clk);
            i = i + 1;
        end
        in_data = 0;
        in_valid = 0;
    end

    // Output
    initial begin
        out_end = 0;
        correct = 0;
        error   = 0;
        // Waiting for reset to finish
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        j = 0;
        wait (out_valid);
        
        @(negedge clk);
        while (out_valid) begin
            if (out_data === golden[j]) begin
                correct = correct + 1;
            end else begin
                error = error + 1;
                $display("Test[%d]: Error!", j);
                $display("Golden value=%b, Yours=%b", golden[j][17:10], out_data[17:10]);
                $display("Golden number=%b, Yours=%b", golden[j][9:0], out_data[9:0]);
            end
            j = j + 1;
            @(negedge clk);
        end
        out_end = 1;
    end

    // End
    initial begin
        wait (out_end);
        if (error === 0) begin
            $display("----------------------------------------------");
            $display("-                 ALL PASS!                  -");
            $display("----------------------------------------------");
        end
        else begin
            $display("----------------------------------------------");
            $display("  Wrong! Total Error: %d                      ", error);
            $display("----------------------------------------------");
        end
        # (2 * `CYCLE);
        $finish;
    end

endmodule

module clk_gen(
    output reg clk,
    output reg rst,
    output reg rst_n
);
    always #(`CYCLE/2.0) clk = ~clk;

    initial begin
        clk = 1'b1;
        rst = 1'b0; rst_n = 1'b1; #(              0.25  * `CYCLE);
        rst = 1'b1; rst_n = 1'b0; #((`RST_DELAY)        * `CYCLE);
        rst = 1'b0; rst_n = 1'b1; #(         `MAX_CYCLE * `CYCLE);
        $display("------------------------");
        $display("Error! Runtime exceeded!");
        $display("------------------------");
        $finish;
    end
endmodule
