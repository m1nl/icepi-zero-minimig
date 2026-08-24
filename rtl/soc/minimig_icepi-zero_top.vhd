library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;
use work.board_config.all;

entity minimig_icepizero_top is
port (
	clk : in std_logic; -- 50MHz

	usb_tx : out std_logic;
	usb_rx : in std_logic;

	button : in std_logic_vector(1 downto 0);
	led : out std_logic_vector(4 downto 0);

	sdram_clk  : out std_logic;
	sdram_csn  : out std_logic;
	sdram_a    : out std_logic_vector(12 downto 0);
	sdram_dq   : inout std_logic_vector(15 downto 0);
	sdram_wen  : out std_logic;
	sdram_rasn : out std_logic;
	sdram_casn : out std_logic;
	sdram_cke  : out std_logic;
	sdram_ba   : out std_logic_vector(1 downto 0);
	sdram_dqm  : out std_logic_vector(1 downto 0);

	sd_clk : out std_logic;
	sd_mosi : out std_logic;
	sd_csn : out std_logic;
	sd_miso : in std_logic;

	usb_dp : inout std_logic_vector(1 downto 0);
	usb_dn : inout std_logic_vector(1 downto 0);
	usb_pull_dp : out std_logic_vector(1 downto 0);
	usb_pull_dn : out std_logic_vector(1 downto 0);

	joya : std_logic_vector(5 downto 0);
	joyb : std_logic_vector(5 downto 0);

	aux_spi_clk : in std_logic;
	aux_spi_mosi : in std_logic;
	aux_spi_csn : in std_logic;

	led_g : out std_logic;
	led_y : out std_logic;
	led_r : out std_logic;

	-- gpio : inout std_logic_vector(27 downto 0);

	gpdi_dp : out std_logic_vector(3 downto 0)	-- Quasi-differential output for digital video.
);
end entity;

architecture rtl of minimig_icepizero_top is
	-- Internal signals
	signal audio_l : std_logic_vector(15 downto 0);
	signal audio_r : std_logic_vector(15 downto 0);
	signal audio_tick : std_logic;

	signal clk_sys : std_logic;
	signal clk_pixel : std_logic;
	signal clk_tmds : std_logic;
	signal clk_usb : std_logic;

	signal pll_locked : std_logic;
	signal reset_n : std_logic;
	signal amiga_reset_n : std_logic;

	signal dvi_red : std_logic_vector(7 downto 0);
	signal dvi_green : std_logic_vector(7 downto 0);
	signal dvi_blue : std_logic_vector(7 downto 0);
	signal dvi_hsync : std_logic := '0';
	signal dvi_vsync : std_logic := '0';
	signal dvi_window : std_logic;
	signal dvi_pixel : std_logic;

	signal display_pal : std_logic;
	signal long_frame : std_logic;
	signal interlace : std_logic;

	signal video_xoffset : std_logic_vector(7 downto 0);
	signal video_yoffset : std_logic_vector(7 downto 0);

	signal joya_i : std_logic_vector(6 downto 0);
	signal joyb_i : std_logic_vector(6 downto 0);
	signal joyc_i : std_logic_vector(6 downto 0);
	signal joyd_i : std_logic_vector(6 downto 0);

	signal auxclks : std_logic_vector(3 downto 0);

	signal led_i : std_logic_vector(4 downto 0);
	signal led_counter : std_logic_vector(2 downto 0);

	component ODDRX1F
	port (
		D0 : in std_logic;
		D1 : in std_logic;
		Q : out std_logic;
		SCLK : in std_logic;
		RST : in std_logic
	); end component;
