// HDMI captures the held stereo pair on sample_en. Its acknowledgement
// crosses back to Paula's clock before the next pair is refreshed.
// At 48 kHz the pair is stable for many cycles before the next capture.

`default_nettype none
`timescale 1 ns / 1 ps
module audio_cdc (
  input wire clk,
  input wire clk_pixel,

  input wire [15:0] audio_l,
  input wire [15:0] audio_r,

  input wire        sample_en,
  output reg [31:0] sample
);

(* ASYNC_REG = "TRUE" *) reg [1:0] sample_ack_sync;

reg sample_ack;
reg sample_ack_seen;

always @(posedge clk_pixel) begin
  if (sample_en)
    sample_ack <= ~sample_ack;
end

always @(posedge clk) begin
  sample_ack_sync <= {sample_ack_sync[0], sample_ack};

  if (sample_ack_sync[1] != sample_ack_seen) begin
    sample          <= {audio_r, audio_l};
    sample_ack_seen <= sample_ack_sync[1];
  end
end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
