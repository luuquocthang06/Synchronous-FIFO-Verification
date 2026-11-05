// Synchronous FIFO (single clock) - Design Under Test
// - Pointers have 1 extra bit to tell "full" apart from "empty"
// - Write when full and read when empty are ignored
// - data_out is registered: valid 1 clock cycle after rd_en
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,     // active-low async reset
    input  wire                  wr_en,
    input  wire                  rd_en,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out,
    output wire                  full,
    output wire                  empty
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]       wr_ptr;   // 1 extra bit
    reg [ADDR_W:0]       rd_ptr;   // 1 extra bit

    assign empty = (wr_ptr == rd_ptr);
`ifdef BUG1
    // BUG1: extra pointer bit forgotten -> full looks the same as empty
    assign full  = (wr_ptr == rd_ptr);
`else
    assign full  = (wr_ptr[ADDR_W]     != rd_ptr[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
`endif

`ifdef BUG2
    // BUG2: write is not blocked when the FIFO is full
    wire do_write = wr_en;
`elsif BUG5
    // BUG5: the write is dropped when a read happens in the same cycle
    wire do_write = wr_en && !full && !(rd_en && !empty);
`else
    wire do_write = wr_en && !full;
`endif

`ifdef BUG3
    // BUG3: read is not blocked when the FIFO is empty
    wire do_read  = rd_en;
`else
    wire do_read  = rd_en && !empty;
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= 0;
            rd_ptr   <= 0;
            data_out <= 0;
        end else begin
            if (do_write) begin
`ifdef BUG4
                // BUG4: bit 0 is lost, but only for the last memory location
                mem[wr_ptr[ADDR_W-1:0]] <= (wr_ptr[ADDR_W-1:0] == DEPTH-1)
                                           ? {data_in[DATA_WIDTH-1:1], 1'b0}
                                           : data_in;
`else
                mem[wr_ptr[ADDR_W-1:0]] <= data_in;
`endif
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (do_read) begin
                data_out <= mem[rd_ptr[ADDR_W-1:0]];
                rd_ptr   <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