begin
	usb_pull_dp <= (others => '0');
	usb_pull_dn <= (others => '0');

	ddr_sdramclk: ODDRX1F port map (D0=>'0', D1=>'1', Q=>sdram_clk, SCLK=>clk_sys, RST=>'0');

	reset_n <= '1';
	amiga_reset_n <= button(0);

	joya_i <= '1' & joya;
	joyb_i <= '1' & joyb;
	joyc_i <= (others=>'1');
	joyd_i <= (others=>'1');

	auxpll : entity work.ecp5pll
	generic map(
		in_hz => natural(base_frequency),
		out0_hz => natural(60e6),
		out0_tol_hz => 1e4
	)
	port map (
		clk_i => clk,
		clk_o => auxclks
	);

	clk_usb <= auxclks(0);

	virtual_top : COMPONENT minimig_virtual_top
	generic map
		(
			hostonly => 0,
			debug => 0,
			spimux => 0,
			haveiec => 0,
			havereconfig => 0,
			havertg => 0,
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
	PORT map
		(
			CLK_IN => clk,
			CLK_USB_IN => clk_usb,
			CLK_114 => clk_sys,
			CLK_28 => clk_pixel,
			CLK_142 => clk_tmds,
			PLL_LOCKED => pll_locked,

			RESET_N => reset_n,
			LED_POWER => led_i(4),
			LED_DISK => led_i(3),
			LED_USB => led_i(1 downto 0),
			LED_AUX => led_i(2),

			MENU_BUTTON => button(1),

			CTRL_TX => open,
			CTRL_RX => '0',

			AMIGA_TX => usb_tx,
			AMIGA_RX => usb_rx,

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

			SDRAM_DQ => sdram_dq,
			SDRAM_A => sdram_a,
			SDRAM_DQML => sdram_dqm(0),
			SDRAM_DQMH => sdram_dqm(1),
			SDRAM_nWE => sdram_wen,
			SDRAM_nCAS => sdram_casn,
			SDRAM_nRAS => sdram_rasn,
			SDRAM_nCS => sdram_csn,
			SDRAM_BA => sdram_ba,
--			SDRAM_CLK => sdram_clk,
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
			AMIGA_KEY => (others=>'-'),
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

	led_r <= led_i(4);
	led_g <= led_i(3);
	led_y <= '0';

	process (clk_pixel)
	begin
		if rising_edge(clk_pixel) then
			if audio_tick = '1' then
				led <= (others => '0');
				led_counter <= std_logic_vector(unsigned(led_counter) + 1);

				if unsigned(led_counter) = 0 then
					led <= led_i;
				end if;
			end if;
		end if;
	end process;

	-- Instantiate HDMI out:
	genvideo: block
		component hdmi
		generic (
			IT_CONTENT : std_logic := '1';
			DVI_OUTPUT : std_logic := '0';
			VIDEO_RATE : integer := 28571400;
			AUDIO_RATE : integer := 44100;
			AUDIO_BIT_WIDTH : integer := 16;
			VENDOR_NAME : std_logic_vector(8*8-1 downto 0) := x"4100000000000000";  -- "A" + zero padding
			PRODUCT_DESCRIPTION : std_logic_vector(8*16-1 downto 0) := x"41000000000000000000000000000000"; -- "FPGA" + padding
			SOURCE_DEVICE_INFORMATION : std_logic_vector(7 downto 0) := x"09"
		);
		port (
			clk_pixel_x5 : in  std_logic;
			clk_pixel    : in  std_logic;
			reset        : in  std_logic;

			pal_mode    : in  std_logic;
			long_frame  : in  std_logic;
			interlace   : in  std_logic;
			screen_mode : in  std_logic_vector(1 downto 0);

			vsync_in : in  std_logic;
			hsync_in : in  std_logic;

			offset_x : in  unsigned(7 downto 0);
			offset_y : in  unsigned(6 downto 0);

			rgb : in  std_logic_vector(23 downto 0);

			audio_sample_word_0 : in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_word_1 : in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_en     : out std_logic;

			tmds       : out std_logic_vector(2 downto 0);
			tmds_clock : out std_logic
		);
		end component;

		signal vreset : std_logic_vector(1 downto 0) := "11";

		signal tmds_clock : std_logic;
		signal tmds : std_logic_vector(2 downto 0);
		signal rgb : std_logic_vector(23 downto 0);

		signal offset_x : unsigned(7 downto 0);
		signal offset_y : unsigned(6 downto 0);
	begin
		process (clk_pixel, pll_locked)
		begin
			if pll_locked = '0' then
				vreset <= "11";
			elsif rising_edge(clk_pixel) then
				vreset <= vreset(0) & '0';
			end if;
		end process;

		offset_x <= unsigned(video_xoffset(7 downto 0));
		offset_y <= unsigned(video_yoffset(6 downto 0));

		hdmi_inst : component hdmi
		generic map (
			VIDEO_RATE => 28571400,
			AUDIO_RATE => 48000,
			AUDIO_BIT_WIDTH => 16
		)
		port map (
			clk_pixel_x5 => clk_tmds,
			clk_pixel => clk_pixel,
			reset => vreset(1),

			pal_mode => display_pal,
			long_frame => long_frame,
			interlace => interlace,
			screen_mode => "00",

			vsync_in => dvi_vsync,
			hsync_in => dvi_hsync,

			offset_x => offset_x,
			offset_y => offset_y,

			rgb => rgb,

			audio_sample_word_0 => audio_l,
			audio_sample_word_1 => audio_r,
			audio_sample_en => open,

			tmds => tmds,
			tmds_clock => tmds_clock
		);

		rgb <= dvi_red & dvi_green & dvi_blue;
		gpdi_dp <= tmds_clock & tmds;
	end block;
end architecture;
-- vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
