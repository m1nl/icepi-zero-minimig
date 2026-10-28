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
`include "minimig_board.vh"
`include "minimig_defines.vh"

`default_nettype none

module minimig_virtual_top #(
	parameter hostonly = 0,
	parameter debug = 0,
	parameter spimux = 0,
	parameter ram_64meg = 1,
	parameter vga_width = 6,
	parameter usethrottle = 1,
	parameter haveiec = 0,
	parameter havereconfig = 0,
	parameter havertg = 1,
	parameter haveaudio = 1,
	parameter havec2p = 1,
	parameter haveamigahost = 0,
	parameter havespirtc = 0,
	parameter havecart = 0,
	parameter havevideofilter = 1,
	parameter haveaga = 1,
	parameter haveusbhid = 0,
	parameter haveauxspi = 0,
	parameter haveuart = 0
) (
	// JTAG inputs
	output sys_tdo,
	input sys_tdi,
	input sys_tck,
	input sys_tms,

	// clock inputs
	input wire            CLK_IN,
	input wire            CLK_USB_IN,
	input wire            CLK_RTG_IN,
	input wire            RESET_N,

	// clock outputs
	output wire           CLK_114,
	output wire           CLK_28,
	output wire           CLK_142,
	output wire           PLL_LOCKED,

	// Button inputs
	input                 MENU_BUTTON,

	// RTG control and RGB output
	output wire           RTG_ENABLE,
	input wire            RTG_ACTIVE,
	input wire            RTG_VIDEO_RESET,
	output reg [23:0]     RTG_RGB,

	// HDMI events for RTG
	input wire            HDMI_FRAME_START,
	input wire            HDMI_VBLANK_START,
	input wire            HDMI_RTG_PIXEL_REQUEST,
	input wire            HDMI_RTG_FRAME_REQUEST,
	input wire            HDMI_RTG_LINE_PREPARE,
	input wire            HDMI_OSD_PIXEL_REQUEST,
	input wire            HDMI_OSD_FRAME_REQUEST,

	// LED outputs
	output wire           LED_POWER,   // LED green
	output wire           LED_FLOPPY,  // LED yellow
	output wire           LED_HDD,     // LED red
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
	output reg            DVI_STROBE,
	output reg            DVI_DE,

	// AUX video signals
	output wire           LONG_FRAME,
	output wire           DISPLAY_PAL,
	output wire           INTERLACE,
	output wire [  8-1:0] VIDEO_XOFFSET,
	output wire [  8-1:0] VIDEO_YOFFSET,
	output wire [  2-1:0] VIDEO_MODE,

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
	output wire [ 24-1:0] AUDIO_MIX_L,   // sigma-delta DAC output left
	output wire [ 24-1:0] AUDIO_MIX_R,   // sigma-delta DAC output right
	output wire [ 16-1:0] AUDIO_PAULA_L, // sigma-delta DAC output left
	output wire [ 16-1:0] AUDIO_PAULA_R, // sigma-delta DAC output right
	output wire           AUDIO_TICK,

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
	input                 AMIGA_RESET_N,
	input       [  8-1:0] AMIGA_KEY,
	input                 AMIGA_KEY_STB,
	input       [ 64-1:0] C64_KEYS,

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

	inout wire  [  2-1:0] USB_DP,
	inout wire  [  2-1:0] USB_DN,

	input wire            AUX_SPI_CSN,
	input wire            AUX_SPI_CLK,
	input wire            AUX_SPI_MOSI,

	output wire           RECONFIG,
	output wire           IECSERIAL,
	input wire            FREEZE
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
wire           sdctl_rst;

// tg68
wire           tg68_rst;
reg            tg68_rst_d;
reg    [2-1:0] tg68_rstn_sync = 2'b00;
wire           tg68_rstn;
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
wire [15:0] tg68_cout_hi, tg68_cin_lo;
wire tg68_long_cand;
wire           tg68_cpuena;
wire [  4-1:0] cpu_config;
wire           overclock;
wire [4:0]     board_configured;
wire           turbochipram;
wire           turbokick;
wire [1:0]     chip_config;
wire [1:0]     slow_config;
wire           aga;
wire           cache_inhibit;
wire           cacheline_clr;
wire [ 32-1:0] tg68_cad;
wire [  5-1:0] tg68_cpustate;
wire           tg68_nrst_out;
//wire           tg68_cdma;
wire           tg68_clds;
wire           tg68_cuds;
wire [  4-1:0] tg68_CACR_out;
wire [ 32-1:0] tg68_VBR_out;
wire           tg68_fast_rd;

// minimig
wire [ 16-1:0] ram_data;      // sram data bus
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

wire [  8-1:0] red_amiga;
wire [  8-1:0] green_amiga;
wire [  8-1:0] blue_amiga;
wire           hsyncpol;
wire           vsyncpol;
wire           selcsync;

// sdram
wire           reset_out;
wire [  4-1:0] sdram_cs;
wire [  2-1:0] sdram_dqm;
wire [  2-1:0] sdram_ba;

// mist
wire [  11:0] joysticka;
wire [  11:0] joystickb;
wire [  11:0] extjoya;
wire [  11:0] extjoyb;

// Realtime clock
wire [63:0] rtc;

// Limit physical address space depending on SDRAM size
localparam addr_max_bits = (ram_64meg == 0 ? 25 : 26);

////////////////////////////////////////
// toplevel assignments               //
////////////////////////////////////////

// SDRAM
assign SDRAM_CKE  = 1'b1;
assign SDRAM_CLK  = clk_sdram;
assign SDRAM_nCS  = sdram_cs[0];
assign SDRAM_DQML = sdram_dqm[0];
assign SDRAM_DQMH = sdram_dqm[1];
assign SDRAM_BA   = sdram_ba;

// reset
assign sdctl_rst = PLL_LOCKED & RESET_N;

// Native video blanking
wire vblank_amiga;
wire blank_amiga;

// RTG register interface
wire [10:0] rtg_reg_addr;
wire [15:0] rtg_reg_d;
wire [15:0] rtg_reg_q;

wire rtg_reg_wr;
wire rtg_reg_req;
wire rtg_reg_ack;
wire rtg_irq_28;

// RTG to RAM interface
wire [25:0] rtg_fetch_addr;
wire [15:0] rtg_fromram;

wire rtg_ramreq;
wire rtg_fill;
wire rtg_rampri;
wire rtg_ram_extend;
wire rtg_ramack;

// OSD drawing for RTG
wire [10:0] osd_write_addr;
wire  [7:0] osd_write_data;

wire osd_write_en;
wire osd_enabled;

// Overlaying of OSD graphics
wire osd_window;
wire osd_pixel;

wire [1:0] osd_r = osd_pixel ? 2'b11 : 2'b00;
wire [1:0] osd_g = osd_pixel ? 2'b11 : 2'b00;
wire [1:0] osd_b = osd_pixel ? 2'b11 : 2'b10;

wire [7:0] VGA_R_INT = osd_window ? {osd_r, red_amiga[7:2]} : red_amiga;
wire [7:0] VGA_G_INT = osd_window ? {osd_g, green_amiga[7:2]} : green_amiga;
wire [7:0] VGA_B_INT = osd_window ? {osd_b, blue_amiga[7:2]} : blue_amiga;

wire VGA_CS_INT;
wire VGA_VS_INT;
wire VGA_HS_INT;

generate
	if (havertg) begin : gen_rtg
		wire [7:0] scan_r;
		wire [7:0] scan_g;
		wire [7:0] scan_b;

		(* ASYNC_REG = "TRUE" *)
		reg [1:0] rtg_resetn_sync = 2'b00;

		// Reset RTG on either system/CPU reset or the CPU RESET instruction.
		// TG68K's nResetOut is generated in CLK_114.
		wire rtg_cpu_resetn = tg68_rstn && tg68_nrst_out;

		wire rtg_resetn = rtg_resetn_sync[1];

		always @(posedge CLK_RTG_IN, negedge reset_out) begin
			if (!reset_out)
				rtg_resetn_sync <= 2'b00;
			else begin
				/* sample CPU reset synchronously in the video domain */
				if (!rtg_cpu_resetn)
					rtg_resetn_sync <= 2'b00;
				else
					rtg_resetn_sync <= {rtg_resetn_sync[0], 1'b1};
			end
		end

		wire rtg_irq;

		(* ASYNC_REG = "TRUE" *)
		reg [1:0] rtg_irq_28_sync;

		always @(posedge CLK_28 or negedge reset_out) begin
			if (!reset_out)
				rtg_irq_28_sync <= 0;
			else begin
				/* sample CPU reset synchronously in the IRQ domain */
				if (!rtg_cpu_resetn)
					rtg_irq_28_sync <= 0;
				else
					rtg_irq_28_sync <= {rtg_irq_28_sync[0], rtg_irq};
			end
		end

		assign rtg_irq_28 = rtg_irq_28_sync[1];

		rtg_video rtg (
			.clk_sys(CLK_114),
			.resetn_sys(reset_out && rtg_cpu_resetn),
			.clk_rtg(CLK_RTG_IN),
			.resetn_rtg(rtg_resetn),

			.rtg_active(RTG_ACTIVE),
			.rtg_enable(RTG_ENABLE),
			.video_reset(RTG_VIDEO_RESET),
			.frame_start_toggle(HDMI_FRAME_START),
			.vblank_start_toggle(HDMI_VBLANK_START),
			.pixel_request(HDMI_RTG_PIXEL_REQUEST),
			.frame_request(HDMI_RTG_FRAME_REQUEST),
			.line_prepare(HDMI_RTG_LINE_PREPARE),

			// RTG register access
			.reg_addr(rtg_reg_addr), .reg_wr(rtg_reg_wr), .reg_req(rtg_reg_req),
			.reg_d(rtg_reg_d), .reg_ack(rtg_reg_ack), .reg_q(rtg_reg_q), .irq(rtg_irq),

			// RTG SDRAM fetch
			.fetch_addr(rtg_fetch_addr), .fetch_req(rtg_ramreq), .fetch_pri(rtg_rampri),
			.fetch_extend(rtg_ram_extend),
			.fetch_d(rtg_fromram), .fetch_ack(rtg_ramack), .fetch_fill(rtg_fill),

			// RTG output
			.red(scan_r), .green(scan_g), .blue(scan_b)
		);

		wire rtg_overlay;
		wire rtg_overlay_pixel;

		rtg_osd osd_rtg (
			.clk_write(CLK_28),
			.clk_rtg(CLK_RTG_IN),
			.reset_n(rtg_resetn),
			.video_reset(RTG_VIDEO_RESET || !RTG_ACTIVE),
			.write_en(osd_write_en),
			.write_addr(osd_write_addr),
			.write_data(osd_write_data),
			.enable(osd_enabled),
			.pixel_request(HDMI_OSD_PIXEL_REQUEST),
			.frame_request(HDMI_OSD_FRAME_REQUEST),
			.overlay(rtg_overlay),
			.pixel(rtg_overlay_pixel)
		);

		wire [23:0] RTG_RGB_INT = rtg_overlay ?
			{rtg_overlay_pixel ? 2'b11 : 2'b00, scan_r[7:2],
			 rtg_overlay_pixel ? 2'b11 : 2'b00, scan_g[7:2],
			 rtg_overlay_pixel ? 2'b11 : 2'b10, scan_b[7:2]} : {scan_r,scan_g,scan_b};

		// Give HDMI's rising-edge capture half a pixel period of separation.
		always @(negedge CLK_RTG_IN)
			RTG_RGB <= RTG_RGB_INT;

	end else begin : gen_no_rtg
		assign RTG_ENABLE = 1'b0;

		assign rtg_irq_28 = 1'b0;
		assign rtg_reg_ack = 1'b0;
		assign rtg_reg_q = 16'hffff;

		assign rtg_fetch_addr = 26'b0;
		assign rtg_ramreq     = 1'b0;
		assign rtg_rampri     = 1'b0;
		assign rtg_ram_extend = 1'b0;

		always @(*)
			RTG_RGB = 24'd0;
	end
endgenerate

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

wire [25:0] aud_ramaddr;
assign aud_ramaddr[15:0]=aud_addr[15:0];
assign aud_ramaddr[25:16]=10'b0001101111;  // 0x6f0000 in SDRAM, 0x040000 to host, 0xec0000 to Amiga

wire [25:0] aud_baseaddr=26'b0;

reg [9:0] aud_ctr;
always @(posedge CLK_28) begin
	aud_tick <= 1'b0;
	aud_ctr <= aud_ctr+1;

	if (aud_ctr == 10'd642) begin
		aud_tick <= 1'b1;
		aud_ctr <= 10'd0;
	end
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

generate
	if (haveaudio) begin
		// We can use the same type of FIFO as we use for video.
		VideoStream #(.fifodepth(9),.burstdepth(3),.signalwidth(16)) myaudiostream
		(
			.clk(CLK_114),
			.reset_n(aud_ena_host | aud_ena_cpu),
			.enable(aud_ena_host | aud_ena_cpu),
			.baseaddr(aud_baseaddr),
			// SDRAM interface
			.a(aud_addr),
			.req(aud_ramreq),
			.ack(aud_ramack),
			.pri(aud_rampri),
			.d(aud_fromram),
			.fill(aud_fill),
			// Display interface
			.rdreq(aud_next),
			.q(aud_sample)
		);
	end else begin
		assign aud_ramreq = 0;
		assign aud_rampri = 0;
		assign aud_sample = 0;
	end
endgenerate

wire clk_56;

//// amiga clocks ////
amiga_clk amiga_clk (
	.rst          (1'b0             ), // async reset input
	.clk_in       (CLK_IN           ), // input clock     ( 27.000000MHz)
	.clk_sdram    (clk_sdram        ), // output clock c0 (114.750000MHz, -146.25 deg)
	.clk_114      (CLK_114          ), // output clock c1 (114.750000MHz)
	.clk_28       (CLK_28           ), // output clock c2 ( 28.375160MHz)
	.clk_56       (clk_56           ), // output clock c3
	.clk_142      (CLK_142          ), // output clock c4 (141.8758MHz)
	.clk7_en      (clk7_en          ), // output clock 7 enable (on 28MHz clock domain)
	.clk7n_en     (clk7n_en         ), // 7MHz negedge output clock enable (on 28MHz clock domain)
	.c1           (c1               ), // clk28m clock domain signal synchronous with clk signal
	.c3           (c3               ), // clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	.cck          (cck              ), // colour clock output (3.54 MHz)
	.eclk         (eclk             ), // 0.709379 MHz clock enable output (clk domain pulse)
	.ntsc         (1'b0             ),
	.locked       (PLL_LOCKED       )  // pll locked output
);

wire  [7:0] amigahost_addr;
wire        amigahost_req;
wire        amigahost_ack;
wire        amigahost_wr;
wire [15:0] amigahost_q;
wire [15:0] amigahost_d;

//// TG68K main CPU ////
`ifdef HOSTONLY
assign tg68_cpustate=4'b00101;
assign tg68_long_cand=1'b0;
assign tg68_cin_lo=16'b0;
assign tg68_nrst_out=1'b1;
`else

always @(posedge CLK_114, negedge tg68_rst) begin
	if (!tg68_rst)
		tg68_rstn_sync <= 2'b00;
	else
		tg68_rstn_sync <= {tg68_rstn_sync[0], 1'b1};
end

assign tg68_rstn = tg68_rstn_sync[1];

TG68K #(
	.usethrottle(usethrottle),
	.havertg(havertg),
	.haveaudio(haveaudio),
	.havec2p(havec2p),
	.haveamigahost(haveamigahost),
	.havecart(havecart),
	.sdram64meg(ram_64meg)
) tg68k (
	.clk          (CLK_114          ),
	.reset        (tg68_rstn        ),
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
	.ena7RDreg    (tg68_ena7RD      ),
	.ena7WRreg    (tg68_ena7WR      ),
	.fromram_hi   (tg68_cout_hi     ),
	.toram_lo     (tg68_cin_lo      ),
	.ram_long_cand(tg68_long_cand   ),
	.fromram      (tg68_cout        ),
	.toram        (tg68_cin         ),
	.ramready     (tg68_cpuena      ),
	.cpu          (cpu_config[1:0]  ),
	.overclock    (overclock        ),
	.turbochipram (turbochipram     ),
	.turbokick    (turbokick        ),
	.chip_config  (chip_config      ),
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
	// Audio signals
	.audio_buf(aud_addr[15]),
	.audio_ena(aud_ena_cpu),
	.audio_int(aud_int),
	// RTG signals
	.rtg_reg_addr(rtg_reg_addr),
	.rtg_reg_req(rtg_reg_req),
	.rtg_reg_ack(rtg_reg_ack),
	.rtg_reg_wr(rtg_reg_wr),
	.rtg_reg_d(rtg_reg_d),
	.rtg_reg_q(rtg_reg_q),
	// Amiga to host signals
	.host_addr(amigahost_addr),
	.host_req(amigahost_req),
	.host_ack(amigahost_ack),
	.host_wr(amigahost_wr),
	.host_q(amigahost_q),
	.host_d(amigahost_d)
);

`endif
wire	[31:0]	hostWR;
wire	[31:2]	hostaddr;
wire	[ 3:0]	hostbytesel;
wire		host_interrupt;
wire	[15:0]	host_ramdata;
wire		host_ramack;
wire		host_ramreq;
wire	[31:0]	host_hwdata;
wire		host_hwack;
wire		host_hwreq;
wire		host_we;

