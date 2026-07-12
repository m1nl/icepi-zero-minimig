////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// Copyright 2006, 2007 Dennis van Weeren                                     //
//                                                                            //
// This file is part of Minimig                                               //
//                                                                            //
// Minimig is free software; you can redistribute it and/or modify            //
// it under the terms of the GNU General Public License as published by       //
// the Free Software Foundation; either version 3 of the License, or          //
// (at your option) any later version.                                        //
//                                                                            //
// Minimig is distributed in the hope that it will be useful,                 //
// but WITHOUT ANY WARRANTY; without even the implied warranty of             //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              //
// GNU General Public License for more details.                               //
//                                                                            //
// You should have received a copy of the GNU General Public License          //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.      //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
// This is the user IO module                                                 //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////



module userio (
  input  wire           clk,                // bus clock
  input  wire           reset,              // reset
  input  wire           clk7_en,
  input  wire           clk7n_en,
  input  wire           c1,
  input  wire           c3,
  input  wire           sol,                // start of video line
  input  wire           sof,                // start of video frame
  input  wire           varbeamen,
  input  wire           rtg_ena,
  input  wire [  9-1:1] reg_address_in,     // register adress inputs
  input  wire [ 16-1:0] data_in,            // bus data in
  output reg  [ 16-1:0] data_out,           // bus data out
  input  wire           ps2mdat_i,            // mouse PS/2 data
  input  wire           ps2mclk_i,            // mouse PS/2 clk
  output wire           ps2mdat_o,            // mouse PS/2 data
  output wire           ps2mclk_o,            // mouse PS/2 clk
  output wire           _fire0,             // joystick 0 fire output (to CIA)
  output wire           _fire1,             // joystick 1 fire output (to CIA)
  input  wire           _fire0_dat,
  input  wire           _fire1_dat,
  input  wire [ 16-1:0] _joy1,              // joystick 1 in (default mouse port)
  input  wire [ 16-1:0] _joy2,              // joystick 2 in (default joystick port)
  input  wire [ 16-1:0] joy_ana,            // analogue joystick (default joystick port)
  input  wire           aflock,             // auto fire lock
  input  wire [  3-1:0] mouse0_btn,
  input  wire [  3-1:0] mouse1_btn,
  input  wire           mouse_idx,
  input  wire           _lmb,
  input  wire           _rmb,
  input  wire [  6-1:0] mou_emu,
  input  wire           kbd_mouse_strobe,
  input  wire           kms_level,
  input  wire [  2-1:0] kbd_mouse_type,
  input  wire [  8-1:0] kbd_mouse_data,
  input  wire [  8-1:0] osd_ctrl,           // OSD control (minimig->host, [menu,select,down,up])
  output reg            keyboard_disabled,  // disables Amiga keyboard while OSD is active
  input  wire           _scs,               // SPI enable
  input  wire           sdi,                // SPI data in
  output wire           sdo,                // SPI data out
  input  wire           sck,                // SPI clock
  output wire           osd_blank,          // osd overlay, normal video blank output
  output wire           osd_pixel,          // osd video pixel
  output wire [  2-1:0] lr_filter,
  output wire [  2-1:0] hr_filter,
  output wire [  7-1:0] memory_config,
  output wire [  5-1:0] chipset_config,
  output wire [  4-1:0] floppy_config,
  output wire [  2-1:0] scanline,
  output wire [  2-1:0] dither,
  output wire [  3-1:0] ide_config0,
  output wire [  3-1:0] ide_config1,
  output wire [  4-1:0] cpu_config,
  output wire           overclock,
  output wire [  2-1:0] audio_filter_mode,
  output wire           pwr_led_dim_n,
  output                usrrst,             // user reset from osd module
  output                cpurst,
  output                cpuhlt,
  output wire           fifo_full,
  // host
  output wire           host_cs,
  output wire [ 24-1:0] host_adr,
  output wire           host_we,
  output wire [  2-1:0] host_bs,
  output wire [ 16-1:0] host_wdat,
  input  wire [ 16-1:0] host_rdat,
  input  wire           host_ack
);


