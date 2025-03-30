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
// Agnus beamcounter                                                          //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


module agnus_beamcounter #(parameter wide_hblank=1'b0) 
(
	input	clk,					// bus clock
	input clk7_en,
	input	reset,					// reset
	input rd,	// Import read signal so we can guard against phantom writes to RTG
	input	cck,					// CCK clock
	input	ntsc,					// NTSC mode switch
	input aga,
	input	ecs,					// ECS enable switch
	input	a1k,					// enable A1000 VBL interrupt timing
	input	[15:0] data_in,			// bus data in
	output	reg [15:0] data_out,	// bus data out
	input 	[8:1] reg_address_in,	// register address inputs
	output  [8:0] hpos,			// horizontal beam counter (140ns)
	output	reg [10:0] vpos,		// vertical beam counter
	output	reg _hsync,				// horizontal sync
	output	wire hsyncpol,			// horizontal sync polarity
	output	reg _vsync,				// vertical sync
	output	wire vsyncpol,			// vertical sync polarity
	output	_csync,					// composite sync
	output	reg blank,				// video blanking
	output	vbl,					// vertical blanking
	output	vblend,					// last line of vertical blanking
	output	eol,					// end of video line
	output	eof,					// end of video frame
	output	reg vbl_int,			// vertical interrupt request (for Paula)
	output	[8:0] htotal_out,			// video line length
	output harddis_out,
	output varbeamen_out,
	output rtg_ena,
	output rtg_linecompare,
	output reg hblank_out,
	input  track_vsync,             // Input selector for alternative interlace-over-HDMI mode
	output long_frame
);

// local beam position counters
reg		ersy;
reg		lace;

//local signals for beam counters and sync generator
reg		long_frame_r;		// 1 : long frame (313 lines); 0 : normal frame (312 lines)
//wire		long_frame;
reg		long_line;		// long line signal for NTSC compatibility (actually long lines are not supported yet)
reg		vser;			// vertical sync serration pulses for composite sync

//register names and adresses		
parameter	VPOSR    = 9'h004;
parameter	VPOSW    = 9'h02A;
parameter	VHPOSR   = 9'h006;
parameter	VHPOSW   = 9'h02C;
parameter	BPLCON0  = 9'h100;
parameter	HTOTAL   = 9'h1C0;
parameter	HSSTOP   = 9'h1C2;
parameter	HBSTRT   = 9'h1C4;
parameter	HBSTOP   = 9'h1C6;
parameter	VTOTAL   = 9'h1C8;
parameter	VSSTOP   = 9'h1CA;
parameter	VBSTRT   = 9'h1CC;
parameter	VBSTOP   = 9'h1CE;
parameter	HSSTRT   = 9'h1DE;
parameter	BEAMCON0 = 9'h1DC;
parameter	VSSTRT   = 9'h1E0;
parameter	HCENTER  = 9'h1E2;
parameter	BPLHSTRT = 9'h1D4; // UHRES vstart - never implemented on real hardware - use for RTG split

parameter	HBSTRT_VAL      = 17+(wide_hblank ? -4 : 4)+4-12;// horizontal blanking start
parameter	HSSTRT_VAL      = 29+(wide_hblank ? -4 : 4)+4;	// front porch = 1.6us (29)
parameter	HSSTOP_VAL      = 63+(wide_hblank ? -9 : -1)+4+4;	// hsync pulse duration = 4.7us (63)  (AMR - why is the sync pulse narrowed? For the scandoubler maybe?)
parameter	HBSTOP_VAL      = 103-5+4-12;// back porch = 4.7us (103) shorter blanking for overscan visibility
parameter	HCENTER_VAL     = 256+(wide_hblank ? -4 : 4)+4;	// position of vsync pulse during the long field of interlaced screen
parameter	VSSTRT_VAL      = 2; //3	// vertical sync start
parameter	VSSTOP_VAL      = 5;	// PAL vsync width: 2.5 lines (NTSC: 3 lines - not implemented)
parameter	VBSTRT_VAL      = 0;	// vertical blanking start
parameter HTOTAL_VAL      = 9'd227 - 9'd1; // line length of 227 CCKs in PAL mode (NTSC line length of 227.5 CCKs is not supported)
parameter VTOTAL_PAL_VAL  = 11'd312 - 11'd1; // total number of lines (PAL: 312 lines, NTSC: 262)
parameter VTOTAL_NTSC_VAL = 11'd262 - 11'd1; // total number of lines (PAL: 312 lines, NTSC: 262)
parameter VBSTOP_PAL_VAL  = 11'd25; // vertical blanking end (PAL 26 lines, NTSC vblank 21 lines)
parameter VBSTOP_NTSC_VAL = 11'd20; // vertical blanking end (PAL 26 lines, NTSC vblank 21 lines)

