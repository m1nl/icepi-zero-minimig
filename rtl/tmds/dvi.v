/*
my_hdmi_device 

Copyright (C) 2021  Hirosh Dabui <hirosh@dabui.de>
with modifications to support a pixel clock subdiving the system clock
by Alastair M. Robinson.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
module dvi #(parameter DDR_ENABLED=1) (
           input pclk,
           input tmds_clk, /* 10 times faster of pclk */

           input [7:0] in_vga_red,
           input [7:0] in_vga_green,
           input [7:0] in_vga_blue,

           input in_vga_vsync,
           input in_vga_hsync,

           input in_vga_pixel,
           input in_vga_window,

           output reg [DDR_ENABLED:0] out_tmds_red,
           output reg [DDR_ENABLED:0] out_tmds_green,
           output reg [DDR_ENABLED:0] out_tmds_blue,
           output reg [DDR_ENABLED:0] out_tmds_clk,
           output reg [DDR_ENABLED:0] out_tmds_red_n,
           output reg [DDR_ENABLED:0] out_tmds_green_n,
           output reg [DDR_ENABLED:0] out_tmds_blue_n,
           output reg [DDR_ENABLED:0] out_tmds_clk_n
       );

localparam OUT_TMDS_MSB = DDR_ENABLED ? 1 : 0;

/* */
wire [9:0] tmds_red;
wire [9:0] tmds_green;
wire [9:0] tmds_blue;

`define USE4BITENCODER

`ifdef USE4BITENCODER

tinytmds enc_red (
	.clk(pclk),
	.reset_n(1'b1),
	.blank(~in_vga_window),
	.hs(1'b0),
	.vs(1'b0),
	.d(in_vga_red),
	.q(tmds_red)
);

tinytmds enc_green (
	.clk(pclk),
	.reset_n(1'b1),
	.blank(~in_vga_window),
	.hs(1'b0),
	.vs(1'b0),
	.d(in_vga_green),
	.q(tmds_green)
);

tinytmds enc_blue (
	.clk(pclk),
	.reset_n(1'b1),
	.blank(~in_vga_window),
	.hs(in_vga_hsync),
	.vs(in_vga_vsync),
	.d(in_vga_blue),
	.q(tmds_blue)
);

`else

tmds_encoder tmsds_encoder_i0(pclk, in_vga_pixel, in_vga_window, in_vga_red,   1'b0,         1'b0,         tmds_red);
tmds_encoder tmsds_encoder_i1(pclk, in_vga_pixel, in_vga_window, in_vga_green, 1'b0,         1'b0,         tmds_green);
tmds_encoder tmsds_encoder_i2(pclk, in_vga_pixel, in_vga_window, in_vga_blue,  in_vga_vsync, in_vga_hsync, tmds_blue);
`endif

/* */
reg       tmds_shift_load   = 0;
reg [3:0] tmds_modulo       = 0;
reg [9:0] tmds_shift_red    = 0;
reg [9:0] tmds_shift_green  = 0;
reg [9:0] tmds_shift_blue   = 0;
reg [9:0] tmds_shift_clk    = 0;

wire [9:0] tmds_pixel_clk = 10'b00000_11111;
/* ddr 5 shifts a 2 bits, sdr 10 shifts a 1 bit */

wire max_shifts_reached = (tmds_modulo == (DDR_ENABLED ? 4 : 9));
always @(posedge tmds_clk) tmds_modulo      <= max_shifts_reached ? 0 : tmds_modulo + 1;
always @(posedge tmds_clk) tmds_shift_load  <= max_shifts_reached;

reg [9:0] tmds_red_r;
reg [9:0] tmds_green_r;
reg [9:0] tmds_blue_r;

always @(posedge tmds_clk) begin
	tmds_red_r <= tmds_red;
	tmds_green_r <= tmds_green;
	tmds_blue_r <= tmds_blue;
end

always @(posedge tmds_clk) begin
    tmds_shift_red    <= tmds_shift_load ? tmds_red_r       : {DDR_ENABLED ? 2'b00 : 1'b0, tmds_shift_red   [9: DDR_ENABLED ? 2 : 1]};
    tmds_shift_green  <= tmds_shift_load ? tmds_green_r     : {DDR_ENABLED ? 2'b00 : 1'b0, tmds_shift_green [9: DDR_ENABLED ? 2 : 1]};
    tmds_shift_blue   <= tmds_shift_load ? tmds_blue_r      : {DDR_ENABLED ? 2'b00 : 1'b0, tmds_shift_blue  [9: DDR_ENABLED ? 2 : 1]};
    tmds_shift_clk    <= tmds_shift_load ? tmds_pixel_clk : {DDR_ENABLED ? 2'b00 : 1'b0, tmds_shift_clk   [9: DDR_ENABLED ? 2 : 1]};
end

always @(posedge tmds_clk) begin
	out_tmds_clk   = tmds_shift_clk    [ OUT_TMDS_MSB : 0 ];
	out_tmds_red   = tmds_shift_red    [ OUT_TMDS_MSB : 0 ];
	out_tmds_green = tmds_shift_green  [ OUT_TMDS_MSB : 0 ];
	out_tmds_blue  = tmds_shift_blue   [ OUT_TMDS_MSB : 0 ];

	out_tmds_clk_n   = ~tmds_shift_clk    [ OUT_TMDS_MSB : 0 ];
	out_tmds_red_n   = ~tmds_shift_red    [ OUT_TMDS_MSB : 0 ];
	out_tmds_green_n = ~tmds_shift_green  [ OUT_TMDS_MSB : 0 ];
	out_tmds_blue_n  = ~tmds_shift_blue   [ OUT_TMDS_MSB : 0 ];
end

endmodule