// register names and adresses
parameter JOY0DAT     = 9'h00a;
parameter JOY1DAT     = 9'h00c;
parameter SCRDAT      = 9'h1f0;
parameter POT0DAT     = 9'h012;
parameter POT1DAT     = 9'h014;
parameter POTINP      = 9'h016;
parameter POTGO       = 9'h034;
parameter JOYTEST     = 9'h036;
parameter KEY_MENU    = 8'h69;
parameter KEY_ESC     = 8'h45;
parameter KEY_ENTER   = 8'h44;
parameter KEY_UP      = 8'h4C;
parameter KEY_DOWN    = 8'h4D;
parameter KEY_LEFT    = 8'h4F;
parameter KEY_RIGHT   = 8'h4E;
parameter KEY_PGUP    = 8'h6c;
parameter KEY_PGDOWN  = 8'h6d;


// local signals
reg  [15:0] _sjoy1;       // synchronized joystick 1 signals
reg  [15:0] _djoy1;       // synchronized joystick 1 signals
reg  [15:0] _xjoy1;       // synchronized joystick 1 signals
reg  [15:0] _xjoy2;       // synchronized joystick 2 signals
reg  [15:0] _tjoy2;       // synchronized joystick 2 signals
reg  [15:0] _djoy2;       // synchronized joystick 2 signals
wire [15:0] _sjoy2;       // synchronized joystick 2 signals
reg  [15:0] potreg;       // POTGO write
wire        pot_cnt_en = sol && !c1 && !c3; // one count / scanline
reg   [7:0] pot0x;
reg   [7:0] pot0y;
reg   [7:0] pot1x;
reg   [7:0] pot1y;
wire  [15:0] mouse0dat;      //mouse counters for first mouse
wire  [15:0] mouse1dat;      //mouse counters for second mouse
wire  [7:0]  mouse0scr;   // mouse scroller
reg   [15:0] dmouse0dat;      // docking mouse counters
reg   [15:0] dmouse1dat;      // docking mouse counters
wire  _mleft0;            //left mouse button
wire  _mthird0;          //middle mouse button
wire  _mright0;          //right mouse buttons
wire  _mleft1;            //left mouse button
wire  _mthird1;          //middle mouse button
wire  _mright1;          //right mouse buttons
reg    joy1enable;          //joystick 1 enable (mouse/joy switch)
wire   joy2enable;          //joystick 2 enable when no osd
reg    mouse2enable;
wire  osd_enable;          // OSD display enable
wire  key_disable;        // Amiga keyboard disable
reg    [7:0] t_osd_ctrl;      //JB: osd control lines
wire  test_load;          //load test value to mouse counter
wire  [15:0] test_data;      //mouse counter test value
wire  [1:0] autofire_config;
reg   [1:0] autofire_cnt;
wire  cd32pad;
wire  anajoy;
wire  invertjoy;
reg   autofire;
reg   sel_autofire;     // select autofire and permanent fire
wire  joy2_pin5;
wire  joy1_pin5;
wire cd32pad1_reg_load;
wire cd32pad1_reg_shift;
wire cd32pad2_reg_load;
wire cd32pad2_reg_shift;


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// POTGO register
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      potreg <= #1 0;
    else if (reg_address_in[8:1]==POTGO[8:1])
      potreg[15:0] <= #1 data_in[15:0];
    else
      potreg[0] <= 0;
  end
end

// POT[0/1]DAT registers
reg [3:0] potcnt; // is the POT counting?