//wire	[8:0] vbstop;		// vertical blanking stop

reg		end_of_line;
wire	end_of_frame;

reg 	vpos_inc;			// increase vertical position counter
wire 	vpos_equ_vtotal;	// vertical beam counter is equal to its maximum count (in interlaced mode it counts one line more)
reg		extra_line;			// extra line (used in interlaced mode)
wire	last_line;			// indicates the last line is displayed (in non-interlaced mode vpos equals to vtotal, in interlaced mode vpos equals to vtotal+1)


//beam position output signals
//assign	htotal = 8'd227 - 8'd1;                           // line length of 227 CCKs in PAL mode (NTSC line length of 227.5 CCKs is not supported)
//assign	vtotal = pal ? VTOTAL_PAL_VAL : VTOTAL_NTSC_VAL;  // total number of lines (PAL: 312 lines, NTSC: 262)
//assign	vbstop = pal ? VBSTOP_PAL_VAL : VBSTOP_NTSC_VAL;  // vertical blanking end (PAL 26 lines, NTSC vblank 21 lines)

//first visible line $1A (PAL) or $15 (NTSC)
//sprites are fetched on line $19 (PAL) or $14 (NTSC) - vblend signal used to tell Agnus to fetch sprites during the last vertical blanking line

//--------------------------------------------------------------------------------------