wire cache_rstn = tg68_rstn && tg68_nrst_out;

//sdram sdram (
sdram_ctrl #(
`ifdef MINIMIG_SDRAM_WRITE_QUEUE
	.cpu_write_queue(1),
`endif
	.addr_max_bits(addr_max_bits)
) sdram (
	.cache_rstn   (cache_rstn       ),
	.cache_inhibit(cache_inhibit    ),
	.cacheline_clr(cacheline_clr    ),
	.cpu_cache_ctrl(tg68_CACR_out   ),
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
	.hostwe       (host_we          ),
	.hostce       (host_ramreq      ),
	.hostinterrupt(host_interrupt   ),
	.hostbytesel  (hostbytesel      ),
	.hostRD       (host_ramdata     ),
	.hostena      (host_ramack      ),

	.cpu_long_cand(tg68_long_cand   ),
	.cpuWR_lo     (tg68_cin_lo      ),
	.cpuRD_hi     (tg68_cout_hi     ),
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
	.rtg_extend_ok(rtg_ram_extend   ),
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


// SPI signals shared by Minimig and the host controller.

wire [8-1 : 0] SPI_CS;
wire SPI_DO;
wire SPI_DI;
wire SPI_SCK;
wire SPI_SS2;
wire SPI_SS3;
wire SPI_SS4;

assign SD_CLK = SPI_SCK;
assign SD_CS = SPI_CS[1];
assign SD_MOSI = SPI_DI;
assign SPI_SS4 = SPI_CS[6];
assign SPI_SS3 = SPI_CS[5];
assign SPI_SS2 = SPI_CS[4];
assign RTC_CS = SPI_CS[7];

// Keyboard-related signals

wire	[15:0]	c64_translated_key;
wire		c64_translated_key_stb;

reg	[7:0]	kbd_mouse_data;
wire		kbd_reset_n;
reg		kbd_mouse_stb;
reg	[1:0]	kbd_mouse_type;

wire		keyboard_done;
wire		keyboard_unavailable;

reg		kms_level;

reg		mouse_idx;
reg	[2:0]	mouse0_buttons;
reg	[2:0]	mouse1_buttons;

reg		amiga_key_stb_r;

assign kbd_reset_n = AMIGA_RESET_N;

always @(*) begin
	kbd_mouse_data = amiga_key_stb_r ? AMIGA_KEY : c64_translated_key[ 7: 0];
	kbd_mouse_type = amiga_key_stb_r ? 2'b10     : c64_translated_key[15:14];
	mouse0_buttons = amiga_key_stb_r ? 3'b000    : c64_translated_key[10: 8];
	mouse1_buttons = amiga_key_stb_r ? 3'b000    : c64_translated_key[13:11];
end

always @(posedge CLK_28) begin
	if (clk7_en) begin
		kbd_mouse_stb <= 1'b0;
		amiga_key_stb_r <= 1'b0;
	end

	if (c64_translated_key_stb || AMIGA_KEY_STB) begin
		kbd_mouse_stb <= 1'b1;
		kms_level     <= ~kms_level;
		amiga_key_stb_r <= AMIGA_KEY_STB;
	end
end

//// minimig top ////
`ifdef HOSTONLY
assign SPI_DO=1'b1;
assign _ram_oe=1'b1;
assign _ram_we=1'b1;
assign keyboard_done=1'b0;
assign keyboard_unavailable=1'b1;
`else

// RTG is independent of Agnus; leave its timing shadow functionality disabled.
minimig #(.usevideofilter(havevideofilter),.useaga(haveaga),.usertg(1'b0),.wide_hblank(0)) minimig
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
	.ovr          (                 ), // NMI override address decoding
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
	.midi_tx      (                 ),
	//I/O
	._joy1        (joysticka        ),  // joystick 1 [fire7:fire,up,down,left,right] (default mouse port)
	._joy2        (joystickb        ),  // joystick 2 [fire7:fire,up,down,left,right] (default joystick port)
	._joy3        (JOYC             ),  // joystick 3 [fire7:fire,up,down,left,right]
	._joy4        (JOYD             ),  // joystick 4 [fire7:fire,up,down,left,right]
	//  .mouse_btn    (mouse_buttons    ),  // mouse buttons
	.mouse0_btn   (mouse0_buttons   ),  // mouse buttons for first mouse
	.mouse1_btn   (mouse1_buttons   ),  // mouse buttons for second mouse
	.mouse_idx    (mouse_idx        ),  // mouse index
	.kbd_reset_n  (kbd_reset_n      ),  // Aux keyboard reset
	.kbd_mouse_data (kbd_mouse_data ),  // mouse direction data, keycodes
	.keyboard_done (keyboard_done),
	.keyboard_unavailable (keyboard_unavailable),
	.kbd_mouse_type (kbd_mouse_type ),  // type of data
	.kbd_mouse_strobe (kbd_mouse_stb), // kbd/mouse data strobe
	.kms_level    (kms_level        ),
	._15khz       (_15khz           ), // scandoubler disable
	.rtc          (rtc              ), // real-time clock
	.pwr_led      (LED_POWER        ), // power led
	.floppy_led   (LED_FLOPPY       ), // floppy led
	.hdd_led      (LED_HDD          ), // hdd led
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
	._csync       (VGA_CS_INT       ),  // horizontal sync
	._hsync       (VGA_HS_INT       ),  // horizontal sync
	._vsync       (VGA_VS_INT       ),  // vertical sync
	.selcsync     (selcsync         ),
	.hsyncpol     (hsyncpol         ),
	.vsyncpol     (vsyncpol         ),
	.red          (red_amiga        ),  // red
	.green        (green_amiga      ),  // green
	.blue         (blue_amiga       ),  // blue
	//audio
//	.left         (                 ),  // audio bitstream left
//	.right        (                 ),  // audio bitstream right
	.ldata_mix    (AUDIO_MIX_L      ),  // left DAC data
	.rdata_mix    (AUDIO_MIX_R      ),  // right DAC data
	.ldata_paula  (AUDIO_PAULA_L    ),  // left DAC data
	.rdata_paula  (AUDIO_PAULA_R    ),  // right DAC data

	.aux_left_2   (aud_left         ),  // Auxiliary audio channels
	.aux_right_2  (aud_right        ),  // Auxiliary audio channels
	.cen_44100    (AUDIO_TICK       ),
	//user i/o
	.cpu_config   (cpu_config       ), // CPU config
	.overclock    (overclock        ), // overclock
	 .board_configured(board_configured),
	.turbochipram (turbochipram     ), // turbo chipRAM
	.turbokick    (turbokick        ), // turbo kickstart
	.chip_config  (chip_config      ),
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
	.hblank_out   (                 ),
	.vblank_out   (vblank_amiga     ),
	.blank_out    (blank_amiga      ),
	.long_frame   (LONG_FRAME       ),
	.displaypal_out (DISPLAY_PAL    ),
	.interlace_out(INTERLACE        ),
	.xoffset_out  (VIDEO_XOFFSET    ),
	.yoffset_out  (VIDEO_YOFFSET    ),
	.vmode_out    (VIDEO_MODE       ),
	.osd_blank_out(osd_window       ),  // Let the toplevel dither module handle drawing the OSD.
	.osd_pixel_out(osd_pixel        ),
	.rtg_ena      (                 ),
	.rtg_linecompare(               ),
	.osd_write_en (osd_write_en     ),
	.osd_write_addr(osd_write_addr  ),
	.osd_write_data(osd_write_data  ),
	.osd_enabled  (osd_enabled      ),
	.ext_int2     (rtg_irq_28       ),
	.ext_int6     (aud_int          ),
	.ram_64meg    (ram_64meg        )
);
`endif

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
	.havecart(havecart),
	.havevideofilter(havevideofilter),
	.haveamigahost(haveamigahost),
	.haveaudio(haveaudio),
	.haveusbhid(haveusbhid),
	.haveauxspi(haveauxspi),
	.haveuart(haveuart)
) mycfide (
	.sysclk(CLK_114),
	.usbclk(CLK_USB_IN),
	.reset_n(reset_out),
	.addr(hostaddr),
	.d(hostWR),
	.req(host_hwreq),
	.wr(host_we),
	.ack(host_hwack),
	.q(host_hwdata),

	.aux_spi_csn(AUX_SPI_CSN),
	.aux_spi_clk(AUX_SPI_CLK),
	.aux_spi_mosi(AUX_SPI_MOSI),

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
	.invertsync(),

	.audio_ena(aud_ena_host),
	.audio_clear(),
	.audio_buf(aud_addr[15]),
	.audio_amiga(aud_ena_cpu),
	.vbl_int(vblank_amiga),
	.interrupt(host_interrupt),
	.amiga_key(c64_translated_key),
	.amiga_key_stb(c64_translated_key_stb),
	.keyboard_done(keyboard_done),
	.keyboard_unavailable(keyboard_unavailable),
	.c64_keys(C64_KEYS),

	.amiga_addr(amigahost_addr),
	.amiga_req(amigahost_req),
	.amiga_ack(amigahost_ack),
	.amiga_wr(amigahost_wr),
	.amiga_d(amigahost_d),
	.amiga_q(amigahost_q),

	.rtc_q(rtc),
	.reconfig(RECONFIG),
	.iecserial(IECSERIAL),

	.usb_dp(USB_DP),
	.usb_dn(USB_DN),
	.usb_connected(LED_USB),

	.joya(extjoya),
	.joyb(extjoyb),

	.clk_28(CLK_28),
	.tick_in(AUDIO_TICK)
);

assign joysticka = {5'b11111, JOYA} & extjoya;
assign joystickb = {5'b11111, JOYB} & extjoyb;

wire [  8-1:0] dithered_red;
wire [  8-1:0] dithered_green;
wire [  8-1:0] dithered_blue;
wire           dithered_vs;
wire           dithered_hs;

reg [2:0] vga_strobe_ctr;

always @(posedge CLK_114) begin
`ifdef MINIMIG_STATIC_HDMI_TIMING
	vga_strobe_ctr <= {vga_strobe_ctr[2:1], 1'b0} + 3'b010;
`else
	if (_15khz)
		vga_strobe_ctr <= {vga_strobe_ctr[2:1], 1'b0} + 3'b010;
	else
		vga_strobe_ctr <= vga_strobe_ctr + 3'b001;
`endif
end

wire vga_stb;
wire vga_window = 1'b1;

assign vga_stb = ~(|vga_strobe_ctr);

video_vga_dither #(.outbits(vga_width), .flickerreduce(1)) dither
(
	.clk(CLK_114),
	.ena(1'b1),
	.pixel(vga_stb),
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
	if (haveaga) begin
		VGA_VS <= dithered_vs ^ (vsyncpol & !selcsync);
		VGA_HS <= dithered_hs ^ (hsyncpol & !selcsync);
		VGA_R  <= dithered_red[7:8-vga_width];
		VGA_G  <= dithered_green[7:8-vga_width];
		VGA_B  <= dithered_blue[7:8-vga_width];
		VGA_DE <= ~blank_amiga;

		VGA_STROBE <= vga_stb;

	end else begin
		VGA_VS <= VGA_VS_INT ^ (vsyncpol & !selcsync);
		VGA_HS <= VGA_HS_INT ^ (hsyncpol & !selcsync);
		VGA_R  <= VGA_R_INT[7:8-vga_width];
		VGA_G  <= VGA_G_INT[7:8-vga_width];
		VGA_B  <= VGA_B_INT[7:8-vga_width];
		VGA_DE <= ~blank_amiga;

		VGA_STROBE <= vga_stb;
	end
end

always @(negedge CLK_28) begin
	DVI_VS <= VGA_VS_INT ^ (vsyncpol & !selcsync);
	DVI_HS <= VGA_HS_INT ^ (hsyncpol & !selcsync);
	DVI_R  <= VGA_R_INT;
	DVI_G  <= VGA_G_INT;
	DVI_B  <= VGA_B_INT;
	DVI_DE <= ~blank_amiga;

	DVI_STROBE <= vga_stb;
end

endmodule
// vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
