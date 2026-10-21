module circular_fifo #(
  parameter WIDTH = 8,
  parameter DEPTH = 8,
  parameter FLAG_WIDTH = 1
) (
  input  wire clk,
  input  wire rst,

  input  wire             wr_en,
  input  wire [WIDTH-1:0] din,

  input  wire             rd_ack,
  output wire [WIDTH-1:0] dout,

  output wire empty,

  input  wire [FLAG_WIDTH-1:0] flag_in,
  output wire [FLAG_WIDTH-1:0] flag_out
);

localparam ADDR_W = $clog2(DEPTH);

`ifdef FIFO_FLAG_STORE_REGISTER
// DEPTH must be a power of two. The producer must keep fewer than DEPTH
// entries pending: pointer equality denotes empty and there is no full guard.
reg [WIDTH-1:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle = "distributed" */;

// Sideband flags use a flat register vector, separate from the data memory.
reg [DEPTH*FLAG_WIDTH-1:0] flags /* synthesis syn_ramstyle = "registers" */;

assign flag_out = flags[rd_ptr*FLAG_WIDTH +: FLAG_WIDTH];
`else
// DEPTH must be a power of two. The producer must keep fewer than DEPTH
// entries pending: pointer equality denotes empty and there is no full guard.
reg [WIDTH+FLAG_WIDTH-1:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle = "distributed" */;

assign flag_out = mem[rd_ptr][WIDTH +: FLAG_WIDTH];
`endif

reg [ADDR_W-1:0] wr_ptr;
reg [ADDR_W-1:0] rd_ptr;

assign empty = (wr_ptr == rd_ptr);
assign dout  = mem[rd_ptr][WIDTH-1:0];

always @(posedge clk) begin
  if (rst) begin
    wr_ptr <= 0;
    rd_ptr <= 0;
  end else begin
    // write side
    if (wr_en) begin
`ifdef FIFO_FLAG_STORE_REGISTER
      mem[wr_ptr] <= din;
      flags[wr_ptr*FLAG_WIDTH +: FLAG_WIDTH] <= flag_in;
`else
      mem[wr_ptr] <= {flag_in, din};
`endif
      wr_ptr <= wr_ptr + 1;   // wraps naturally
    end
    // read side
    if (rd_ack && !empty) begin
      rd_ptr <= rd_ptr + 1;   // wraps naturally
    end
  end
end

endmodule
