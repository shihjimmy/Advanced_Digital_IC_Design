`timescale 1ns/1ps
`define PERIOD      1.0
`define PERIOD2     5.0
`define MAX_TIME    10000
`define RST_DELAY   2.0
`define IO_DELAY    0.5

`ifdef m00
    `define MODE        2'b00
    `define CTRL_FILE   "../00_TESTBED/pattern/ctrl.dat"
    `define IN_FILE_A   "../00_TESTBED/pattern/pattern0.dat"
    `define OUT_FILE_A  "../00_TESTBED/pattern/golden0.dat"
    `define VAL_LEN     96
    `define IN_LEN      71
    `define OUT_LEN     6
`elsif m01
    `define MODE        2'b01
    `define CTRL_FILE   "../00_TESTBED/pattern/ctrl.dat"
    `define IN_FILE_A   "../00_TESTBED/pattern/pattern1.dat"
    `define IN_FILE_B   "../00_TESTBED/pattern/pattern2.dat"
    `define OUT_FILE_A  "../00_TESTBED/pattern/golden1.dat"
    `define OUT_FILE_B  "../00_TESTBED/pattern/golden2.dat"
    `define VAL_LEN     96
    `define IN_LEN      71
    `define OUT_LEN     6
`else
    `define MODE        2'b11
    `define VAL_LEN     0
    `define IN_LEN      0
    `define OUT_LEN     0
`endif

`define SDF_FILE "../02_SYN/Netlist/keccak_syn.sdf"


module testbench #(
    parameter IN_DATA_WIDTH  = 128,
    parameter OUT_DATA_WIDTH = 64
) ();

`ifdef FSDB
    initial begin

    `ifdef m00
        $fsdbDumpfile("keccak_00.fsdb");
    `elsif m01
        $fsdbDumpfile("keccak_01.fsdb");
    `else
        $fsdbDumpfile("keccak_11.fsdb");
    `endif 

    `ifdef UPF
        $fsdbDumpvars(0, "+all", "+mda", "+power");
    `else
        $fsdbDumpvars(0, "+all", "+mda");
    `endif

    end
`endif