//beamcounter read registers VPOSR and VHPOSR
always @(*)
	if (reg_address_in[8:1]==VPOSR[8:1] || reg_address_in[8:1]==VPOSW[8:1])
		data_out[15:0] = {long_frame,1'b0,ecs,ntsc,2'b00,{2{aga}},long_line,4'b0000,vpos[10:8]};
	else if (reg_address_in[8:1]==VHPOSR[8:1] || reg_address_in[8:1]==VHPOSW[8:1])
		data_out[15:0] = {vpos[7:0],hpos[8:1]};
	else
		data_out[15:0] = 0;


// BEAMCON0 register
reg [15:0] beamcon0_reg;
reg [15:0] beamcon0_sh;
always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      beamcon0_reg <= #1 {10'b0, ~ntsc, 5'b0};
      beamcon0_sh <= #1 {10'b0, ~ntsc, 5'b0};
	 end else if ((reg_address_in[8:1] == BEAMCON0[8:1]) && ecs) begin
		// Write to shadow register only in RTG mode when lpendis or displaydual are high
		if(!rd && (data_in[13] || data_in[6]))
			beamcon0_sh <= #1 data_in;
		else // Otherwise update the non-shadowed reg 
			beamcon0_reg <= #1 data_in;
    end
  end
end


// Multiplex between standard and shadow regs depending on whether RTG is on.
wire harddis      = beamcon0_reg[14];
wire lpendis      = beamcon0_sh[13];
wire varvben      = displaydual ? beamcon0_sh[12] : beamcon0_reg[12];
wire loldis       = beamcon0_reg[11];
wire cscben       = beamcon0_reg[10];
wire varvsyen     = displaydual ? beamcon0_sh[9] :beamcon0_reg[ 9];
wire varhsyen     = displaydual ? beamcon0_sh[8] :beamcon0_reg[ 8];
wire varbeamen    = displaydual ? beamcon0_sh[7] :beamcon0_reg[ 7];
wire displaydual  = beamcon0_sh[ 6];
wire displaypal   = beamcon0_reg[ 5];
wire varcsyen     = displaydual ? beamcon0_sh[4] :beamcon0_reg[ 4];
wire blanken      = displaydual ? beamcon0_sh[3] :beamcon0_reg[ 3];
wire csynctrue    = displaydual ? beamcon0_sh[2] :beamcon0_reg[ 2];
wire vsynctrue    = displaydual ? beamcon0_sh[1] :beamcon0_reg[ 1];
wire hsynctrue    = displaydual ? beamcon0_sh[0] :beamcon0_reg[ 0];

assign hsyncpol = hsynctrue;
assign vsyncpol = vsynctrue;


// write ERSY bit of bplcon0 register (External ReSYnchronization - genlock)
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		ersy <= 1'b0;
  	else if (reg_address_in[8:1] == BPLCON0[8:1])
  		ersy <= data_in[1];
  end
		
//BPLCON0 register
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		lace <= 1'b0;
  	else if (reg_address_in[8:1]==BPLCON0[8:1])
  		lace <= data_in[2];
  end


// programmable display mode regs
// AMR - shadow copies for RTG
reg [ 8:0] htotal_reg;
reg [ 8:0] hsstrt_reg;
reg [ 8:0] hsstop_reg;
reg [ 8:0] hcenter_reg;
reg [ 8:0] hbstrt_reg; // not correct size, this should have [10:0]
reg [ 8:0] hbstop_reg;
reg [10:0] vtotal_reg;
reg [10:0] vsstrt_reg;
reg [10:0] vsstop_reg;
reg [10:0] vbstrt_reg;
reg [10:0] vbstop_reg;

reg [ 8:0] htotal_sh;
reg [ 8:0] hsstrt_sh;
reg [ 8:0] hsstop_sh;
reg [ 8:0] hcenter_sh;
reg [ 8:0] hbstrt_sh; // not correct size, this should have [10:0]
reg [ 8:0] hbstop_sh;
reg [10:0] vtotal_sh;
reg [10:0] vsstrt_sh;
reg [10:0] vsstop_sh;
reg [10:0] vbstrt_sh;
reg [10:0] vbstop_sh;

// AMR - Register for never-implemented-on-real-hardware Dual mode - we use as line compare
reg [10:0] bplhstrt_reg;

always @ (posedge clk) begin
  if (clk7_en) begin
    if (reset) begin
      htotal_reg  <= #1 HTOTAL_VAL << 1;
      hsstrt_reg  <= #1 HSSTRT_VAL;
      hsstop_reg  <= #1 HSSTOP_VAL;
      hcenter_reg <= #1 HCENTER_VAL;
      hbstrt_reg  <= #1 HBSTRT_VAL;
      hbstop_reg  <= #1 HBSTOP_VAL;
      vtotal_reg  <= #1 displaypal ? VTOTAL_PAL_VAL : VTOTAL_NTSC_VAL;
      vsstrt_reg  <= #1 VSSTRT_VAL;
      vsstop_reg  <= #1 VSSTOP_VAL;
      vbstrt_reg  <= #1 VBSTRT_VAL;
    end else begin
		if(!displaydual || !lpendis) begin  // Normal registers when RTG is off, or lpendis is low
			case (reg_address_in[8:1])
			  BPLHSTRT[8:1]: bplhstrt_reg  <= #1 {data_in[10:0]};
			  HTOTAL [8:1] : htotal_reg  <= #1 {data_in[ 7:0], 1'b0};
			  HSSTRT [8:1] : hsstrt_reg  <= #1 {data_in[ 7:0], 1'b0};
			  HSSTOP [8:1] : hsstop_reg  <= #1 {data_in[ 7:0], 1'b0};
			  HCENTER[8:1] : hcenter_reg <= #1 {data_in[ 7:0], 1'b0};
			  HBSTRT [8:1] : hbstrt_reg  <= #1 {data_in[ 7:0], 1'b0}; // TODO fix this
			  HBSTOP [8:1] : hbstop_reg  <= #1 {data_in[ 7:0], 1'b0};
			  VTOTAL [8:1] : vtotal_reg  <= #1 {data_in[10:0]};
			  VSSTRT [8:1] : vsstrt_reg  <= #1 {data_in[10:0]};
			  VSSTOP [8:1] : vsstop_reg  <= #1 {data_in[10:0]};
			  VBSTRT [8:1] : vbstrt_reg  <= #1 {data_in[10:0]};
			  VBSTOP [8:1] : vbstop_reg  <= #1 {data_in[10:0]};
			  default: ;
			endcase
		end
		if(displaydual && lpendis) begin  // Shadow regs when RTG is on and lpendis is high
			case (reg_address_in[8:1])
			  BPLHSTRT[8:1]: bplhstrt_reg  <= #1 {data_in[10:0]};
			  HTOTAL [8:1] : htotal_sh  <= #1 {data_in[ 7:0], 1'b0};
			  HSSTRT [8:1] : hsstrt_sh  <= #1 {data_in[ 7:0], 1'b0};
			  HSSTOP [8:1] : hsstop_sh  <= #1 {data_in[ 7:0], 1'b0};
			  HCENTER[8:1] : hcenter_sh <= #1 {data_in[ 7:0], 1'b0};
			  HBSTRT [8:1] : hbstrt_sh  <= #1 {data_in[ 7:0], 1'b0}; // TODO fix this
			  HBSTOP [8:1] : hbstop_sh  <= #1 {data_in[ 7:0], 1'b0};
			  VTOTAL [8:1] : vtotal_sh  <= #1 {data_in[10:0]};
			  VSSTRT [8:1] : vsstrt_sh  <= #1 {data_in[10:0]};
			  VSSTOP [8:1] : vsstop_sh  <= #1 {data_in[10:0]};
			  VBSTRT [8:1] : vbstrt_sh  <= #1 {data_in[10:0]};
			  VBSTOP [8:1] : vbstop_sh  <= #1 {data_in[10:0]};
			  default: ;
			endcase
		end
    end
  end
end

// programmable display mode values
wire [ 8:0] htotal;   // line length of 227 CCKs in PAL mode (NTSC line length of 227.5 CCKs is not supported)
wire [ 8:0] hsstrt;
wire [ 8:0] hsstop;
wire [ 8:0] hcenter;
wire [ 8:0] hbstrt;
wire [ 8:0] hbstop;
wire [10:0] vtotal;
wire [10:0] vsstrt;
wire [10:0] vsstop;
wire [10:0] vbstrt;
wire [10:0] vbstop;

assign htotal  =             varbeamen ? (displaydual ? htotal_sh : htotal_reg)  : HTOTAL_VAL << 1;
assign hsstrt  = varhsyen && varbeamen ? (displaydual ? hsstrt_sh : hsstrt_reg)  : HSSTRT_VAL;
assign hsstop  = varhsyen && varbeamen ? (displaydual ? hsstop_sh : hsstop_reg)  : HSSTOP_VAL;
assign hcenter = varhsyen && varbeamen ? (displaydual ? hcenter_sh : hcenter_reg) : HCENTER_VAL;
assign hbstrt  =             varbeamen ? (displaydual ? hbstrt_sh : hbstrt_reg)  : HBSTRT_VAL;
assign hbstop  =             varbeamen ? (displaydual ? hbstop_sh : hbstop_reg)  : HBSTOP_VAL;
assign vtotal  =             varbeamen ? (displaydual ? vtotal_sh : vtotal_reg)  : displaypal ? VTOTAL_PAL_VAL : VTOTAL_NTSC_VAL;
assign vsstrt  = varvsyen && varbeamen ? (displaydual ? vsstrt_sh : vsstrt_reg)  : VSSTRT_VAL;
assign vsstop  = varvsyen && varbeamen ? (displaydual ? vsstop_sh : vsstop_reg)  : VSSTOP_VAL;
assign vbstrt  = varvben  && varbeamen ? (displaydual ? vbstrt_sh : vbstrt_reg)  : (track_vsync && lace) ? vtotal : VBSTRT_VAL;
assign vbstop  = varvben  && varbeamen ? (displaydual ? vbstop_sh : vbstop_reg)  : displaypal ? VBSTOP_PAL_VAL : VBSTOP_NTSC_VAL;

assign htotal_out    = htotal;
assign harddis_out   = harddis || varbeamen || varvben;
assign varbeamen_out = varbeamen;


//--------------------------------------------------------------------------------------//
//                                                                                      //
//   HORIZONTAL BEAM COUNTER                                                            //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//generate start of line signal
always @(posedge clk)
  if (clk7_en) begin
  	if (hpos[8:0]=={htotal[8:1],1'b0})
  		end_of_line <= 1'b1;
  	else
  		end_of_line <= 1'b0;
  end

reg [8:1] hpos_r;

// horizontal beamcounter
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==VHPOSW[8:1])
  		hpos_r[8:1] <= data_in[7:0]; 
  	else if (end_of_line)
  		hpos_r[8:1] <= 0;
  	else if (cck && (~ersy || |hpos[8:1]))
  		hpos_r[8:1] <= hpos[8:1] + 1'b1;
  end

assign hpos = {hpos_r,cck};

//long line signal (not used, only for better NTSC compatibility)
always @(posedge clk)
  if (clk7_en) begin
  	if (end_of_line)
  		if (displaypal || (loldis && varbeamen))
  			long_line <= 1'b0;
  		else if (!(loldis && varbeamen))
  			long_line <= ~long_line;
  end

//--------------------------------------------------------------------------------------//
//                                                                                      //
//   VERTICAL BEAM COUNTER                                                              //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//vertical counter increase
always @(posedge clk)
  if (clk7_en) begin
  	if (hpos==2) //actual chipset works in this way
  		vpos_inc <= 1'b1;
  	else
  		vpos_inc <= 1'b0;
  end

//external signals assigment
assign eol = vpos_inc;

//vertical position counter
//vpos changes after hpos equals 3
always @(posedge clk)
  if (clk7_en) begin
  	if (reg_address_in[8:1]==VPOSW[8:1])
  		vpos[10:8] <= data_in[2:0];
  	else if (reg_address_in[8:1]==VHPOSW[8:1])
  		vpos[7:0] <= data_in[15:8];
  	else if (vpos_inc)
  		if (last_line)
  			vpos <= 0;
  		else
  			vpos <= vpos + 1'b1;
  end

// long_frame - long frame signal used in interlaced mode
always @(posedge clk)
  if (clk7_en) begin
  	if (reset)
  		long_frame_r <= 1'b1;
  	else if (reg_address_in[8:1]==VPOSW[8:1])
  		long_frame_r <= data_in[15];
  	else if (end_of_frame && lace) // interlace
  		long_frame_r <= ~long_frame;
  end

 assign long_frame = displaydual ? 1'b0 : long_frame_r;  // Don't want long frames in RTG mode
  
//maximum position of vertical beam position
assign vpos_equ_vtotal = vpos==vtotal ? 1'b1 : 1'b0;

//extra line in interlaced mode	
always @(posedge clk)
  if (clk7_en) begin
  	if (vpos_inc)
  		if (long_frame && vpos_equ_vtotal)
  			extra_line <= 1'b1;
  		else
  			extra_line <= 1'b0;
  end

//in non-interlaced display the last line is equal to vtotal or vtotal+1 (depends on long_frame)
//in interlaced mode every second frame is vtotal+1 long
assign last_line = long_frame ? extra_line : vpos_equ_vtotal;

//generate end of frame signal
assign end_of_frame = vpos_inc & last_line;

//external signal assigment
assign eof = end_of_frame;

always @(posedge clk)
  if (clk7_en) begin
  	vbl_int <= hpos==8 && vpos==(a1k ? 1 : 0) ? 1'b1 : 1'b0; // OCS AGNUS CHIPS 8361/8367 assert vbl int in line #1
  end

//--------------------------------------------------------------------------------------//
//                                                                                      //
//  VIDEO SYNC GENERATOR                                                                //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//horizontal sync
always @(posedge clk)
  if (clk7_en) begin
  	if (hpos==hsstrt)//start of sync pulse (front porch = 1.69us)
  		_hsync <= 1'b0;
  	else if (hpos==hsstop)//end of sync pulse (sync pulse = 4.65us)
  		_hsync <= 1'b1;
  end

//vertical sync and vertical blanking
always @(posedge clk)
  if (clk7_en) begin
  	if ((vpos==vsstrt+1 && hpos==hsstrt && long_frame) || (vpos==vsstrt && hpos==hcenter && !long_frame))
  		_vsync <= 1'b0;
  	else if ((vpos==vsstop && hpos==hcenter && long_frame) || (vpos==vsstop && hpos==hsstrt && !long_frame))
  		_vsync <= 1'b1;
  end

//apparently generating csync from vsync alligned with leading edge of hsync results in malfunction of the AD724 CVBS/S-Video encoder (no colour in interlaced mode)
//to overcome this limitation semi (only present before horizontal sync pulses) vertical sync serration pulses are inserted into csync
always @(posedge clk)//sync
  if (clk7_en) begin
  	if (hpos==hsstrt-(hsstop-hsstrt))//start of sync pulse (front porch = 1.69us)
  		vser <= 1'b1;
  	else if (hpos==hsstrt)//end of sync pulse	(sync pulse = 4.65us)
  		vser <= 1'b0;
  end

//composite sync
assign _csync = (_hsync & _vsync) | vser; //composite sync with serration pulses

//--------------------------------------------------------------------------------------//
//                                                                                      //
//  VIDEO BLANKING GENERATOR                                                            //
//                                                                                      //
//--------------------------------------------------------------------------------------//


//vertical blanking
reg vbl_reg;
always @ (posedge clk) begin
  if (reset)
    vbl_reg <= #1 1'b0;
  else if (vpos == vbstrt)
    vbl_reg <= #1 1'b1;
  else if (vpos == vbstop+1)
    vbl_reg <= #1 1'b0;
end

// assign vbl = (vpos <= vbstop) ? 1'b1 : 1'b0;
assign vbl = vbl_reg; // TODO

//vertical blanking end (last line)
assign vblend = vpos==vbstop ? 1'b1 : 1'b0;

// line compare:
assign rtg_linecompare = vpos==bplhstrt_reg ? 1'b1 : 1'b0;

// We don't want to delay hblank by 12 7Mhz clks in RTG mode
// Rather than use two lots of comaparators, delay the chipset
// blank signal with a shift register.
reg [11:0] hblank_delay;
reg hblank_tmp;
//composite display blanking		
always @(posedge clk)
begin
	if (clk7_en) begin
		blank<=displaydual | hblank_delay[11]; // Blank while RTG is enabled
		hblank_delay<={hblank_delay[10:0],hblank_tmp};
		if (hpos==hbstrt) begin
			hblank_tmp<=1'b1;
			hblank_out<=1'b1;
		end
		else if (hpos==hbstop) begin
			hblank_out<=1'b0;	
			hblank_tmp<=vbl;
		end
//		if (hpos==hbstrt + 8'd12) //start of blanking (active line=51.88us)
//			blank <= 1'b1;
//		else if (hpos==hbstop + 8'd12) begin//end of blanking (back porch=5.78us)
			// TODO 		blank <= vbl_reg;
//			blank <= vbl;
//		end
	end
end

// Abuse the DUAL bit in BEAMCON0 to enable the RTG mode
assign rtg_ena = displaydual;
endmodule

