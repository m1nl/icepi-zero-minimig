// Keep both DCSC selectors together and hold HDMI in reset during switching.
// Native video must be able to start independently of the auxiliary RTG PLL.

`default_nettype none
`timescale 1 ns / 1 ps
module video_clock_control (
  input wire clk,
  input wire clk_pixel,

  input wire native_locked,
  input wire rtg_locked,

  input  wire rtg_request,
  output reg  rtg_active,
  output wire video_reset
);

(* ASYNC_REG = "TRUE" *) reg [1:0] request_sync = 2'b00;
(* ASYNC_REG = "TRUE" *) reg [1:0] lock_sync    = 2'b00;

reg [5:0] switch_count  = 6'd63;
reg       switch_reset  = 1'b1;
reg       switch_target = 1'b0;

wire desired_mode  = request_sync[1] && lock_sync[1];
wire reset_request = !native_locked || !rtg_locked || switch_reset;

always @(posedge clk or negedge rtg_locked) begin
  if (!rtg_locked)
    lock_sync <= 2'b00;
  else
    lock_sync <= {lock_sync[0], 1'b1};
end

always @(posedge clk or negedge native_locked) begin
  if (!native_locked) begin
    request_sync  <= 2'b00;
    switch_count  <= 6'd63;
    switch_target <= 1'b0;
    rtg_active    <= 1'b0;
    switch_reset  <= 1'b1;

  end else begin
    request_sync <= {request_sync[0], rtg_request};

    if (switch_count != 0) begin
      switch_count <= switch_count - 1'b1;

      // Give reset three board-clock cycles before changing selectors.
      if (switch_count == 6'd60)
      rtg_active <= switch_target && lock_sync[1];

      // Allow both glitchless clock muxes to settle before release.
      if (switch_count == 1)
      switch_reset <= 1'b0;

    end else if (desired_mode != rtg_active) begin
      switch_target <= desired_mode;
      switch_count  <= 6'd63;
      switch_reset  <= 1'b1;

    end else
      switch_reset <= 1'b0;
  end
end

(* ASYNC_REG = "TRUE" *)
reg [1:0] reset_sync = 2'b11;

// Assertion also works while the selected pixel clock is stopped.
// Release occurs only after two edges of the selected pixel clock.
always @(posedge clk_pixel or posedge reset_request) begin
  if (reset_request)
    reset_sync <= 2'b11;
  else
    reset_sync <= {reset_sync[0], 1'b0};
end

assign video_reset = reset_sync[1];

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
