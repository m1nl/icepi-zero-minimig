library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;
use work.board_config.all;

entity minimig_icepizero_top is
port (
	clk	:	in std_logic; -- 50MHz

	usb_tx	:	out std_logic;
	usb_rx	:	in std_logic;

	slave_tx	:	out std_logic;
	slave_rx	:	in std_logic;

	button	:	in std_logic_vector(1 downto 0);
	slave_button	:	in std_logic_vector(1 downto 0);

	led	:	out std_logic_vector(4 downto 0);

	sdram_clk 	:	out std_logic;
	sdram_csn 	:	out std_logic;
	sdram_a   	:	out std_logic_vector(12 downto 0);
	sdram_dq  	:	inout std_logic_vector(15 downto 0);
	sdram_wen 	:	out std_logic;
	sdram_rasn	:	out std_logic;
	sdram_casn	:	out std_logic;
	sdram_cke 	:	out std_logic;
	sdram_ba  	:	out std_logic_vector(1 downto 0);
	sdram_dqm 	:	out std_logic_vector(1 downto 0);

	sd_clk	:	out std_logic;
	sd_mosi	:	out std_logic;
	sd_csn	:	out std_logic;
	sd_miso	:	in std_logic;

	usb_dp	:	inout std_logic_vector(1 downto 0);
	usb_dn	:	inout std_logic_vector(1 downto 0);
	usb_pull_dp	:	out std_logic_vector(1 downto 0);
	usb_pull_dn	:	out std_logic_vector(1 downto 0);

	joya	:	std_logic_vector(5 downto 0);
	joyb	:	std_logic_vector(5 downto 0);

	aux_spi_clk	:	in std_logic;
	aux_spi_mosi	:	in std_logic;
	aux_spi_csn	:	in std_logic;

	led_g	:	out std_logic;
	led_y	:	out std_logic;
	led_r	:	out std_logic;

	-- gpio	:	inout std_logic_vector(27 downto 0);

	gpdi_dp	:	out std_logic_vector(3 downto 0)	-- Quasi-differential output for digital video.
);
end entity;

