/*******************************************/
/* Virtual toplevel for Minimig, based on   */
/* minimig_mist_top.v                       */
/*                                          */
/* 2012-2015, rok.krajnc@gmail.com          */
/* 2020-2021, Alastair M. Robinson          */
/********************************************/

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that they will
// be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>

// board type define
`define MINIMIG_VIRTUAL
`define MINIMIG_USB
//`define HOSTONLY

`include "minimig_defines.vh"

`default_nettype none

module minimig_virtual_top	#(
	parameter hostonly=0,
	parameter debug = 0,
	parameter spimux = 0,
	parameter haveiec = 0,
	parameter havereconfig = 0,
	parameter havertg = 1,
	parameter haveaudio = 1,
	parameter havec2p = 1,
	parameter havespirtc = 0,
	parameter ram_64meg = 0,
	parameter vga_width = 6,
	parameter havecart = 1,
	parameter haveaga = 1
)
(
  // JTAG inputs
  output sys_tdo,
  input sys_tdi,
  input sys_tck,
  input sys_tms,
  // clock inputs
  input wire            CLK_IN,
  output wire           CLK_114,
  output wire           CLK_28,
  output wire           PLL_LOCKED,
  input wire            RESET_N,
  
  // Button inputs
  input						MENU_BUTTON,
  
  // LED outputs
  output wire           LED_POWER,  // LED green
  output wire           LED_DISK,   // LED red
  output wire [1:0]     LED_USB,
  
  // UART
  output wire           CTRL_TX,    // UART Transmitter
  input wire            CTRL_RX,    // UART Receiver
  output wire           AMIGA_TX,    // UART Transmitter
  input wire            AMIGA_RX,    // UART Receiver
  
  // VGA
  output reg            VGA_HS,     // VGA H_SYNC
  output reg            VGA_VS,     // VGA V_SYNC
  output reg [  vga_width-1:0] VGA_R,      // VGA Red[5:0]
  output reg [  vga_width-1:0] VGA_G,      // VGA Green[5:0]
  output reg [  vga_width-1:0] VGA_B,      // VGA Blue[5:0]
  output reg            VGA_STROBE,
  output reg            VGA_DE,
  
  // DVI
  output reg            DVI_HS,     // VGA H_SYNC
  output reg            DVI_VS,     // VGA V_SYNC
  output reg [  7:0]    DVI_R,      // VGA Red[5:0]
  output reg [  7:0]    DVI_G,      // VGA Green[5:0]
  output reg [  7:0]    DVI_B,      // VGA Blue[5:0]
  output                DVI_STROBE,
  output reg            DVI_DE,
  
  // SDRAM
  inout  wire [ 16-1:0] SDRAM_DQ,   // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A,    // SDRAM Address bus 13 Bits
  output wire           SDRAM_DQML, // SDRAM Low-byte Data Mask
  output wire           SDRAM_DQMH, // SDRAM High-byte Data Mask
  output wire           SDRAM_nWE,  // SDRAM Write Enable
  output wire           SDRAM_nCAS, // SDRAM Column Address Strobe
  output wire           SDRAM_nRAS, // SDRAM Row Address Strobe
  output wire           SDRAM_nCS,  // SDRAM Chip Select
  output wire [  2-1:0] SDRAM_BA,   // SDRAM Bank Address
  output wire           SDRAM_CLK,  // SDRAM Clock
  output wire           SDRAM_CKE,  // SDRAM Clock Enable
  
  // MINIMIG specific
  output wire[23:0]     AUDIO_L,    // sigma-delta DAC output left
  output wire[23:0]     AUDIO_R,    // sigma-delta DAC output right

  // Keyboard / Mouse
  input                 PS2_DAT_I,      // PS2 Keyboard Data
  input                 PS2_CLK_I,      // PS2 Keyboard Clock
  input                 PS2_MDAT_I,     // PS2 Mouse Data
  input                 PS2_MCLK_I,     // PS2 Mouse Clock
  output                PS2_DAT_O,      // PS2 Keyboard Data
  output                PS2_CLK_O,      // PS2 Keyboard Clock
  output                PS2_MDAT_O,     // PS2 Mouse Data
  output                PS2_MCLK_O,     // PS2 Mouse Clock

  // Potential Amiga keyboard from docking station
  input						AMIGA_RESET_N,
  input						[7:0] AMIGA_KEY,
  input						AMIGA_KEY_STB,
  input			[63:0]	C64_KEYS,
  // Joystick
  input       [  7-1:0] JOYA,         // joystick port A
  input       [  7-1:0] JOYB,         // joystick port B
  input       [  7-1:0] JOYC,         // joystick port A
  input       [  7-1:0] JOYD,         // joystick port B
  
  // SPI 
  input wire            SD_MISO,     // inout
  output wire           SD_MOSI,
  output wire           SD_CLK,
  output wire           SD_CS,
  input wire            SD_ACK,
  output wire           RTC_CS,
  
  inout wire [1:0]      usb_dp,
  inout wire [1:0]      usb_dn,
  output wire				RECONFIG,
  output wire				IECSERIAL,
  input wire			FREEZE
);

