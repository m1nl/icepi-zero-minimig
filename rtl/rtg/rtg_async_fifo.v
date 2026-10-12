// Dual-clock video FIFO

`default_nettype none
`timescale 1 ns / 1 ps
module rtg_async_fifo #(
  parameter ADDR_BITS = 9,
  parameter DATA_BITS = 16
) (
  input wire wr_clk,
  input wire rd_clk,
  input wire reset,

  input wire wr_en,
  input wire [DATA_BITS-1:0] wr_data,

  input wire rd_en,
  output reg [DATA_BITS-1:0] rd_data,

  output wire full,
  output wire empty,
  output wire [ADDR_BITS:0] wr_used,

  output wire wr_reset_busy,
  output wire rd_reset_busy
);

reg [DATA_BITS-1:0] ram [0:(1<<ADDR_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;

// Assert both domains together; release each on its own clock.
(* ASYNC_REG = "TRUE" *) reg [1:0] wr_rst_sync = 2'b11;
(* ASYNC_REG = "TRUE" *) reg [1:0] rd_rst_sync = 2'b11;

always @(posedge wr_clk or posedge reset) begin
  if (reset)
    wr_rst_sync <= 2'b11;
  else
    wr_rst_sync <= {wr_rst_sync[0],1'b0};
end

always @(posedge rd_clk or posedge reset) begin
  if (reset)
    rd_rst_sync <= 2'b11;
  else
    rd_rst_sync <= {rd_rst_sync[0],1'b0};
end

assign wr_reset_busy = wr_rst_sync[1];
assign rd_reset_busy = rd_rst_sync[1];

reg [ADDR_BITS:0] wr_bin, rd_bin, wr_gray, rd_gray;

(* ASYNC_REG = "TRUE" *) reg [ADDR_BITS:0] rd_gray_w1, rd_gray_w2;
(* ASYNC_REG = "TRUE" *) reg [ADDR_BITS:0] wr_gray_r1, wr_gray_r2;

wire [ADDR_BITS:0] wr_next = wr_bin + {{ADDR_BITS{1'b0}},1'b1};
wire [ADDR_BITS:0] rd_next = rd_bin + {{ADDR_BITS{1'b0}},1'b1};

assign full  = wr_gray == {~rd_gray_w2[ADDR_BITS:ADDR_BITS-1],rd_gray_w2[ADDR_BITS-2:0]};
assign empty = rd_gray == wr_gray_r2;

function [ADDR_BITS:0] gray_to_bin;
  input [ADDR_BITS:0] g;
  integer i;
  begin
    gray_to_bin[ADDR_BITS] = g[ADDR_BITS];
    for (i = ADDR_BITS-1;i >= 0;i = i - 1)
      gray_to_bin[i] = gray_to_bin[i+1] ^ g[i];
  end
endfunction

assign wr_used = wr_bin - gray_to_bin(rd_gray_w2);

always @(posedge wr_clk or posedge wr_reset_busy) begin
  if (wr_reset_busy) begin
    wr_bin <= 0;
    wr_gray <= 0;
    rd_gray_w1 <= 0;
    rd_gray_w2 <= 0;

  end else begin
    rd_gray_w1 <= rd_gray;
    rd_gray_w2 <= rd_gray_w1;

    if (wr_en && !full) begin
      wr_bin <= wr_next;
      wr_gray <= (wr_next >> 1) ^ wr_next;
    end
  end
end

always @(posedge rd_clk or posedge rd_reset_busy) begin
  if (rd_reset_busy) begin
    rd_bin <= 0;
    rd_gray <= 0;
    wr_gray_r1 <= 0;
    wr_gray_r2 <= 0;

  end else begin
    wr_gray_r1 <= wr_gray;
    wr_gray_r2 <= wr_gray_r1;

    if (rd_en && !empty) begin
      rd_bin <= rd_next;
      rd_gray <= (rd_next >> 1) ^ rd_next;
    end
  end
end

always @(posedge wr_clk)
  if (!wr_reset_busy && wr_en && !full)
    ram[wr_bin[ADDR_BITS-1:0]] <= wr_data;

always @(posedge rd_clk)
  if (!rd_reset_busy && rd_en && !empty)
    rd_data <= ram[rd_bin[ADDR_BITS-1:0]];

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
