`timescale 1ns/1ps
// Step 3: constrained-random stimulus for sync_fifo (no checking yet - see step 4)

// ---------------- Transaction: one clock cycle of random inputs ----------------
class fifo_txn;
    rand bit       wr;
    rand bit       rd;
    rand bit [7:0] data;

    // weights (in %) that decide how often wr/rd are 1; changed between phases
    int w_wr = 50;
    int w_rd = 50;

`ifdef USE_RANDOMIZE
    constraint c_wr { wr dist {1 := w_wr, 0 := 100 - w_wr}; }
    constraint c_rd { rd dist {1 := w_rd, 0 := 100 - w_rd}; }
`endif

    // fallback for simulators without constrained-random (e.g. ModelSim Starter):
    // same behavior, written with $urandom_range
    function void rnd();
        wr   = ($urandom_range(99) < w_wr);
        rd   = ($urandom_range(99) < w_rd);
        data = $urandom_range(255);
    endfunction

    function void display(string tag = "");
        $display("[%0t] %s wr=%b rd=%b data=%h", $time, tag, wr, rd, data);
    endfunction
endclass

// ---------------- Testbench top ----------------
module tb_random;
    parameter W = 8;
    parameter D = 16;

    logic         clk = 0;
    logic         rst_n = 0;
    logic         wr_en = 0;
    logic         rd_en = 0;
    logic [W-1:0] data_in = 0;
    logic [W-1:0] data_out;
    logic         full, empty;

    sync_fifo #(.DATA_WIDTH(W), .DEPTH(D)) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .rd_en(rd_en),
        .data_in(data_in), .data_out(data_out),
        .full(full), .empty(empty)
    );

    // passive assertion checker (see fifo_sva.sv); .* connects same-named signals
    fifo_sva #(.W(W), .D(D)) sva (.*);

    // passive functional-coverage collector (see fifo_cov.sv)
    fifo_cov #(.W(W), .D(D)) cov (.*);

    always #5 clk = ~clk;

    fifo_txn t;
    int shown     = 0;
    int cyc_full  = 0;
    int cyc_empty = 0;
    int cyc_both  = 0;

    // simple statistics: did random stimulus reach the interesting situations?
    always @(posedge clk) if (rst_n) begin
        if (full)           cyc_full++;
        if (empty)          cyc_empty++;
        if (wr_en && rd_en) cyc_both++;
    end

    // ---------------- Scoreboard: reference model + checker ----------------
    logic [W-1:0] ref_q[$];        // reference model = a plain SystemVerilog queue
    logic [W-1:0] exp_data;        // value expected on data_out after a read
    bit           exp_valid = 0;   // a read happened at the previous edge
    int           checks = 0;
    int           errors = 0;

    // Sampled at posedge: values read here are the ones from BEFORE this edge
    // (DUT outputs change in the NBA region, after this block has run).
    always @(posedge clk) begin
        bit do_wr, do_rd;
        if (!rst_n) begin
            ref_q.delete();
            exp_valid = 0;
        end else begin
            // 1) data_out is registered: it shows the result of the previous edge's read
            if (exp_valid) begin
                checks++;
                if (data_out !== exp_data) begin
                    errors++;
                    $display("[%0t] ERROR data_out=%h expected=%h", $time, data_out, exp_data);
                end
            end

            // 2) flags must match the model's occupancy
            checks++;
            if (full !== (ref_q.size() == D)) begin
                errors++;
                $display("[%0t] ERROR full=%b expected=%b", $time, full, (ref_q.size() == D));
            end
            checks++;
            if (empty !== (ref_q.size() == 0)) begin
                errors++;
                $display("[%0t] ERROR empty=%b expected=%b", $time, empty, (ref_q.size() == 0));
            end

            // 3) update the model (decisions use the state BEFORE this edge)
            do_wr = wr_en && (ref_q.size() < D);
            do_rd = rd_en && (ref_q.size() > 0);
            exp_valid = do_rd;
            if (do_rd) exp_data = ref_q.pop_front();
            if (do_wr) ref_q.push_back(data_in);
        end
    end

    // drive n random cycles with the given wr/rd weights
    task automatic drive_cycles(input int n, input int w_wr, input int w_rd);
        repeat (n) begin
            t.w_wr = w_wr;
            t.w_rd = w_rd;
`ifdef USE_RANDOMIZE
            if (!t.randomize()) $fatal(1, "randomize() failed");
`else
            t.rnd();
`endif
            if (shown < 8) begin
                t.display("txn");
                shown++;
            end
            @(negedge clk);
            wr_en   = t.wr;
            rd_en   = t.rd;
            data_in = t.data;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_random);

        t = new();

        repeat (3) @(negedge clk);
        rst_n = 1;

        drive_cycles(200, 80, 20);   // phase A: write-heavy -> should hit full
        drive_cycles(200, 20, 80);   // phase B: read-heavy  -> should hit empty
        drive_cycles(400, 50, 50);   // phase C: balanced    -> many wr+rd together
        drive_cycles(D + 8, 0, 100); // phase D: drain       -> read out everything left

        @(negedge clk);
        wr_en = 0;
        rd_en = 0;
        repeat (3) @(negedge clk);   // let the scoreboard check the last read

        $display("---- statistics ----");
        $display("cycles with full=1   : %0d", cyc_full);
        $display("cycles with empty=1  : %0d", cyc_empty);
        $display("cycles with wr&&rd   : %0d", cyc_both);
        $display("---- scoreboard ----");
        $display("checks: %0d, errors: %0d", checks, errors);
        if (errors == 0) $display("SCOREBOARD PASSED");
        else             $display("SCOREBOARD FAILED");
        $display("---- assertions ----");
        $display("assertion failures: %0d", sva.fails);
        $display("---- coverage ----");
        cov.report();
        $finish;
    end
endmodule