////////////////////////////////////////
// internal signals                   //
////////////////////////////////////////

// clock
wire           clk_sdram;
wire           clk7_en;
wire           clk7n_en;
wire           c1;
wire           c3;
wire           cck;
wire [ 10-1:0] eclk;

// reset
wire           pll_rst;
wire           sdctl_rst;
wire           rst_50;
wire           rst_minimig;

// ctrl
wire           rom_status;
wire           ram_status;
wire           reg_status;

// tg68
wire           tg68_rst;
reg            tg68_rst_d;
reg            tg68_rst_sync;
wire [ 16-1:0] tg68_dat_in;
wire [ 16-1:0] tg68_dat_in2;
wire [ 16-1:0] tg68_dat_out;
wire [ 16-1:0] tg68_dat_out2;
wire [ 32-1:0] tg68_adr;
wire [  3-1:0] tg68_IPL;
wire           tg68_dtack;
wire           tg68_as;
wire           tg68_uds;
wire           tg68_lds;
wire           tg68_uds2;
wire           tg68_lds2;
wire           tg68_rw;
wire           tg68_ena7RD;
wire           tg68_ena7WR;
wire           tg68_ena28;
wire [ 16-1:0] tg68_cout;
wire [ 16-1:0] tg68_cin;
wire           tg68_cpuena;
wire [  4-1:0] cpu_config;
wire [4:0]     board_configured;
wire           turbochipram;
wire           turbokick;
wire [1:0]     slow_config;
wire           aga;
wire           cache_inhibit;
wire           cacheline_clr;
wire [ 32-1:0] tg68_cad;
wire [  4-1:0] tg68_cpustate;
wire           tg68_nrst_out;
//wire           tg68_cdma;
wire           tg68_clds;
wire           tg68_cuds;
wire [  4-1:0] tg68_CACR_out;
wire [ 32-1:0] tg68_VBR_out;
wire           tg68_ovr;
wire           tg68_fast_rd;

// minimig
wire           led;
wire [ 16-1:0] ram_data;      // sram data bus
wire [ 16-1:0] ram_data2;     // sram data bus 2nd word
wire [ 16-1:0] ramdata_in;    // sram data bus in
wire [ 48-1:0] chip48;        // big chip read
wire [ 23-1:1] ram_address;   // sram address bus
wire           _ram_bhe;      // sram upper byte select
wire           _ram_ble;      // sram lower byte select
wire           _ram_bhe2;     // sram upper byte select 2nd word
wire           _ram_ble2;     // sram lower byte select 2nd word
wire           _ram_we;       // sram write enable
wire           _ram_oe;       // sram output enable
wire           _15khz;        // scandoubler disable
wire           invertsync;    // helps some monitors with the scandoubled signal
wire           sdo;           // SPI data output
wire           vs;
wire           hs;
wire           cs;
wire [  8-1:0] red_amiga;
wire [  8-1:0] green_amiga;
wire [  8-1:0] blue_amiga;
wire				hsyncpol;
wire				vsyncpol;

// sdram
wire           reset_out;
wire [  4-1:0] sdram_cs;
wire [  2-1:0] sdram_dqm;
wire [  2-1:0] sdram_ba;

// mist
wire           user_io_sdo;
wire           minimig_sdo;
wire [   6:0] joysticka;
wire [   6:0] joystickb;
wire [   6:0] joyc;
wire [   6:0] joyd;
wire [   6:0] joykeys;

// UART
wire minimig_rxd;
wire minimig_txd;
wire debug_rxd;
wire debug_txd;

// Realtime clock
wire [63:0] rtc;

////////////////////////////////////////
// toplevel assignments               //
////////////////////////////////////////

// SDRAM
assign SDRAM_CKE        = 1'b1;
assign SDRAM_CLK        = clk_sdram;
assign SDRAM_nCS        = sdram_cs[0];
assign SDRAM_DQML       = sdram_dqm[0];
assign SDRAM_DQMH       = sdram_dqm[1];
assign SDRAM_BA         = sdram_ba;

// reset
assign pll_rst          = 1'b0;
assign sdctl_rst        = PLL_LOCKED & RESET_N;


// RTG support...

wire rtg_ena;	// RTG screen on/off

wire hblank_amiga;
wire vblank_amiga;
wire blank_amiga;
reg rtg_vblank;
wire rtg_blank;
reg rtg_blank_d;
reg rtg_blank_d2;
reg rtg_blank_d3;
reg [6:0] rtg_vbcounter;	// Vvbco counter
wire [6:0] rtg_vbend; // Size of VBlank area

// RTG register interface
wire [10:0] rtg_reg_addr;
wire [15:0] rtg_reg_d;
wire rtg_reg_wr;

// RTG to RAM interface
wire [25:0] rtg_fetch_addr;
wire rtg_ramreq;
wire [15:0] rtg_fromram;
wire rtg_fill;
wire rtg_rampri;
wire rtg_ramack;

