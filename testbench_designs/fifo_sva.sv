// Step 5: SystemVerilog Assertions (SVA) for sync_fifo
// A passive checker: it only watches the ports, never drives anything.
module fifo_sva #(
    parameter W = 8,
    parameter D = 16
) (
    input logic         clk,
    input logic         rst_n,
    input logic         wr_en,
    input logic         rd_en,
    input logic         full,
    input logic         empty,
    input logic [W-1:0] data_out
);

    int fails = 0;

    // 1) FIFO can never be full and empty at the same time
    a_not_full_and_empty: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(full && empty)
    ) else begin fails++; $error("full and empty are both 1"); end

    // 2) flags are never X/Z once reset is released
    a_no_x_flags: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({full, empty})
    ) else begin fails++; $error("full/empty is X or Z"); end

    // 3) right after reset is released the FIFO is empty and not full
    a_empty_after_reset: assert property (
        @(posedge clk)
        $rose(rst_n) |-> (empty && !full)
    ) else begin fails++; $error("FIFO not empty after reset"); end

    // 4) writing into an empty FIFO makes it non-empty
    a_write_makes_nonempty: assert property (
        @(posedge clk) disable iff (!rst_n)
        (empty && wr_en) |=> !empty
    ) else begin fails++; $error("write to empty FIFO did not clear empty"); end

    // 5) reading from a full FIFO makes it non-full
    a_read_makes_nonfull: assert property (
        @(posedge clk) disable iff (!rst_n)
        (full && rd_en) |=> !full
    ) else begin fails++; $error("read from full FIFO did not clear full"); end

    // 6) writing to a full FIFO (without a read) must be ignored: still full
    a_full_stays_full: assert property (
        @(posedge clk) disable iff (!rst_n)
        (full && wr_en && !rd_en) |=> full
    ) else begin fails++; $error("write on full FIFO changed the state"); end

    // 7) reading from an empty FIFO (without a write) must be ignored: still empty
    a_empty_stays_empty: assert property (
        @(posedge clk) disable iff (!rst_n)
        (empty && rd_en && !wr_en) |=> empty
    ) else begin fails++; $error("read on empty FIFO changed the state"); end

    // 8) reading from an empty FIFO must not change data_out
    a_empty_read_keeps_data: assert property (
        @(posedge clk) disable iff (!rst_n)
        (empty && rd_en) |=> $stable(data_out)
    ) else begin fails++; $error("data_out changed on a read from empty FIFO"); end

endmodule
