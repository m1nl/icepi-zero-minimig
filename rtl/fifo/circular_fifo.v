module circular_fifo #(
  parameter WIDTH = 8,
  parameter DEPTH = 8
) (
  input  wire clk,
  input  wire rst,

  input  wire             wr_en,
  input  wire [WIDTH-1:0] din,

  input  wire             rd_ack,
  output wire [WIDTH-1:0] dout,

  output wire empty
);

localparam ADDR_W = $clog2(DEPTH);

reg [WIDTH-1:0] mem [0:DEPTH-1];

reg [ADDR_W-1:0] wr_ptr;
reg [ADDR_W-1:0] rd_ptr;

assign empty = (wr_ptr == rd_ptr);
assign dout  = mem[rd_ptr];

always @(posedge clk) begin
  if (rst) begin
    wr_ptr <= 0;
    rd_ptr <= 0;
  end else begin
    // write side
    if (wr_en) begin
      mem[wr_ptr] <= din;
      wr_ptr <= wr_ptr + 1;   // wraps naturally
    end
    // read side
    if (rd_ack && !empty) begin
      rd_ptr <= rd_ptr + 1;   // wraps naturally
    end
  end
end

endmodule