wire [7:0] rtg_r;	// RTG video data
wire [7:0] rtg_g;
wire [7:0] rtg_b;

wire rtg_pixel;

wire selcsync;
wire rtg_linecompare;
wire rtg_ena_mm;
wire rtg_de;

rtg_video rtg (
	.clk_114(CLK_114),
	.clk_28(CLK_28),
	.clk_vid(CLK_114),
	.reset_n(RESET_N),
	.rtg_ena(rtg_ena),
	.rtg_linecompare(rtg_linecompare),
	.reg_addr(rtg_reg_addr),
	.reg_wr(rtg_reg_wr),
	.reg_d(rtg_reg_d),

	.fetch_addr(rtg_fetch_addr),
	.fetch_req(rtg_ramreq),
	.fetch_pri(rtg_rampri),
	.fetch_d(rtg_fromram),
	.fetch_ack(rtg_ramack),
	.fetch_fill(rtg_fill),
		
	.amiga_r(red_amiga),
	.amiga_g(green_amiga),
	.amiga_b(blue_amiga),
	.amiga_hb(hblank_amiga),
	.amiga_vb(vblank_amiga),
	.amiga_hs(hs),
	.amiga_blank(blank_amiga),

	.red(rtg_r),
	.green(rtg_g),
	.blue(rtg_b),
	.pixel(rtg_pixel),
	.de(rtg_de)
);


// Overlaying of OSD graphics

wire osd_window;
wire osd_pixel;
wire [1:0] osd_r;
wire [1:0] osd_g;
wire [1:0] osd_b;
assign osd_r = osd_pixel ? 2'b11 : 2'b00;
assign osd_g = osd_pixel ? 2'b11 : 2'b00;
assign osd_b = osd_pixel ? 2'b11 : 2'b10;
reg       VGA_CS_INT;
reg       VGA_VS_INT;
reg       VGA_HS_INT;
wire [7:0] VGA_R_INT = osd_window ? {osd_r,rtg_r[7:2]} : rtg_r;
wire [7:0] VGA_G_INT = osd_window ? {osd_g,rtg_g[7:2]} : rtg_g;
wire [7:0] VGA_B_INT = osd_window ? {osd_b,rtg_b[7:2]} : rtg_b;

always @(posedge CLK_28) begin
	VGA_CS_INT = cs;
	VGA_HS_INT = hs;
	VGA_VS_INT = vs;
end

// Audio for CD images
wire aud_int;
reg [15:0] aud_left;
reg [15:0] aud_right;    // sigma-delta DAC output right

reg aud_tick;
reg aud_tick_d;
reg aud_next;

wire [25:0] aud_addr;
wire [15:0] aud_sample;

wire aud_ramreq;
wire aud_ramack;
wire aud_rampri;
wire [15:0] aud_fromram;
wire aud_fill;
wire aud_ena_host;
wire aud_ena_cpu;
wire aud_clear;

wire [25:0] aud_ramaddr;
assign aud_ramaddr[15:0]=aud_addr[15:0];
assign aud_ramaddr[25:16]=10'b0001101111;  // 0x6f0000 in SDRAM, 0x040000 to host, 0xec0000 to Amiga

wire [25:0] aud_baseaddr=26'b0;

