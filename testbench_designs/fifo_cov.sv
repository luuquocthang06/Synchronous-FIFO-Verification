// Step 6: functional coverage for sync_fifo
// Question answered: "did our random test actually visit all the situations we care about?"
//
// Default build  : manual coverage counters (works on any simulator, e.g. ModelSim Starter)
// +define+USE_COVERGROUP : real SystemVerilog covergroup (needs a simulator with coverage
//                          support: Riviera-PRO, VCS, Xcelium, Questa)
module fifo_cov #(
    parameter W = 8,
    parameter D = 16
) (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic full,
    input logic empty
);

    // The coverage block cannot see inside the DUT, so it tracks the FIFO level itself.
    int  level = 0;
    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    // level -> bin index: 0=zero, 1=low, 2=mid, 3=high, 4=full
    function automatic int lvl_idx(int l);
        if      (l == 0)         return 0;
        else if (l <= D/4)       return 1;
        else if (l <  3*D/4)     return 2;
        else if (l <  D)         return 3;
        else                     return 4;
    endfunction

`ifdef USE_COVERGROUP
    covergroup cg;
        cp_level: coverpoint level {
            bins zero   = {0};
            bins low    = {[1 : D/4]};
            bins mid    = {[D/4+1 : 3*D/4-1]};
            bins high   = {[3*D/4 : D-1]};
            bins full_b = {D};
        }
        cp_wr: coverpoint wr_en;
        cp_rd: coverpoint rd_en;
        // every combination of (level, write request, read request) = 5 x 2 x 2 = 20 bins
        x_level_wr_rd: cross cp_level, cp_wr, cp_rd;
    endgroup
    cg cg_inst = new();
`else
    int hits [5][2][2];   // [level bin][wr_en][rd_en], starts at 0
`endif

    // sample BEFORE the level is updated, so the bin matches the state seen by the DUT
    always @(posedge clk) begin
        if (!rst_n) begin
            level <= 0;
        end else begin
`ifdef USE_COVERGROUP
            cg_inst.sample();
`else
            hits[lvl_idx(level)][wr_en][rd_en]++;
`endif
            level <= level + do_wr - do_rd;
        end
    end

    task automatic report;
`ifdef USE_COVERGROUP
        $display("functional coverage: %0.1f %%", cg_inst.get_inst_coverage());
`else
        int covered = 0;
        string names [5] = '{"zero", "low", "mid", "high", "full"};
        for (int l = 0; l < 5; l++)
            for (int w = 0; w < 2; w++)
                for (int r = 0; r < 2; r++)
                    if (hits[l][w][r] > 0) covered++;
                    else $display("  NOT covered: level=%s wr_en=%0d rd_en=%0d", names[l], w, r);
        $display("cross coverage: %0d / 20 bins (%0.1f %%)", covered, covered * 100.0 / 20);
`endif
    endtask

endmodule
