`timescale 1ns/1ps
// Directed testbench for sync_fifo (step 2)
// Stimulus is driven on negedge clk, DUT samples on posedge -> no race.
module tb;
    parameter W = 8;
    parameter D = 16;

    reg          clk = 0;
    reg          rst_n = 0;
    reg          wr_en = 0;
    reg          rd_en = 0;
    reg  [W-1:0] data_in = 0;
    wire [W-1:0] data_out;
    wire         full, empty;

    integer i;
    integer errors = 0;
    reg [W-1:0] prev;

    sync_fifo #(.DATA_WIDTH(W), .DEPTH(D)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .rd_en(rd_en),
        .data_in(data_in), .data_out(data_out),
        .full(full), .empty(empty)
    );

    always #5 clk = ~clk;   // 100 MHz

    // write one value (1 clock cycle of wr_en)
    task push(input [W-1:0] d);
        begin
            @(negedge clk);
            wr_en = 1; data_in = d;
            @(negedge clk);
            wr_en = 0;
        end
    endtask

    // read one value (data_out is valid 1 cycle after rd_en)
    task pop;
        begin
            @(negedge clk);
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
        end
    endtask

    // write and read in the same clock cycle
    task push_pop(input [W-1:0] d);
        begin
            @(negedge clk);
            wr_en = 1; rd_en = 1; data_in = d;
            @(negedge clk);
            wr_en = 0; rd_en = 0;
        end
    endtask

    task check_flags(input exp_full, input exp_empty, input [255:0] name);
        begin
            if (full !== exp_full || empty !== exp_empty) begin
                $display("FAIL [%0s]: full=%b empty=%b (expected %b %b)",
                         name, full, empty, exp_full, exp_empty);
                errors = errors + 1;
            end else
                $display("PASS [%0s]", name);
        end
    endtask

    task check_data(input [W-1:0] exp, input [255:0] name);
        begin
            if (data_out !== exp) begin
                $display("FAIL [%0s]: data_out=%h (expected %h)", name, data_out, exp);
                errors = errors + 1;
            end else
                $display("PASS [%0s]", name);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);

        // reset
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Test 1: after reset the FIFO is empty
        check_flags(0, 1, "T1 empty after reset");

        // Test 2: write D values -> full
        for (i = 0; i < D; i = i + 1) push(i + 8'h10);
        @(negedge clk);
        check_flags(1, 0, "T2 full after D writes");

        // Test 3: read D values back, in the same order they were written
        for (i = 0; i < D; i = i + 1) begin
            pop;
            check_data(i + 8'h10, "T3 read order");
        end
        check_flags(0, 1, "T3 empty after D reads");

        // Test 4: write when full -> the extra write must be ignored
        for (i = 0; i < D; i = i + 1) push(i + 8'h20);
        @(negedge clk);
        check_flags(1, 0, "T4 full before extra write");
        push(8'hFF);                         // extra write, FIFO is full
        check_flags(1, 0, "T4 still full after extra write");
        for (i = 0; i < D; i = i + 1) begin
            pop;
            check_data(i + 8'h20, "T4 data intact");
        end
        check_flags(0, 1, "T4 empty (0xFF was not stored)");

        // Test 5: read when empty -> data_out and pointers must not change
        prev = data_out;
        pop;                                 // FIFO is empty
        check_data(prev, "T5 data_out unchanged");
        check_flags(0, 1, "T5 still empty");
        push(8'h55);                         // pointers must still be in sync
        pop;
        check_data(8'h55, "T5 normal operation after empty read");

        // Test 6: write and read at the same time (FIFO half full)
        for (i = 0; i < D/2; i = i + 1) push(i + 8'h60);
        push_pop(8'hAA);                     // read 0x60 while writing 0xAA
        check_data(8'h60, "T6 simultaneous read");
        check_flags(0, 0, "T6 neither full nor empty");
        for (i = 1; i < D/2; i = i + 1) begin
            pop;
            check_data(i + 8'h60, "T6 remaining order");
        end
        pop;
        check_data(8'hAA, "T6 value written during simultaneous op");
        check_flags(0, 1, "T6 empty at the end");

        // Test 7: reset in the middle of operation -> FIFO becomes empty
        for (i = 0; i < 5; i = i + 1) push(i + 8'h70);
        @(negedge clk);
        rst_n = 0;
        @(negedge clk);
        rst_n = 1;
        check_flags(0, 1, "T7 empty after mid-operation reset");
        check_data(8'h00, "T7 data_out cleared");
        push(8'h77);
        pop;
        check_data(8'h77, "T7 old data not leaked after reset");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