// button on the pot pins
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      {pot0x, pot0y, pot1x, pot1y} <= 0;
      potcnt <= 4'b0000;
    end else if (potreg[0]) begin
      {pot0x, pot0y, pot1x, pot1y} <= 0;
      potcnt <= 4'b1111;
    end
    else if (pot_cnt_en) begin
      if (!potcap[0]) pot0x <= pot0x + 1'd1;
      if (!potcap[1]) pot0y <= pot0y + 1'd1;
      if (anajoy) begin
        if (potcnt[2] && joy_ana[15:8] != pot1y) pot1y <= pot1y + 1'd1; else potcnt[2] <= 0;
        if (potcnt[3] && joy_ana[ 7:0] != pot1x) pot1x <= pot1x + 1'd1; else potcnt[3] <= 0;
      end else begin
        if (!potcap[2]) pot1x <= pot1x + 1'd1;
        if (!potcap[3]) pot1y <= pot1y + 1'd1;
      end
    end
  end
end

assign joy2_pin5 = ~(potreg[13] & ~potreg[12]);
assign joy1_pin5 = ~(potreg[9]  & ~potreg[8]);

// potcap reg
reg  [4-1:0] potcap;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      potcap <= #1 4'h0;
    else begin
      if (anajoy)
        potcap[3] <= ~(potreg[15] & ~potreg[14]); // pin9
      else if (cd32pad && ~joy2_pin5)
        potcap[3] <= #1 cd32pad2_reg[7];
      else
        potcap[3] <= #1 _mright1 & _djoy2[5] & ~(potreg[15] & ~potreg[14]);

      potcap[2] <= #1 _mthird1 & joy2_pin5; // pin5.

      if(joy1enable & cd32pad & ~joy1_pin5)
        potcap[1] <= #1 cd32pad1_reg[7];
      else
        potcap[1] <= #1 _mright0 & _rmb & _djoy1[5] & ~(potreg[11] & ~potreg[10]);

      potcap[0] <= #1 _mthird0 & joy1_pin5;
    end
  end
end

// cd32pad1 reg
reg fire1_d;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fire1_d <= #1 1'b1;
    else
      fire1_d <= #1 _fire0_dat;
  end
end

assign cd32pad1_reg_load = joy1_pin5;
assign cd32pad1_reg_shift = _fire0_dat && !fire1_d;
reg [8-1:0] cd32pad1_reg;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      cd32pad1_reg <= #1 8'hff;
    else if (cd32pad1_reg_load)
      cd32pad1_reg <= #1 {_djoy1[5], _djoy1[4], _djoy1[6], _djoy1[7], _djoy1[8], _djoy1[9], _djoy1[10], 1'b1};
    else if (cd32pad1_reg_shift)
      cd32pad1_reg <= #1 {cd32pad1_reg[6:0], 1'b0};
  end
end

// cd32pad2 reg
reg fire2_d;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      fire2_d <= #1 1'b1;
    else
      fire2_d <= #1 _fire1_dat;
  end
end

assign cd32pad2_reg_load  = joy2_pin5;
assign cd32pad2_reg_shift = _fire1_dat && !fire2_d;
reg [8-1:0] cd32pad2_reg;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      cd32pad2_reg <= #1 8'hff;
    else if (cd32pad2_reg_load)
      cd32pad2_reg <= #1 {_djoy2[5], _djoy2[4], _djoy2[6], _djoy2[7], _djoy2[8], _djoy2[9], _djoy2[10], 1'b1};
    else if (cd32pad2_reg_shift)
      cd32pad2_reg <= #1 {cd32pad2_reg[6:0], 1'b0};
  end
end

// autofire pulses generation
always @ (posedge clk) begin
  if (clk7_en) begin
    if (sof)
      if (autofire_cnt == 1)
        autofire_cnt <= #1 autofire_config;
      else
        autofire_cnt <= #1 autofire_cnt - 2'd1;
  end
end

