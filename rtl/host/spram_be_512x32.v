module spram_be_512x32 (
  input  wire        clk,
  input  wire [3:0]  wren,
  input  wire [8:0]  addr,
  input  wire [31:0] w,
  output reg  [31:0] q
);

reg [31:0] mem [0:511];

always @(posedge clk) begin
  // byte write enables
  if (wren[0])
    mem[addr][7:0]   <= w[7:0];

  if (wren[1])
    mem[addr][15:8]  <= w[15:8];

  if (wren[2])
    mem[addr][23:16] <= w[23:16];

  if (wren[3])
    mem[addr][31:24] <= w[31:24];

  // synchronous read
  q <= mem[addr];
end

endmodule
