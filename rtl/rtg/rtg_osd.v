// Mirror the native 256x64 menu at 1x horizontal / 2x vertical scale,
// positioned by HDMI's one-bit visibility/start requests.

`default_nettype none
`timescale 1 ns / 1 ps
module rtg_osd (
  input wire clk_write,
  input wire clk_rtg,
  input wire reset_n,
  input wire video_reset,

  input wire [10:0] write_addr,
  input wire [7:0]  write_data,
  input wire        write_en,

  input wire        enable,
  input wire pixel_request,
  input wire frame_request,

  output reg overlay,
  output reg pixel
);

reg [7:0] ram [0:2047] /* synthesis syn_ramstyle="block_ram" */;
reg [7:0] data_read;

reg [7:0] column;
reg [6:0] row;

reg pixel_request_d;

wire  [6:0] current_row = frame_request ? 7'd0 : row;
wire [10:0] addr = {current_row[6:4], column};

always @(posedge clk_write)
  if (write_en)
    ram[write_addr] <= write_data;

always @(posedge clk_rtg)
  data_read <= ram[addr];

(* ASYNC_REG = "TRUE" *) reg [1:0] enable_sync;

reg frame_enable;

reg [2:0] bit_index;

reg pixel_r1;

reg overlay_r1;
reg overlay_r2;

always @(posedge clk_rtg or negedge reset_n) begin
  if (!reset_n) begin
    enable_sync <= 2'b0;

    frame_enable <= 0;
    overlay_r1   <= 0;
    overlay_r2   <= 0;
    overlay      <= 0;

  end else begin
    enable_sync <= {enable_sync[0], enable};

    if (video_reset)
      frame_enable <= 0;
    else if (frame_request)
      frame_enable <= enable_sync[1];

    pixel_request_d <= pixel_request;

    if (pixel_request)
      column <= column + 1;
    else
      column <= 0;

    if (frame_request)
      row <= 0;
    else if (pixel_request_d && !pixel_request)
      row <= row + 1;

    overlay_r1 <= pixel_request && frame_enable;
    overlay_r2 <= overlay_r1;
    overlay    <= overlay_r2;

    bit_index <= current_row[3:1];

    pixel_r1 <= data_read[bit_index];
    pixel    <= pixel_r1;
  end
end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