architecture rtl of minimig_icepizero_top is
	-- RTG raster configuration. Match the driver profile and clock constraints.
	constant RTG_PIXEL_HZ            : natural := 66000000;
	constant RTG_PIXELX5_HZ          : natural := 5 * RTG_PIXEL_HZ;

	constant RTG_FRAME_WIDTH         : natural := 1344;
	constant RTG_FRAME_HEIGHT        : natural := 806;
	constant RTG_SCREEN_WIDTH        : natural := 1024;
	constant RTG_SCREEN_HEIGHT       : natural := 768;
	constant RTG_HSYNC_PULSE_START   : natural := 24;
	constant RTG_HSYNC_PULSE_SIZE    : natural := 136;
	constant RTG_VSYNC_PULSE_START   : natural := 3;
	constant RTG_VSYNC_PULSE_SIZE    : natural := 6;
	-- Bit 0 inverts HSync; bit 1 inverts VSync. CEA mode 0 is unspecified.
	constant RTG_POLARITY_INVERT     : std_logic_vector(1 downto 0) := "11";
	constant RTG_CEA_MODE            : natural := 0;

	-- constant RTG_FRAME_WIDTH       : natural := 1650;
	-- constant RTG_FRAME_HEIGHT      : natural := 750;
	-- constant RTG_SCREEN_WIDTH      : natural := 1280;
	-- constant RTG_SCREEN_HEIGHT     : natural := 720;
	-- constant RTG_HSYNC_PULSE_START : natural := 110;
	-- constant RTG_HSYNC_PULSE_SIZE  : natural := 40;
	-- constant RTG_VSYNC_PULSE_START : natural := 5;
	-- constant RTG_VSYNC_PULSE_SIZE  : natural := 5;
	-- -- Bit 0 inverts HSync; bit 1 inverts VSync. CEA mode 0 is unspecified.
	-- constant RTG_POLARITY_INVERT   : std_logic_vector(1 downto 0) := "00";
	-- constant RTG_CEA_MODE          : natural := 0;

	-- Internal signals
	signal audio_l	:	std_logic_vector(15 downto 0);
	signal audio_r	:	std_logic_vector(15 downto 0);
	signal audio_tick	:	std_logic;

	signal clk_sys	:	std_logic;
	signal clk_28m	:	std_logic;
	signal clk_142m	:	std_logic;

	signal clk_usb	:	std_logic;
	signal clk_rtg_5x	:	std_logic;
	signal clk_rtg	:	std_logic;

	signal clk_pixel	:	std_logic;
	signal clk_tmds	:	std_logic;

	signal pll_locked	:	std_logic;
	signal auxpll_locked	:	std_logic;

	signal rtg_enable	:	std_logic;
	signal rtg_active	:	std_logic := '0';
	signal rtg_rgb	:	std_logic_vector(23 downto 0);

	signal hdmi_frame_start	:	std_logic;
	signal hdmi_vblank_start	:	std_logic;
	signal hdmi_rtg_pixel_request	:	std_logic;
	signal hdmi_rtg_frame_request	:	std_logic;
	signal hdmi_rtg_line_prepare	:	std_logic;
	signal hdmi_osd_pixel_request	:	std_logic;
	signal hdmi_osd_frame_request	:	std_logic;
	signal hdmi_reset	:	std_logic;

	signal reset_n	:	std_logic;
	signal amiga_reset_n	:	std_logic;
	signal menu_button_n	:	std_logic;
	signal serial_rx	:	std_logic;
	signal serial_tx	:	std_logic;

	signal dvi_red	:	std_logic_vector(7 downto 0);
	signal dvi_green	:	std_logic_vector(7 downto 0);
	signal dvi_blue	:	std_logic_vector(7 downto 0);
	signal dvi_hsync	:	std_logic := '0';
	signal dvi_vsync	:	std_logic := '0';
	signal dvi_window	:	std_logic;
	signal dvi_pixel	:	std_logic;

	signal display_pal	:	std_logic;
	signal long_frame	:	std_logic;
	signal interlace	:	std_logic;

	signal video_xoffset	:	std_logic_vector(7 downto 0);
	signal video_yoffset	:	std_logic_vector(7 downto 0);
	signal video_mode	:	std_logic_vector(1 downto 0);

	signal joya_i	:	std_logic_vector(6 downto 0);
	signal joyb_i	:	std_logic_vector(6 downto 0);
	signal joyc_i	:	std_logic_vector(6 downto 0);
	signal joyd_i	:	std_logic_vector(6 downto 0);

	signal auxclks	:	std_logic_vector(3 downto 0);

	signal led_floppy	:	std_logic;
	signal led_hdd	:	std_logic;
	signal led_power	:	std_logic;
	signal led_usb	:	std_logic_vector(1 downto 0);

	signal led_i	:	std_logic_vector(4 downto 0);
	signal led_counter	:	std_logic_vector(1 downto 0);

	component ODDRX1F
	port (
		D0	:	in std_logic;
		D1	:	in std_logic;
		Q	:	out std_logic;
		SCLK	:	in std_logic;
		RST	:	in std_logic
	);
	end component;

	component DCSC
	generic (
		DCSMODE	:	string := "NEG"
	);
	port (
		CLK1, CLK0	:	in std_logic;
		SEL1, SEL0	:	in std_logic;
		MODESEL	:	in std_logic;
		DCSOUT	:	out std_logic
	);
	end component;