// autofire
always @ (posedge clk) begin
  if (clk7_en) begin
    if (sof)
      if (autofire_config == 2'd0)
        autofire <= #1 1'b0;
      else if (autofire_cnt == 2'd1)
        autofire <= #1 ~autofire;
  end
end

// auto fire function toggle via capslock status
always @ (posedge clk) begin
  if (clk7_en) begin
    sel_autofire <= #1 (~aflock ^ _xjoy2[4]) ? autofire : 1'b0;
  end
end

// disable keyboard when OSD is displayed
always @ (*) keyboard_disabled = key_disable;

// input synchronization of external signals
always @ (posedge clk) begin
  if (clk7_en) begin
    _sjoy1 <= #1 ~key_disable ? (invertjoy ? _joy2 : _joy1) : 16'hffff;
    _djoy1 <= #1 ~key_disable ? _sjoy1 : 16'hffff;
    _tjoy2 <= #1   joy2enable ? (invertjoy ? _joy1 : _joy2) : 16'hffff;
    _djoy2 <= #1   joy2enable ? _tjoy2 : 16'hffff;
    if (sof) begin
      _xjoy1 <= #1 (invertjoy ? _joy2 : _joy1);
      _xjoy2 <= #1 (invertjoy ? _joy1 : _joy2);
    end
  end
end

wire _tpin4 = anajoy ? _tjoy2[5] : _tjoy2[0];
wire _tpin3 = anajoy ? _tjoy2[4] : _tjoy2[1];
wire _tpin2 = anajoy ?      1'b1 : _tjoy2[2];
wire _tpin1 = anajoy ? _tjoy2[6] : _tjoy2[3];

wire _dpin4 = anajoy ? _djoy2[5] : _djoy2[0];
wire _dpin3 = anajoy ? _djoy2[4] : _djoy2[1];
wire _dpin2 = anajoy ?      1'b1 : _djoy2[2];
wire _dpin1 = anajoy ? _djoy2[6] : _djoy2[3];

// port 2 joystick disable in osd or when second mouse left button is pressed
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset)
      mouse2enable <= 0;
    else
      if (!_mleft1)
        mouse2enable <= 1;
      else if (!_xjoy2[4])
        mouse2enable <= 0;
  end
end

assign joy2enable = !mouse2enable && !key_disable;

// autofire is permanent active if enabled, can be overwritten any time by normal fire button
assign _sjoy2[5:0] = joy2enable ? {_xjoy2[5], sel_autofire ^ _xjoy2[4], _xjoy2[3:0]} : 6'b11_1111;

always @ (*) begin
  if (~joy2enable)
//    if (~_xjoy2[5] || (~_xjoy2[3] && ~_xjoy2[2]))	// Obsolete, dates back to original Minimig.
//      t_osd_ctrl = KEY_MENU;
    if (~_xjoy1[11] || ~_xjoy2[11])
      t_osd_ctrl = KEY_MENU;
    else if (~_xjoy1[4] || ~_xjoy2[4])
      t_osd_ctrl = KEY_ENTER;
    else if (~_xjoy1[3] || ~_xjoy2[3])
      t_osd_ctrl = KEY_UP;
    else if (~_xjoy1[2] || ~_xjoy2[2])
      t_osd_ctrl = KEY_DOWN;
    else if (~_xjoy1[1] || ~_xjoy2[1])
      t_osd_ctrl = KEY_LEFT;
    else if (~_xjoy1[0] || ~_xjoy2[0])
      t_osd_ctrl = KEY_RIGHT;
//    else if (~_xjoy2[1] && ~_xjoy2[3])
//      t_osd_ctrl = KEY_PGUP;
//    else if (~_xjoy2[0] && ~_xjoy2[2])
//      t_osd_ctrl = KEY_PGDOWN;
    else
      t_osd_ctrl = osd_ctrl;
  else begin
//    if (~_xjoy2[3] && ~_xjoy2[2])
//      t_osd_ctrl = KEY_MENU;
//    else
    if (~_xjoy1[11] || ~_xjoy2[11])
      t_osd_ctrl = KEY_MENU;
    else
      t_osd_ctrl = osd_ctrl;
  end
end

// port 1 automatic mouse/joystick switch
always @ (posedge clk) begin
  if (clk7_en) begin
    if (!_mleft0 || reset)//when left mouse button pushed, switch to mouse (default)
      joy1enable = 0;
    else if (!_sjoy1[4])//when joystick 1 fire pushed, switch to joystick
      joy1enable = 1;
  end
end

// Port 1
always @ (posedge clk) begin
  if (clk7_en) begin
    if (test_load)
      dmouse0dat[7:0] <= #1 8'h00;
    else if ((!_djoy1[0] && _sjoy1[0] && _sjoy1[2]) || (_djoy1[0] && !_sjoy1[0] && !_sjoy1[2]) || (!_djoy1[2] && _sjoy1[2] && !_sjoy1[0]) || (_djoy1[2] && !_sjoy1[2] && _sjoy1[0]))
      dmouse0dat[7:0] <= #1 dmouse0dat[7:0] + 1'd1;
    else if ((!_djoy1[0] && _sjoy1[0] && !_sjoy1[2]) || (_djoy1[0] && !_sjoy1[0] && _sjoy1[2]) || (!_djoy1[2] && _sjoy1[2] && _sjoy1[0]) || (_djoy1[2] && !_sjoy1[2] && !_sjoy1[0]))
      dmouse0dat[7:0] <= #1 dmouse0dat[7:0] - 1'd1;
    else
      dmouse0dat[1:0] <= #1 {!_djoy1[0], _djoy1[0] ^ _djoy1[2]};
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (test_load)
      dmouse0dat[15:8] <= #1 8'h00;
    else if ((!_djoy1[1] && _sjoy1[1] && _sjoy1[3]) || (_djoy1[1] && !_sjoy1[1] && !_sjoy1[3]) || (!_djoy1[3] && _sjoy1[3] && !_sjoy1[1]) || (_djoy1[3] && !_sjoy1[3] && _sjoy1[1]))
      dmouse0dat[15:8] <= #1 dmouse0dat[15:8] + 1'd1;
    else if ((!_djoy1[1] && _sjoy1[1] && !_sjoy1[3]) || (_djoy1[1] && !_sjoy1[1] && _sjoy1[3]) || (!_djoy1[3] && _sjoy1[3] && _sjoy1[1]) || (_djoy1[3] && !_sjoy1[3] && !_sjoy1[1]))
      dmouse0dat[15:8] <= #1 dmouse0dat[15:8] - 1'd1;
    else
      dmouse0dat[9:8] <= #1 {!_djoy1[1], _djoy1[1] ^ _djoy1[3]};
  end
end

// Port 2
always @ (posedge clk) begin
  if (clk7_en) begin
    if (test_load)
      dmouse1dat[7:2] <= #1 test_data[7:2];
    else if ((!_dpin4 && _tpin4 && _tpin2) || (_dpin4 && !_tpin4 && !_tpin2) || (!_dpin2 && _tpin2 && !_tpin4) || (_dpin2 && !_tpin2 && _tpin4))
      dmouse1dat[7:0] <= #1 dmouse1dat[7:0] + 1'd1;
    else if ((!_dpin4 && _tpin4 && !_tpin2) || (_dpin4 && !_tpin4 && _tpin2) || (!_dpin2 && _tpin2 && _tpin4) || (_dpin2 && !_tpin2 && !_tpin4))
      dmouse1dat[7:0] <= #1 dmouse1dat[7:0] - 1'd1;
    else
      dmouse1dat[1:0] <= #1 {!_dpin4, _dpin4 ^ _dpin2};
  end
end

always @ (posedge clk) begin
  if (clk7_en) begin
    if (test_load)
      dmouse1dat[15:10] <= #1 test_data[15:10];
    else if ((!_dpin3 && _tpin3 && _tpin1) || (_dpin3 && !_tpin3 && !_tpin1) || (!_dpin1 && _tpin1 && !_tpin3) || (_dpin1 && !_tpin1 && _tpin3))
      dmouse1dat[15:8] <= #1 dmouse1dat[15:8] + 1'd1;
    else if ((!_dpin3 && _tpin3 && !_tpin1) || (_dpin3 && !_tpin3 && _tpin1) || (!_dpin1 && _tpin1 && _tpin3) || (_dpin1 && !_tpin1 && !_tpin3))
      dmouse1dat[15:8] <= #1 dmouse1dat[15:8] - 1'd1;
    else
      dmouse1dat[9:8] <= #1 {!_dpin3, _dpin3 ^ _dpin1};
  end
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// data output multiplexer
always @(*) begin
  if ((reg_address_in[8:1]==JOY0DAT[8:1]) && joy1enable)//read port 1 joystick
    data_out[15:0] = {mouse0dat[15:10] + dmouse0dat[15:10],dmouse0dat[9:8],mouse0dat[7:2] + dmouse0dat[7:2],dmouse0dat[1:0]};
  else if (reg_address_in[8:1]==JOY0DAT[8:1])//read port 1 mouse
    data_out[15:0] = {mouse0dat[15:8] + dmouse0dat[15:8],mouse0dat[7:0] + dmouse0dat[7:0]};
  else if ((reg_address_in[8:1]==JOY1DAT[8:1]) && joy2enable)//read port 2 joystick
    data_out[15:0] = dmouse1dat;
  else if (reg_address_in[8:1]==JOY1DAT[8:1])//read port 2 mouse
    data_out[15:0] = mouse1dat;
  else if (reg_address_in[8:1]==POT0DAT[8:1])
    data_out[15:0] = { pot0y, pot0x };
  else if (reg_address_in[8:1]==POT1DAT[8:1])
    data_out[15:0] = { pot1y, pot1x };
  else if (reg_address_in[8:1]==POTINP[8:1])//read mouse and joysticks extra buttons
    data_out[15:0] = {1'b0, potcap[3],
                      1'b0, potcap[2],
                      1'b0, potcap[1],
                      1'b0, potcap[0],
                      8'h00};
  else if (reg_address_in[8:1]==SCRDAT[8:1])//read mouse scroll wheel
    data_out[15:0] = {8'h00,mouse0scr};
  else
    data_out[15:0] = 16'h0000;
end

// assign fire outputs to cia A
assign _fire0 = cd32pad && !cd32pad1_reg_load ? fire1_d : _sjoy1[4] & _mleft0 & _lmb;
assign _fire1 = cd32pad && !cd32pad2_reg_load ? fire2_d : _sjoy2[4] & _mleft1;

//JB: some trainers writes to JOYTEST register to reset current mouse counter
assign test_load = reg_address_in[8:1]==JOYTEST[8:1] ? 1'b1 : 1'b0;
assign test_data = data_in[15:0];


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------


`ifdef MINIMIG_PS2_MOUSE

//instantiate mouse controller
userio_ps2mouse pm1
(
  .clk        (clk),
  .clk7_en    (clk7_en),
  .reset      (reset),
  .ps2mdat_i  (ps2mdat_i),
  .ps2mclk_i  (ps2mclk_i),
  .ps2mdat_o  (ps2mdat_o),
  .ps2mclk_o  (ps2mclk_o),
  .mou_emu    (mou_emu),
  .sof        (sof),
  .zcount     (mouse0scr),
  .ycount     (mouse0dat[15:8]),
  .xcount     (mouse0dat[7:0]),
  ._mleft     (_mleft0),
  ._mthird    (_mthird0),
  ._mright    (_mright0),
  .test_load  (test_load),
  .test_data  (test_data)
);

assign _mleft1  = 1'b1;
assign _mright1 = 1'b1;
assign _mthird1 = 1'b1;

`else

//// MiST mouse ////
reg  [ 7:0] xcount0, xcount1;
reg  [ 7:0] ycount0, ycount1;
reg  [ 7:0] zcount0, zcount1;
reg         wheel_next; // next byte will be the wheel data
// mouse counters
always @(posedge clk) begin
	if(reset) begin
		xcount0 <= #1 8'd0;
		ycount0 <= #1 8'd0;
		zcount0 <= #1 8'd0;
		xcount1 <= #1 8'd0;
		ycount1 <= #1 8'd0;
		zcount1 <= #1 8'd0;
	end else if (test_load && clk7_en) begin
		ycount0[7:2] <= #1 test_data[15:10];
		xcount0[7:2] <= #1 test_data[7:2];
	end else if (kbd_mouse_strobe) begin
		if(kbd_mouse_type == 2'b00) begin
			wheel_next <= 0;
			if (!mouse_idx)
				xcount0[7:0] <= #1 xcount0[7:0] + kbd_mouse_data;
			else
				xcount1[7:0] <= #1 xcount1[7:0] + kbd_mouse_data;
		end else if(kbd_mouse_type == 2'b01) begin
			if (wheel_next)
				if (!mouse_idx)
					zcount0[7:0] <= #1 zcount0[7:0] - kbd_mouse_data;
				else
					zcount1[7:0] <= #1 zcount1[7:0] - kbd_mouse_data;
			else begin
				wheel_next <= 1;
				if (!mouse_idx)
					ycount0[7:0] <= #1 ycount0[7:0] + kbd_mouse_data;
				else
					ycount1[7:0] <= #1 ycount1[7:0] + kbd_mouse_data;
			end
		end
  end
end

// output
assign mouse0dat = {ycount0, xcount0};
assign mouse0scr = zcount0;
assign mouse1dat = {ycount1, xcount1};

// mouse buttons
assign _mleft0  = ~mouse0_btn[0];
assign _mright0 = ~mouse0_btn[1];
assign _mthird0 = ~mouse0_btn[2];

assign _mleft1  = ~mouse1_btn[0];
assign _mright1 = ~mouse1_btn[1];
assign _mthird1 = ~mouse1_btn[2];

`endif


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

`ifndef MINIMIG_ANAJOY
assign anajoy = 1'b0;
`endif

//instantiate osd controller
userio_osd osd1
(
  .clk              (clk),
  .clk7_en          (clk7_en),
  .clk7n_en         (clk7n_en),
  .reset            (reset),
  .c1               (c1),
  .c3               (c3),
  .sol              (sol),
  .sof              (sof),
  .varbeamen        (varbeamen),
  .rtg_ena          (rtg_ena),
  .osd_ctrl         (t_osd_ctrl),
  ._scs             (_scs),
  .sdi              (sdi),
  .sdo              (sdo),
  .sck              (sck),
  .osd_blank        (osd_blank),
  .osd_pixel        (osd_pixel),
  .osd_enable       (osd_enable),
  .key_disable      (key_disable),
  .lr_filter        (lr_filter),
  .hr_filter        (hr_filter),
  .memory_config    (memory_config),
  .chipset_config   (chipset_config),
  .floppy_config    (floppy_config),
  .scanline         (scanline),
  .dither           (dither),
  .ide_config0      (ide_config0),
  .ide_config1      (ide_config1),
  .cpu_config       (cpu_config),
  .overclock        (overclock),
  .autofire_config  (autofire_config),
  .cd32pad          (cd32pad),
`ifdef MINIMIG_ANAJOY
  .anajoy           (anajoy),
`else
  .anajoy           (),
`endif
  .invertjoy        (invertjoy),
  .audio_filter_mode(audio_filter_mode),
  .pwr_led_dim_n    (pwr_led_dim_n),
  .usrrst           (usrrst),
  .cpurst           (cpurst),
  .cpuhlt           (cpuhlt),
  .fifo_full        (fifo_full),
  .host_cs          (host_cs),
  .host_adr         (host_adr),
  .host_we          (host_we),
  .host_bs          (host_bs),
  .host_wdat        (host_wdat),
  .host_rdat        (host_rdat),
  .host_ack         (host_ack)
);


endmodule