reg [9:0] aud_ctr;
always @(posedge CLK_28) begin
	aud_ctr<=aud_ctr+1;
	if (aud_ctr==10'd642) begin
		aud_tick<=1'b1;
		aud_ctr<=10'b0;
	end
	else
		aud_tick<=1'b0;
end

//  tick:   0 0 1 1 1 1 0 0
//  tick_d: 0 0 0 1 1 1 1 0
// tick^tick_d  1 0 0 0 1 0 
always @(posedge CLK_114) begin
	aud_tick_d<=aud_tick;
	aud_next<=aud_tick ^ aud_tick_d;
	if (aud_tick_d==1)
		aud_left<={aud_sample[7:0],aud_sample[15:8]};
	else
		aud_right<={aud_sample[7:0],aud_sample[15:8]};
end	

// We can use the same type of FIFO as we use for video.
VideoStream #(.fifodepth(9),.burstdepth(3),.signalwidth(16)) myaudiostream
(
	.clk(CLK_114),
	.reset_n(aud_ena_host | aud_ena_cpu), // !aud_clear),
	.enable(aud_ena_host | aud_ena_cpu),
	.baseaddr(aud_baseaddr),
	// SDRAM interface
	.a(aud_addr),
	.req(aud_ramreq),
	.ack(aud_ramack),
	.pri(aud_rampri),
	.d(aud_fromram),
	.fill(aud_fill & (haveaudio ? 1'b1 : 1'b0)),
	// Display interface
	.rdreq(aud_next & (haveaudio ? 1'b1 : 1'b0)),
	.q(aud_sample)
);

wire clk_56;

//// amiga clocks ////
amiga_clk amiga_clk (
  .rst          (1'b0             ), // async reset input
  .clk_in       (CLK_IN           ), // input clock     ( 27.000000MHz)
  .clk_114      (CLK_114          ), // output clock c0 (114.750000MHz)
  .clk_sdram    (clk_sdram        ), // output clock c2 (114.750000MHz, -146.25 deg)
  .clk_28       (CLK_28           ), // output clock c1 ( 28.687500MHz)
  .clk_56       (clk_56           ),
  .clk7_en      (clk7_en          ), // output clock 7 enable (on 28MHz clock domain)
  .clk7n_en     (clk7n_en         ), // 7MHz negedge output clock enable (on 28MHz clock domain)
  .c1           (c1               ), // clk28m clock domain signal synchronous with clk signal
  .c3           (c3               ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
  .cck          (cck              ), // colour clock output (3.54 MHz)
  .eclk         (eclk             ), // 0.709379 MHz clock enable output (clk domain pulse)
  .ntsc         (1'b0             ),
  .locked       (PLL_LOCKED       )  // pll locked output
);

wire amigahost_req;
wire amigahost_ack;
wire [15:0] amigahost_q;

//// TG68K main CPU ////
`ifdef HOSTONLY
assign tg68_cpustate=2'b01;
assign tg68_nrst_out=1'b1;
`else

always @(posedge CLK_114) begin
	tg68_rst_d<=tg68_rst;
	tg68_rst_sync<=tg68_rst_d;
end

TG68K #(.havertg(havertg),
			.haveaudio(haveaudio),
			.havec2p(havec2p),
			.havecart(havecart)
		) tg68k (
  .clk          (CLK_114          ),
  .reset        (tg68_rst_sync    ),
  .clkena_in    (tg68_ena28       ),
  .IPL          (tg68_IPL         ),
  .dtack        (tg68_dtack       ),
  .freeze       (FREEZE           ),
  .vpa          (1'b1             ),
  .ein          (1'b1             ),
  .addr         (tg68_adr         ),
  .data_read    (tg68_dat_in      ),
  .data_read2   (tg68_dat_in2     ),
  .data_write   (tg68_dat_out     ),
  .data_write2  (tg68_dat_out2    ),
  .fast_rd      (tg68_fast_rd     ),
  .as           (tg68_as          ),
  .uds          (tg68_uds         ),
  .lds          (tg68_lds         ),
  .uds2         (tg68_uds2        ),
  .lds2         (tg68_lds2        ),
  .rw           (tg68_rw          ),
  .vma          (                 ),
  .wrd          (                 ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),
  .fromram      (tg68_cout        ),
  .toram        (tg68_cin         ),
  .ramready     (tg68_cpuena      ),
  .cpu          (cpu_config[1:0]  ),
  .turbochipram (turbochipram     ),
  .turbokick    (turbokick        ),
  .slow_config  (slow_config      ),
  .aga          (aga              ),
  .cache_inhibit(cache_inhibit    ),
  .cacheline_clr(cacheline_clr    ),
  .ziiram_active(board_configured[0]),
  .ziiiram_active(board_configured[1]),
  .ziiiram2_active(board_configured[2]),
  .ziiiram3_active(board_configured[3]),
//  .fastramcfg   ({&memcfg[5:4],memcfg[5:4]}),
  .eth_en       (1'b1), // TODO
  .sel_eth      (),
  .frometh      (16'd0),
  .ethready     (1'b0),
  .ramaddr      (tg68_cad         ),
  .cpustate     (tg68_cpustate    ),
  .nResetOut    (tg68_nrst_out    ),
  .ramlds       (tg68_clds        ),
  .ramuds       (tg68_cuds        ),
  .CACR_out     (tg68_CACR_out    ),
  .VBR_out      (tg68_VBR_out     ),
  // RTG signals
  .rtg_reg_addr(rtg_reg_addr),
  .rtg_reg_d(rtg_reg_d),
  .rtg_reg_wr(rtg_reg_wr),

	.audio_buf(aud_addr[15]),
	.audio_ena(aud_ena_cpu),
	.audio_int(aud_int),
	// Amiga to host signals
	.host_req(amigahost_req),
	.host_ack(amigahost_ack),
	.host_q(amigahost_q)
);

`endif

wire [ 32-1:0] hostRD;
wire [ 32-1:0] hostWR;
wire [ 32-1:2] hostaddr;
wire [  3-1:0] hostState;
wire [3:0]     hostbytesel;
wire  [ 16-1:0] host_ramdata;
wire           host_ramack;
wire           host_ramreq;
wire  [ 16-1:0] host_hwdata;
wire           host_hwack;
wire           host_hwreq;
wire           host_we;
wire           hostreq;
wire           hostack;
wire           hostce;

//sdram sdram (
sdram_ctrl sdram (
  .cache_rst    (tg68_rst_sync    ),
  .cache_inhibit(cache_inhibit    ),
  .cacheline_clr(cacheline_clr    ),
  .cpu_cache_ctrl (tg68_CACR_out    ),
  .sdata        (SDRAM_DQ         ),
  .sdaddr       (SDRAM_A[12:0]    ),
  .dqm          (sdram_dqm        ),
  .sd_cs        (sdram_cs         ),
  .ba           (sdram_ba         ),
  .sd_we        (SDRAM_nWE        ),
  .sd_ras       (SDRAM_nRAS       ),
  .sd_cas       (SDRAM_nCAS       ),
  .sysclk       (CLK_114          ),
  .reset_in     (sdctl_rst        ),
  
  .hostWR       (hostWR           ),
  .hostAddr     (hostaddr         ),
  .hostwe       (host_we           ),
  .hostce       (host_ramreq      ),
  .hostbytesel  (hostbytesel      ),
  .hostRD       (host_ramdata     ),
  .hostena      (host_ramack      ),

  .cpuWR        (tg68_cin         ),
  .cpuAddr      (tg68_cad[25:1]   ),
  .cpuU         (tg68_cuds        ),
  .cpuL         (tg68_clds        ),
  .cpustate     (tg68_cpustate    ),
  .cpuRD        (tg68_cout        ),
  .cpuena       (tg68_cpuena      ),

//  .cpu_dma      (tg68_cdma        ),
  .chipWR       (ram_data         ),
  .chipWR2      (tg68_dat_out2    ),
  .chipAddr     ({1'b0, ram_address[22:1]}),
  .chipU        (_ram_bhe         ),
  .chipL        (_ram_ble         ),
  .chipU2       (_ram_bhe2        ),
  .chipL2       (_ram_ble2        ),
  .chipRW       (_ram_we          ),
  .chip_dma     (_ram_oe          ),
  .clk7_en      (clk7_en          ),
  .chipRD       (ramdata_in       ),
  .chip48       (chip48           ),

  .rtgAddr      (rtg_fetch_addr   ),
  .rtgce        (rtg_ramreq       ),
  .rtgfill      (rtg_fill         ),
  .rtgack       (rtg_ramack       ),
  .rtgpri       (rtg_rampri       ),
  .rtgRd        (rtg_fromram      ),

  .audAddr      (aud_ramaddr      ),
  .audce        (aud_ramreq       ),
  .audfill      (aud_fill         ),
  .audack       (aud_ramack       ),
  .audRd        (aud_fromram      ),

  .reset_out    (reset_out        ),
  .enaWRreg     (tg68_ena28       ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      )
);


// multiplex spi_do, drive it from user_io if that's selected, drive
// it from minimig if it's selected and leave it open else (also
// to be able to monitor sd card data directly)

wire [8-1 : 0] SPI_CS;
wire SPI_DO;
wire SPI_DI;
wire SPI_SCK;
wire SPI_SS;
wire SPI_SS2;
wire SPI_SS3;
wire SPI_SS4;
wire CONF_DATA0;

//assign SPI_DO = (CONF_DATA0 == 1'b0)?user_io_sdo:
//    (((SPI_SS2 == 1'b0)|| (SPI_SS3 == 1'b0))?minimig_sdo:1'bZ);

assign CONF_DATA0 = SPI_CS[3];
assign SD_CLK = SPI_SCK;
assign SD_CS = SPI_CS[1];
assign SD_MOSI = SPI_DI;
assign SPI_SS4 = SPI_CS[6];
assign SPI_SS3 = SPI_CS[5];
assign SPI_SS2 = SPI_CS[4];
assign RTC_CS = SPI_CS[7];

// Keyboard-related signals

wire	[15:0] c64_translated_key;
wire	c64_translated_key_stb;
reg	[7:0] kbd_mouse_data;
wire	kbd_reset_n;
reg	kbd_mouse_stb;
reg	kbd_mouse_stb_r;

reg           mouse_idx;
reg [  2-1:0] kbd_mouse_type;
reg kms_level;
reg [  3-1:0] mouse0_buttons;
reg [  3-1:0] mouse1_buttons;


localparam capturewidth = 18;
wire [capturewidth-1:0] capture;
wire [capturewidth-1:0] capout;
wire cap_upd;

assign capture[0] = kbd_mouse_stb;
assign capture[8:1] = kbd_mouse_data;
assign capture[10:9] = kbd_mouse_type;
assign capture[13:11] = mouse0_buttons;
assign capture[16:14] = mouse1_buttons;
assign capture[17] = kms_level;

//jcapture #(.capturewidth(capturewidth),.triggerwidth(capturewidth)) cap_inst (
//	.clk(CLK_114),
//	.reset_n(reset_out),
//	.stb(1'b1),
//	.d(capture),
//	.q(capout),
//	.update(cap_upd)
//);


assign kbd_reset_n = AMIGA_RESET_N;

always @(posedge CLK_28) begin
	kbd_mouse_stb <= kbd_mouse_stb_r;
	kms_level <= kms_level ^ kbd_mouse_stb;
end

always @(posedge CLK_114) begin

	if(kbd_mouse_stb) begin
		kbd_mouse_stb_r<=1'b0;
	end

	if(c64_translated_key_stb || AMIGA_KEY_STB) begin
		kbd_mouse_data <= c64_translated_key_stb ? c64_translated_key[7:0] : AMIGA_KEY;
		kbd_mouse_type <= c64_translated_key_stb ? c64_translated_key[15:14] : 2'b10;
		mouse0_buttons <= c64_translated_key_stb ? c64_translated_key[10:8] : 3'b000;
		mouse1_buttons <= c64_translated_key_stb ? c64_translated_key[13:11] : 3'b000;
		kbd_mouse_stb_r<=1'b1;
	end

//	if(cap_upd) begin
//		kbd_mouse_stb_r <= 1'b1;
//		kbd_mouse_data <= capout[8:1];
//		kbd_mouse_type <= capout[10:9];
//		mouse0_buttons <= capout[13:11];
//		mouse1_buttons <= capout[16:14];
//		mouse_idx <= capout[0];
//	end

end

//// minimig top ////
`ifdef HOSTONLY
assign SPI_DO=1'b1;
assign _ram_oe=1'b1;
assign _ram_we=1'b1;
`else

minimig #(.useaga(haveaga),.wide_hblank(1'b1)) minimig
(
	// JTAG
	.sys_tdo(sys_tdo),
	.sys_tdi(sys_tdi),
	.sys_tck(sys_tck),
	.sys_tms(sys_tms),
	//m68k pins
	.cpu_address  (tg68_adr[23:1]   ), // M68K address bus
	.cpu_data     (tg68_dat_in      ), // M68K data bus
	.cpu_data2    (tg68_dat_in2     ), // M68K data bus 2nd word
	.cpudata_in   (tg68_dat_out     ), // M68K data in
	._cpu_ipl     (tg68_IPL         ), // M68K interrupt request
	.fast_rd      (tg68_fast_rd     ), // Fast read for Gayle IDE cycles
	._cpu_as      (tg68_as          ), // M68K address strobe
	._cpu_uds     (tg68_uds         ), // M68K upper data strobe
	._cpu_lds     (tg68_lds         ), // M68K lower data strobe
	._cpu_uds2    (tg68_uds2        ), // M68K upper data strobe 2nd word
	._cpu_lds2    (tg68_lds2        ), // M68K lower data strobe 2nd word
	.cpu_r_w      (tg68_rw          ), // M68K read / write
	._cpu_dtack   (tg68_dtack       ), // M68K data acknowledge
	._cpu_reset   (tg68_rst         ), // M68K reset
	._cpu_reset_in(tg68_nrst_out    ), // M68K reset out
	.cpu_vbr      (tg68_VBR_out     ), // M68K VBR
	.ovr          (tg68_ovr         ), // NMI override address decoding
	//sram pins
	.ram_data     (ram_data         ), // SRAM data bus
	.ramdata_in   (ramdata_in       ), // SRAM data bus in
	.ram_address  (ram_address[22:1]), // SRAM address bus
	._ram_bhe     (_ram_bhe         ), // SRAM upper byte select
	._ram_ble     (_ram_ble         ), // SRAM lower byte select
	._ram_bhe2    (_ram_bhe2        ), // SRAM upper byte select 2nd word
	._ram_ble2    (_ram_ble2        ), // SRAM lower byte select 2nd word
	._ram_we      (_ram_we          ), // SRAM write enable
	._ram_oe      (_ram_oe          ), // SRAM output enable
	.chip48       (chip48           ), // big chipram read
	//system  pins
	.rst_ext      (!reset_out       ), // reset from ctrl block
	.rst_out      (                 ), // minimig reset status
	.clk          (CLK_28           ), // output clock c1 ( 28.687500MHz)
	.clk7_en      (clk7_en          ), // 7MHz clock enable
	.clk7n_en     (clk7n_en         ), // 7MHz negedge clock enable
	.c1           (c1               ), // clk28m clock domain signal synchronous with clk signal
	.c3           (c3               ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck          (cck              ), // colour clock output (3.54 MHz)
	.eclk         (eclk             ), // 0.709379 MHz clock enable output (clk domain pulse)
	//rs232 pins
	.rxd          (AMIGA_RX         ),  // RS232 receive
	.txd          (AMIGA_TX         ),  // RS232 send
	.cts          (1'b0             ),  // RS232 clear to send
	.rts          (                 ),  // RS232 request to send
	.midi_rx      (1'b1             ),
	//I/O
	._joy1        (joysticka        ),  // joystick 1 [fire7:fire,up,down,left,right] (default mouse port)
	._joy2        (joystickb        ),  // joystick 2 [fire7:fire,up,down,left,right] (default joystick port)
	._joy3        (JOYC             ),  // joystick 3 [fire7:fire,up,down,left,right]
	._joy4        (JOYD             ),  // joystick 4 [fire7:fire,up,down,left,right]
	//  .mouse_btn    (mouse_buttons    ),  // mouse buttons
	.mouse0_btn   (mouse0_buttons   ),  // mouse buttons for first mouse
	.mouse1_btn   (mouse1_buttons   ),  // mouse buttons for second mouse
	.mouse_idx    (mouse_idx        ),  // mouse index
	.kbd_reset_n  (1'b1             ),  // Aux keyboard reset (not used with MiST)
	.kbd_mouse_data (kbd_mouse_data ),  // mouse direction data, keycodes
	.kbd_mouse_type (kbd_mouse_type ),  // type of data
	.kbd_mouse_strobe (kbd_mouse_stb), // kbd/mouse data strobe
	.kms_level    (kms_level        ),
	._15khz       (_15khz           ), // scandoubler disable
	.rtc          (rtc              ), // real-time clock
	.pwr_led      (LED_POWER        ), // power led
	.disk_led     (LED_DISK         ), // power led
	.msdat_i      (PS2_MDAT_I       ), // PS2 mouse data
	.msclk_i      (PS2_MCLK_I       ), // PS2 mouse clk
	.kbddat_i     (PS2_DAT_I        ), // PS2 keyboard data
	.kbdclk_i     (PS2_CLK_I        ), // PS2 keyboard clk
	.msdat_o      (PS2_MDAT_O       ), // PS2 mouse data
	.msclk_o      (PS2_MCLK_O       ), // PS2 mouse clk
	.kbddat_o     (PS2_DAT_O        ), // PS2 keyboard data
	.kbdclk_o     (PS2_CLK_O        ), // PS2 keyboard clk
	//host controller interface (SPI)
	._scs         ( {SPI_SS4,SPI_SS3,SPI_SS2}  ),  // SPI chip select spi_chipselect(6 downto 4),
	.direct_sdi   (SD_MISO          ),  // SD Card direct in  SPI_SDO
	.sdi          (SPI_DI           ),  // SPI data input
	.sdo          (SPI_DO           ),  // SPI data output
	.sck          (SPI_SCK          ),  // SPI clock
	//video
	.selcsync     (selcsync         ),
	._csync       (cs               ),  // horizontal sync
	._hsync       (hs               ),  // horizontal sync
	.hsyncpol     (hsyncpol         ),
	._vsync       (vs               ),  // vertical sync
	.vsyncpol     (vsyncpol         ),
	.red          (red_amiga        ),  // red
	.green        (green_amiga      ),  // green
	.blue         (blue_amiga       ),  // blue
	//audio
//	.left         (                 ),  // audio bitstream left
//	.right        (                 ),  // audio bitstream right
	.ldata        (AUDIO_L          ),  // left DAC data
	.rdata        (AUDIO_R          ),  // right DAC data
    .aux_left_2   (aud_left         ),  // Auxiliary audio channels
    .aux_right_2  (aud_right        ),  // Auxiliary audio channels
	//user i/o
	.cpu_config   (cpu_config       ), // CPU config
   .board_configured(board_configured),
	.turbochipram (turbochipram     ), // turbo chipRAM
	.turbokick    (turbokick        ), // turbo kickstart
	.slow_config  (slow_config      ),
	.aga          (aga              ),
	.init_b       (                 ), // vertical sync for MCU (sync OSD update)
	.fifo_full    (                 ),
	// fifo / track display
	.trackdisp    (                 ),  // floppy track number
	.secdisp      (                 ),  // sector
	.floppy_fwr   (                 ),  // floppy fifo writing
	.floppy_frd   (                 ),  // floppy fifo reading
	.hd_fwr       (                 ),  // hd fifo writing
	.hd_frd       (                 ),  // hd fifo  ading
	.hblank_out   (hblank_amiga     ),
	.vblank_out   (vblank_amiga     ),
	.blank_out    (blank_amiga      ),
	.osd_blank_out(osd_window       ),  // Let the toplevel dither module handle drawing the OSD.
	.osd_pixel_out(osd_pixel        ),
	.rtg_ena      (rtg_ena_mm       ),
	.rtg_linecompare (rtg_linecompare),
	.ext_int2     (1'b0             ),
	.ext_int6     (aud_int          ),
	.ram_64meg    (ram_64meg        )
);

assign rtg_ena = havertg && rtg_ena_mm;

`endif

wire host_interrupt;

EightThirtyTwo_Bridge #( debug) hostcpu
(
	.clk(CLK_114),
	.nReset(reset_out),
	.addr(hostaddr),
	.q(hostWR),
	.sel(hostbytesel),
	.wr(host_we),
	.hw_d(host_hwdata),
	.hw_ack(host_hwack),
	.hw_req(host_hwreq),
	.ram_d(host_ramdata),
	.ram_req(host_ramreq),
	.ram_ack(host_ramack),
	.interrupt(host_interrupt)
);


cfide #(
	.spimux(spimux),
	.havespirtc(havespirtc),
	.haveiec(haveiec),
	.havereconfig(havereconfig),
	.havecart(havecart)
) mycfide ( 
		.sysclk(CLK_114),
		.n_reset(reset_out),

		.addr(hostaddr),
		.d(hostWR[15:0]),
		.req(host_hwreq),
		.wr(host_we),
		.ack(host_hwack),
		.q(host_hwdata),

		.sd_di(SPI_DO),
		.sd_cs(SPI_CS),
		.sd_clk(SPI_SCK),
		.sd_do(SPI_DI),
		.sd_dimm(SD_MISO),
		.sd_ack(SD_ACK),

		.debugTxD(CTRL_TX),
		.debugRxD(CTRL_RX),
		.menu_button(MENU_BUTTON),
		.scandoubler(_15khz),
		.invertsync(invertsync),
		
		.audio_ena(aud_ena_host),
		.audio_clear(aud_clear),
		.audio_buf(aud_addr[15]),
		.audio_amiga(aud_ena_cpu),
		.vbl_int(vblank_amiga),
		.interrupt(host_interrupt),
		.amiga_key(c64_translated_key),
		.amiga_key_stb(c64_translated_key_stb),
		.c64_keys(C64_KEYS),

		.amiga_addr(tg68_cad[8:1]),
		.amiga_d(tg68_cin),
		.amiga_q(amigahost_q),
		.amiga_req(amigahost_req),
		.amiga_wr(tg68_cpustate[0]),
		.amiga_ack(amigahost_ack),

		.rtc_q(rtc),
		.reconfig(RECONFIG),
		.iecserial(IECSERIAL),
		
		.usb_dp(usb_dp),
		.usb_dn(usb_dn),
		.usb_connected(LED_USB),
		
		.joykeys(joykeys),

		.clk_28(CLK_28),
		.tick_in(aud_tick)
	);
	
assign joysticka = JOYA;
assign joystickb = JOYB & joykeys;

wire [  8-1:0] dithered_red;
wire [  8-1:0] dithered_green;
wire [  8-1:0] dithered_blue;
wire           dithered_vs;
wire           dithered_hs;
wire           dithered_de;

reg [2:0] vga_strobe_ctr;
always @(posedge CLK_114) begin
	if(rtg_ena)
		vga_strobe_ctr<={vga_strobe_ctr[2],2'b00}+3'b100;
	else if (_15khz)
		vga_strobe_ctr<={vga_strobe_ctr[2:1],1'b0}+3'b010;
	else
		vga_strobe_ctr<= vga_strobe_ctr+3'b001;
end

wire vga_stb;
assign vga_stb = ~(|vga_strobe_ctr);

wire vga_window = 1'b1;
video_vga_dither #(.outbits(vga_width), .flickerreduce(1)) dither
(
	.clk(CLK_114),
	.ena(1'b1),
	.pixel(rtg_ena ? rtg_pixel : vga_stb),
	.vidEna(vga_window),
	.iSelcsync(1'b0), // selcsync),
	.iCsync(VGA_CS_INT),
	.iHsync(VGA_HS_INT),
	.iVsync(VGA_VS_INT),
	.iRed(VGA_R_INT),
	.iGreen(VGA_G_INT),
	.iBlue(VGA_B_INT),
	.oHsync(dithered_hs),
	.oVsync(dithered_vs),
	.oRed(dithered_red),
	.oGreen(dithered_green),
	.oBlue(dithered_blue)
);
	
		
always @(posedge CLK_114) begin
	if(haveaga) begin
		VGA_VS <= dithered_vs ^ (vsyncpol & !selcsync);
		VGA_HS <= dithered_hs ^ (hsyncpol & !selcsync);
		VGA_R <= dithered_red[7:8-vga_width];
		VGA_G <= dithered_green[7:8-vga_width];
		VGA_B <= dithered_blue[7:8-vga_width];
		VGA_STROBE <= rtg_ena ? rtg_pixel : vga_stb;
		VGA_DE <= rtg_de;
	end else begin
		VGA_VS <= VGA_VS_INT ^ (vsyncpol & !selcsync);
		VGA_HS <= VGA_HS_INT ^ (hsyncpol & !selcsync);
		VGA_R <= VGA_R_INT[7:8-vga_width];
		VGA_G <= VGA_G_INT[7:8-vga_width];
		VGA_B <= VGA_B_INT[7:8-vga_width];
		VGA_STROBE <= rtg_ena ? rtg_pixel : vga_stb;
		VGA_DE <= rtg_de;
	end
end

always @(posedge CLK_114) begin
	if(vga_stb) begin
		DVI_VS <= VGA_VS_INT ^ (vsyncpol & !selcsync);
		DVI_HS <= VGA_HS_INT ^ (hsyncpol & !selcsync);

		DVI_R <= VGA_R_INT;
		DVI_G <= VGA_G_INT;
		DVI_B <= VGA_B_INT;
		DVI_DE <= rtg_de;
	end
end
assign DVI_STROBE = vga_stb; // rtg_ena ? rtg_pixel : vga_stb;

`ifdef MINIMIG_CAPTURE_SYNC
edge_capture #(.bits(2)) synccapture (
	.clk(CLK_114),
	.reset(~tg68_rst),
	.d({VGA_VS_INT,VGA_HS_INT})
);
`endif

endmodule