begin
	usb_pull_dp <= (others => '0');
	usb_pull_dn <= (others => '0');

	ddr_sdramclk: ODDRX1F port map (D0 => '0', D1 => '1', Q => sdram_clk, SCLK => clk_sys, RST => '0');

	reset_n <= '1';

	amiga_reset_n <= button(0) and slave_button(0);
	menu_button_n <= button(1) and slave_button(1);

	joya_i <= '1' & joya;
	joyb_i <= '1' & joyb;
	joyc_i <= (others => '1');
	joyd_i <= (others => '1');

	slave_tx  <= serial_tx;
	usb_tx    <= serial_tx;
	serial_rx <= usb_rx and slave_rx;

	auxpll	:	entity work.ecp5pll
	generic map (
		in_hz => natural(base_frequency),
		out0_hz => RTG_PIXELX5_HZ,
		out0_tol_hz => 1e4,
		out1_hz => RTG_PIXEL_HZ,
		out1_tol_hz => 1e4,
		out2_hz => natural(60e6),
		out2_tol_hz => 1e4
	)
	port map (
		clk_i => clk,
		clk_o => auxclks,
		locked => auxpll_locked
	);

	clk_rtg_5x <= auxclks(0);
	clk_rtg <= auxclks(1);
	clk_usb <= auxclks(2);

	virtual_top : component minimig_virtual_top
	generic map (
		hostonly => 0,
		debug => 0,
		spimux => 0,
		haveiec => 0,
		havereconfig => 0,
		havertg => 1,
		haveaudio => 0,
		havec2p => 1,
		haveamigahost => 0,
		havespirtc => 0,
		ram_64meg => 0,
		vga_width => 8,
		usethrottle => 0,
		havecart => 0,
		havevideofilter => 0,
		haveaga => 1,
		haveusbhid => 1,
		haveauxspi => 1,
		haveuart => 0
	)
	port map (
		CLK_IN => clk,
		CLK_USB_IN => clk_usb,
		CLK_RTG_IN => clk_rtg,

		RTG_ENABLE => rtg_enable,
		RTG_ACTIVE => rtg_active,
		RTG_VIDEO_RESET => hdmi_reset,
		RTG_RGB => rtg_rgb,

		HDMI_FRAME_START => hdmi_frame_start,
		HDMI_VBLANK_START => hdmi_vblank_start,
		HDMI_RTG_PIXEL_REQUEST => hdmi_rtg_pixel_request,
		HDMI_RTG_FRAME_REQUEST => hdmi_rtg_frame_request,
		HDMI_RTG_LINE_PREPARE => hdmi_rtg_line_prepare,
		HDMI_OSD_PIXEL_REQUEST => hdmi_osd_pixel_request,
		HDMI_OSD_FRAME_REQUEST => hdmi_osd_frame_request,

		CLK_114 => clk_sys,
		CLK_28 => clk_28m,
		CLK_142 => clk_142m,
		PLL_LOCKED => pll_locked,

		RESET_N => reset_n,
		LED_POWER => led_power,
		LED_FLOPPY => led_floppy,
		LED_HDD => led_hdd,
		LED_USB => led_usb,

		MENU_BUTTON => menu_button_n,

		CTRL_TX => open,
		CTRL_RX => '0',

		AMIGA_TX => serial_tx,
		AMIGA_RX => serial_rx,

		DVI_HS => dvi_hsync,
		DVI_VS => dvi_vsync,
		DVI_R => dvi_red,
		DVI_G => dvi_green,
		DVI_B => dvi_blue,
		DVI_STROBE => dvi_pixel,
		DVI_DE => dvi_window,

		LONG_FRAME => long_frame,
		DISPLAY_PAL => display_pal,
		INTERLACE => interlace,
		VIDEO_XOFFSET => video_xoffset,
		VIDEO_YOFFSET => video_yoffset,
		VIDEO_MODE => video_mode,

		SDRAM_DQ => sdram_dq,
		SDRAM_A => sdram_a,
		SDRAM_DQML => sdram_dqm(0),
		SDRAM_DQMH => sdram_dqm(1),
		SDRAM_nWE => sdram_wen,
		SDRAM_nCAS => sdram_casn,
		SDRAM_nRAS => sdram_rasn,
		SDRAM_nCS => sdram_csn,
		SDRAM_BA => sdram_ba,
--		SDRAM_CLK => sdram_clk,
		SDRAM_CKE => sdram_cke,

		AUDIO_PAULA_L => audio_l,
		AUDIO_PAULA_R => audio_r,
		AUDIO_TICK => audio_tick,

		PS2_DAT_I => '1',
		PS2_CLK_I => '1',
		PS2_MDAT_I => '1',
		PS2_MCLK_I => '1',

		PS2_DAT_O => open,
		PS2_CLK_O => open,
		PS2_MDAT_O => open,
		PS2_MCLK_O => open,

		AMIGA_RESET_N => amiga_reset_n,
		AMIGA_KEY => (others => '-'),
		AMIGA_KEY_STB => '0',

		C64_KEYS => (others => '1'),

		JOYA => joya_i,
		JOYB => joyb_i,
		JOYC => joyc_i,
		JOYD => joyd_i,

		SD_MISO => sd_miso,
		SD_MOSI => sd_mosi,
		SD_CLK => sd_clk,
		SD_CS => sd_csn,
		SD_ACK => '1',

		USB_DP => usb_dp,
		USB_DN => usb_dn,

		AUX_SPI_CSN => aux_spi_csn,
		AUX_SPI_CLK => aux_spi_clk,
		AUX_SPI_MOSI => aux_spi_mosi
	);

	led_g <= led_power;
	led_i(4) <= led_power;

	led_y <= led_floppy;
	led_i(3) <= led_floppy;

	led_r <= led_hdd;
	led_i(2) <= led_hdd;

	led_i(1 downto 0) <= led_usb;

	-- power indicator is quite dark already
	led(4) <= led_i(4);

	process (clk_28m)
	begin
		if rising_edge(clk_28m) then
			if audio_tick = '1' then
				led(3 downto 0) <= "0000";

				led_counter <= std_logic_vector(unsigned(led_counter) + 1);

				-- dim remaining leds
				if unsigned(led_counter) = 0 then
					led(3 downto 0) <= led_i(3 downto 0);
				end if;
			end if;
		end if;
	end process;

	-- Instantiate HDMI out:
	genvideo: block
		component hdmi
		generic (
			IT_CONTENT	:	std_logic := '1';
			DVI_OUTPUT	:	std_logic := '0';
			RTG_REQUEST_LEAD	:	integer := 3;
			VIDEO_RATE	:	integer := 28571400;
			RTG_VIDEO_RATE	:	integer := 66000000;
			AUDIO_RATE	:	integer := 48000;
			AUDIO_BIT_WIDTH	:	integer := 16;
			VENDOR_NAME	:	std_logic_vector(8*8-1 downto 0) := x"4100000000000000";  -- "A" + zero padding
			PRODUCT_DESCRIPTION	:	std_logic_vector(8*16-1 downto 0) := x"41000000000000000000000000000000"; -- "FPGA" + padding
			SOURCE_DEVICE_INFORMATION	:	std_logic_vector(7 downto 0) := x"09";
			RTG_FRAME_WIDTH	:	std_logic_vector(10 downto 0) := std_logic_vector(to_unsigned(1344, 11));
			RTG_FRAME_HEIGHT	:	std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(806, 10));
			RTG_SCREEN_WIDTH	:	std_logic_vector(10 downto 0) := std_logic_vector(to_unsigned(1024, 11));
			RTG_SCREEN_HEIGHT	:	std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(768, 10));
			RTG_HSYNC_PULSE_START	:	std_logic_vector(10 downto 0) := std_logic_vector(to_unsigned(24, 11));
			RTG_HSYNC_PULSE_SIZE	:	std_logic_vector(10 downto 0) := std_logic_vector(to_unsigned(136, 11));
			RTG_VSYNC_PULSE_START	:	std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(3, 10));
			RTG_VSYNC_PULSE_SIZE	:	std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(6, 10));
			RTG_POLARITY_INVERT	:	std_logic_vector(1 downto 0) := "11";
			RTG_CEA_MODE	:	std_logic_vector(7 downto 0) := x"00"
		);
		port (
			clk_pixel_x5	:	in  std_logic;
			clk_pixel   	:	in  std_logic;
			reset       	:	in  std_logic;

			rtg_en	:	in std_logic;

			rtg_pixel_request	:	out std_logic;
			rtg_frame_request	:	out std_logic;
			rtg_line_prepare	:	out std_logic;

			osd_pixel_request	:	out std_logic;
			osd_frame_request	:	out std_logic;

			frame_start_toggle	:	out std_logic;
			vblank_start_toggle	:	out std_logic;

			pal_mode   	:	in  std_logic;
			long_frame 	:	in  std_logic;
			interlace  	:	in  std_logic;
			screen_mode	:	in  std_logic_vector(1 downto 0);

			vsync_in	:	in  std_logic;
			hsync_in	:	in  std_logic;

			offset_x	:	in  unsigned(7 downto 0);
			offset_y	:	in  unsigned(6 downto 0);

			rgb	:	in  std_logic_vector(23 downto 0);

			audio_sample_word_0	:	in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_word_1	:	in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_en    	:	out std_logic;

			tmds      	:	out std_logic_vector(2 downto 0);
			tmds_clock	:	out std_logic
		);
		end component;

		component audio_cdc
		port (
			clk	:	in std_logic;
			clk_pixel	:	in std_logic;
			audio_l	:	in std_logic_vector(15 downto 0);
			audio_r	:	in std_logic_vector(15 downto 0);
			sample_en	:	in std_logic;
			sample	:	out std_logic_vector(31 downto 0)
		);
		end component;
		signal hdmi_audio_sample	:	std_logic_vector(31 downto 0);
		signal hdmi_audio_sample_en	:	std_logic;


		signal tmds_clock	:	std_logic;
		signal tmds	:	std_logic_vector(2 downto 0);
		signal rgb	:	std_logic_vector(23 downto 0);

		signal offset_x	:	unsigned(7 downto 0);
		signal offset_y	:	unsigned(6 downto 0);

		signal hsync_in	:	std_logic := '0';
		signal vsync_in	:	std_logic := '0';

		signal clksel_n	:	std_logic;

		component video_clock_control
		port (
			clk: in std_logic;
			clk_pixel: in std_logic;
			native_locked: in std_logic;
			rtg_locked: in std_logic;
			rtg_request: in std_logic;
			rtg_active:  out std_logic;
			video_reset: out std_logic
		);
		end component;

	begin
		clock_control : component video_clock_control
		port map (
			clk => clk,
			clk_pixel => clk_pixel,
			native_locked => pll_locked,
			rtg_locked => auxpll_locked,
			rtg_request => rtg_enable,
			rtg_active => rtg_active,
			video_reset => hdmi_reset
		);

		clksel_n <= not rtg_active;

		clkmux_0 : component DCSC
		generic map (
			DCSMODE => "NEG"
		)
		port map (
			CLK0 => clk_142m,
			CLK1 => clk_rtg_5x,
			SEL0 => clksel_n,
			SEL1 => rtg_active,
			MODESEL => '0',
			DCSOUT => clk_tmds
		);

		clkmux_1 : component DCSC
		generic map (
			DCSMODE => "NEG"
		)
		port map (
			CLK0 => clk_28m,
			CLK1 => clk_rtg,
			SEL0 => clksel_n,
			SEL1 => rtg_active,
			MODESEL => '0',
			DCSOUT => clk_pixel
		);

		offset_x <= unsigned(video_xoffset(7 downto 0));
		offset_y <= unsigned(video_yoffset(6 downto 0));

		audio_sync : component audio_cdc
		port map (
			clk => clk_28m,
			clk_pixel => clk_pixel,
			audio_l => audio_l,
			audio_r => audio_r,
			sample_en => hdmi_audio_sample_en,
			sample => hdmi_audio_sample
		);

		hdmi_inst : component hdmi
		generic map (
			VIDEO_RATE => 28571400,
			RTG_VIDEO_RATE => RTG_PIXEL_HZ,
			RTG_FRAME_WIDTH => std_logic_vector(to_unsigned(RTG_FRAME_WIDTH, 11)),
			RTG_FRAME_HEIGHT => std_logic_vector(to_unsigned(RTG_FRAME_HEIGHT, 10)),
			RTG_SCREEN_WIDTH => std_logic_vector(to_unsigned(RTG_SCREEN_WIDTH, 11)),
			RTG_SCREEN_HEIGHT => std_logic_vector(to_unsigned(RTG_SCREEN_HEIGHT, 10)),
			RTG_HSYNC_PULSE_START => std_logic_vector(to_unsigned(RTG_HSYNC_PULSE_START, 11)),
			RTG_HSYNC_PULSE_SIZE => std_logic_vector(to_unsigned(RTG_HSYNC_PULSE_SIZE, 11)),
			RTG_VSYNC_PULSE_START => std_logic_vector(to_unsigned(RTG_VSYNC_PULSE_START, 10)),
			RTG_VSYNC_PULSE_SIZE => std_logic_vector(to_unsigned(RTG_VSYNC_PULSE_SIZE, 10)),
			RTG_POLARITY_INVERT => RTG_POLARITY_INVERT,
			RTG_CEA_MODE => std_logic_vector(to_unsigned(RTG_CEA_MODE, 8)),
			RTG_REQUEST_LEAD => 2,
			AUDIO_RATE => 48000,
			AUDIO_BIT_WIDTH => 16
		)
		port map (
			clk_pixel_x5 => clk_tmds,
			clk_pixel => clk_pixel,
			reset => hdmi_reset,

			rtg_en => rtg_active,
			rtg_pixel_request => hdmi_rtg_pixel_request,
			rtg_frame_request => hdmi_rtg_frame_request,
			rtg_line_prepare => hdmi_rtg_line_prepare,

			osd_pixel_request => hdmi_osd_pixel_request,
			osd_frame_request => hdmi_osd_frame_request,

			frame_start_toggle => hdmi_frame_start,
			vblank_start_toggle => hdmi_vblank_start,

			pal_mode => display_pal,
			long_frame => long_frame,
			interlace => interlace,
			screen_mode => video_mode,

			vsync_in => vsync_in,
			hsync_in => hsync_in,

			offset_x => offset_x,
			offset_y => offset_y,

			rgb => rgb,

			audio_sample_word_0 => hdmi_audio_sample(15 downto 0),
			audio_sample_word_1 => hdmi_audio_sample(31 downto 16),
			audio_sample_en => hdmi_audio_sample_en,

			tmds => tmds,
			tmds_clock => tmds_clock
		);

		rgb <= rtg_rgb when rtg_active = '1' else dvi_red & dvi_green & dvi_blue;

		vsync_in <= dvi_vsync;
		hsync_in <= dvi_hsync;

		gpdi_dp <= tmds_clock & tmds;
	end block;
end architecture;
-- vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