`ifdef SDF
    initial begin
        $display("Annotating with SDF file: %s", `SDF_FILE);
        $sdf_annotate(`SDF_FILE, u_keccak);
    end
`endif

    // data
    reg                 [1:0] ctrl       [`VAL_LEN-1:0];
    reg  [ IN_DATA_WIDTH-1:0] in_data_a  [ `IN_LEN-1:0];
    reg  [ IN_DATA_WIDTH-1:0] in_data_b  [ `IN_LEN-1:0];
    reg  [OUT_DATA_WIDTH-1:0] out_data_a [`OUT_LEN-1:0];
    reg  [OUT_DATA_WIDTH-1:0] out_data_b [`OUT_LEN-1:0];

    initial begin
        `ifdef CTRL_FILE
            $readmemb(`CTRL_FILE, ctrl);
        `endif
        `ifdef IN_FILE_A
            $readmemh(`IN_FILE_A, in_data_a);
        `endif
        `ifdef IN_FILE_B
            $readmemh(`IN_FILE_B, in_data_b);
        `endif
        `ifdef OUT_FILE_A
            $readmemh(`OUT_FILE_A, out_data_a);
        `endif
        `ifdef OUT_FILE_B
            $readmemh(`OUT_FILE_B, out_data_b);
        `endif
    end

    // testbench signal
    integer input_end, output_a_end, output_b_end, bist_end;
    integer ctrl_cntr, pattern_cntr;
    integer hash_a_cntr, hash_b_cntr;
    integer error_a, error_b;
    wire clk, clk2, rst, rst_n;

    clk_gen clk_0 (
        .clk   (clk),
        .clk2  (clk2),
        .rst   (),
        .rst_n (rst_n)
    );

    // design under test
    parameter UNKNOWN_INPUT = {IN_DATA_WIDTH{1'bx}};

    reg  [               1:0] i_mode;
    wire                      o_ready;
    reg                       i_valid;
    reg                       i_last;
    reg  [ IN_DATA_WIDTH-1:0] i_data_a;
    reg  [ IN_DATA_WIDTH-1:0] i_data_b;
    wire                      o_valid_a;
    wire [OUT_DATA_WIDTH-1:0] o_data_a;
    wire                      o_valid_b;
    wire [OUT_DATA_WIDTH-1:0] o_data_b;
    wire                      o_BIST_valid;
    wire [OUT_DATA_WIDTH-1:0] o_BIST_data;


    `ifdef SDF
        keccak u_keccak (
            .i_clk        (clk  ),
            .i_clk2       (clk2 ),
            .i_rst_n      (rst_n),

            .i_mode       (i_mode  ),
            .o_ready      (o_ready ),
            .i_valid      (i_valid ),
            .i_last       (i_last  ),
            .i_data_a     (i_data_a),
            .i_data_b     (i_data_b),
            .o_valid_a    (o_valid_a),
            .o_data_a     (o_data_a ),
            .o_valid_b    (o_valid_b),
            .o_data_b     (o_data_b ),
            .o_BIST_valid (o_BIST_valid),
            .o_BIST_data  (o_BIST_data ),

            // scan chain inputs
            .test_se(1'd0),
            .test_si(1'd0),
            .test_so()
        );
    `endif 


    `ifdef RTL
        keccak u_keccak (
            .i_clk        (clk  ),
            .i_clk2       (clk2 ),
            .i_rst_n      (rst_n),

            .i_mode       (i_mode  ),
            .o_ready      (o_ready ),
            .i_valid      (i_valid ),
            .i_last       (i_last  ),
            .i_data_a     (i_data_a),
            .i_data_b     (i_data_b),
            .o_valid_a    (o_valid_a),
            .o_data_a     (o_data_a ),
            .o_valid_b    (o_valid_b),
            .o_data_b     (o_data_b ),
            .o_BIST_valid (o_BIST_valid),
            .o_BIST_data  (o_BIST_data )
        );
    `endif 



    // Input
    initial begin
        input_end    = 0;
        ctrl_cntr    = 0;
        pattern_cntr = 0;

        // init
        wait (rst_n === 1'b0);
        i_mode   = `MODE;
        i_valid  = 0;
        i_last   = 0;
        i_data_a = UNKNOWN_INPUT;
        i_data_b = UNKNOWN_INPUT;

        // init done
        wait (rst_n === 1'b1);
        @(posedge clk); #(`IO_DELAY);

        if (`MODE != 2'b11) begin
            while (pattern_cntr < `IN_LEN) begin
                @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
                while (o_ready !== 1'b1) begin
                    @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
                end

                @(posedge clk); #(`IO_DELAY);
                i_valid = ctrl[ctrl_cntr][1];

                if (i_valid) begin
                    case (`MODE)
                        2'b00: begin
                            i_last   = ctrl[ctrl_cntr][0];;
                            i_data_a = in_data_a[pattern_cntr];
                            i_data_b = 0;
                        end
                        2'b01: begin
                            i_last   = ctrl[ctrl_cntr][0];;
                            i_data_a = in_data_a[pattern_cntr];
                            i_data_b = in_data_b[pattern_cntr];
                        end
                        default: begin
                            i_last   = 0;
                            i_data_a = UNKNOWN_INPUT;
                            i_data_b = UNKNOWN_INPUT;
                        end
                    endcase

                    pattern_cntr = pattern_cntr + 1;

                    @(posedge clk); #(`IO_DELAY);
                    i_valid  = 0;
                    i_last   = 0;
                    i_data_a = UNKNOWN_INPUT;
                    i_data_b = UNKNOWN_INPUT;
                end

                ctrl_cntr = ctrl_cntr + 1;
            end

            @(posedge clk); #(`IO_DELAY);
            i_valid  = 0;
            i_last   = 0;
            i_data_a = UNKNOWN_INPUT;
            i_data_b = UNKNOWN_INPUT;
        end

        input_end = 1;
    end

    // Output A
    initial begin
        output_a_end = 0;
        hash_a_cntr  = 0;
        error_a      = 0;

        // init
        wait (rst_n === 1'b0);
        // init done
        wait (rst_n === 1'b1);
        @(posedge clk);

        while ((`MODE === 2'b00 || `MODE === 2'b01) && hash_a_cntr < `OUT_LEN) begin
            @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
            while (o_valid_a !== 1'b1) begin
                @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
            end

            if (o_data_a !== out_data_a[hash_a_cntr]) begin
                $display("Wrong hash value! Sequence: %d", hash_a_cntr);
                error_a = error_a + 1;
            end

            hash_a_cntr = hash_a_cntr + 1;
        end
        @(posedge clk);

        output_a_end = 1;
    end

    // Output B
    initial begin
        output_b_end = 0;
        hash_b_cntr  = 0;
        error_b      = 0;

        // init
        wait (rst_n === 1'b0);
        // init done
        wait (rst_n === 1'b1);
        @(posedge clk);

        while (`MODE === 2'b01 && hash_b_cntr < `OUT_LEN) begin
            @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
            while (o_valid_b !== 1'b1) begin
                @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
            end

            if (o_data_b !== out_data_b[hash_b_cntr]) begin
                $display("Wrong hash value! Sequence: %d", hash_b_cntr);
                error_b = error_b + 1;
            end

            hash_b_cntr = hash_b_cntr + 1;
        end
        @(posedge clk);

        output_b_end = 1;
    end

    // BIST
    initial begin
        bist_end = 0;

        // init
        wait (rst_n === 1'b0);
        // init done
        wait (rst_n === 1'b1);
        @(posedge clk);

        if (`MODE == 2'b11) begin
            while (o_BIST_valid !== 1'b1) begin
                @(negedge clk); #(`PERIOD/2.0 - `IO_DELAY);
            end

            if (o_BIST_data !== 0) begin
                $display("BIST result: instance %d is faulty", o_BIST_data);
            end else begin
                $display("BIST result: No faulty instance");
            end
        end
        @(posedge clk);

        bist_end = 1;
    end

    // End
    integer start_time, end_time;

    initial begin
        // init
        wait (rst_n === 1'b0);
        // init done
        wait (rst_n === 1'b1);
        @(posedge clk);

        start_time = $time;
        $display("----------------------------------------------");
        $display("-                   START                    -");
        $display("----------------------------------------------");

        wait (input_end & output_a_end & output_b_end & bist_end);
        end_time = $time;

        if (error_a + error_b === 0) begin
            $display("----------------------------------------------");
            $display("-                 ALL PASS!                  -");
            $display("----------------------------------------------");
        end
        else begin
            $display("----------------------------------------------");
            $display("  Wrong! Total Error: %d                      ", error_a + error_b);
            $display("----------------------------------------------");
        end

        if ((end_time - start_time) < 6000) begin
            $display("  Total sim time: %6d ns", (end_time - start_time));
        end
        else begin
            $display("  Total sim time: %6d ns", (end_time - start_time));
        end

        # (2 * `PERIOD);
        $finish;
    end

endmodule

module clk_gen (
    output reg clk,
    output reg clk2,
    output reg rst,
    output reg rst_n
);

    always #(`PERIOD  / 2.0) clk  = ~clk ;
    always #(`PERIOD2 / 2.0) clk2 = ~clk2;

    initial begin
        clk = 1'b0; clk2 = $random % 2;
        rst = 1'b0; rst_n = 1'b1; #(              0.25  * `PERIOD);
        rst = 1'b1; rst_n = 1'b0; #((`RST_DELAY - 0.25) * `PERIOD);
        rst = 1'b0; rst_n = 1'b1; #(                    `MAX_TIME);
        $display("---------------------------");
        $display("Error! Time limit exceeded!");
        $display("---------------------------");
        $finish;
    end

endmodule
