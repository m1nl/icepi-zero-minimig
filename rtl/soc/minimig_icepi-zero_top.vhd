library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;
use work.board_config.all;

entity minimig_icepizero_top is
port(
	clk : in std_logic; -- 25MHz

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

	gpio : inout std_logic_vector(27 downto 0);

	gpdi_dp : out std_logic_vector(3 downto 0)	-- Quasi-differential output for digital video.
	-- gpdi_dn : out std_logic_vector(3 downto 0)  -- Don't declare the _n pins - the _p pins are declared as
	                                               -- LVCMOS33D so their conjugate pairs will be used automatically.
);
end entity;

architecture rtl of minimig_icepizero_top is
	-- Internal signals

	signal ps2k_dat_in : std_logic;
	signal ps2k_dat_out : std_logic;
	signal ps2k_clk_in : std_logic;
	signal ps2k_clk_out : std_logic;
	signal ps2m_dat_in : std_logic;
	signal ps2m_dat_out : std_logic;
	signal ps2m_clk_in : std_logic;
	signal ps2m_clk_out : std_logic;

	signal audio_l : std_logic_vector(15 downto 0);
	signal audio_r : std_logic_vector(15 downto 0);
	signal audio_tick : std_logic;

	signal clk_sys : std_logic;
	signal clk_pixel : std_logic;
	signal clk_tmds : std_logic;
	signal clk_usb : std_logic;

	signal dvi_red : std_logic_vector(7 downto 0);
	signal dvi_green : std_logic_vector(7 downto 0);
	signal dvi_blue : std_logic_vector(7 downto 0);
	signal dvi_hsync : std_logic := '0';
	signal dvi_vsync : std_logic := '0';
	signal dvi_window : std_logic;
	signal dvi_pixel : std_logic;

	signal reset_n : std_logic;

	signal amiga_txd : std_logic;
	signal amiga_rxd : std_logic;

	signal joya : std_logic_vector(6 downto 0);
	signal joyb : std_logic_vector(6 downto 0);
	signal joyc : std_logic_vector(6 downto 0);
	signal joyd : std_logic_vector(6 downto 0);

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

	reset_n <= button(0);

	ps2k_clk_in <= '1';
	ps2k_dat_in <= '1';
	ps2m_clk_in <= '1';
	ps2m_dat_in <= '1';

	joya <= (others=>'1');
	joyb <= (others=>'1');
	joyc <= (others=>'1');
	joyd <= (others=>'1');

	amiga_rxd <= '1';

	auxpll : entity work.ecp5pll
	generic map(
		in_hz => natural(base_frequency),
		out0_hz => natural(60e6), out0_tol_hz => 1e4
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
			havec2p => 0,
			havespirtc => 0,
			ram_64meg => 0,
			vga_width => 8,
			usethrottle => 0,
			havecart => 0,
			haveaga => 0,
			haventscswitch => 0
		)
	PORT map
		(
			CLK_IN => clk,
			CLK_USB_IN => clk_usb,
			CLK_114 => clk_sys,
			CLK_28 => clk_pixel,
			CLK_142 => clk_tmds,
			RESET_N => reset_n,
			LED_POWER => led_i(4),
			LED_DISK => led_i(3),
			LED_USB => led_i(1 downto 0),
			LED_AUX => led_i(2),
			MENU_BUTTON => button(1),
			CTRL_TX => usb_tx,
			CTRL_RX => usb_rx,
			AMIGA_TX => amiga_txd,
			AMIGA_RX => amiga_rxd,

			DVI_HS => dvi_hsync,
			DVI_VS => dvi_vsync,
			DVI_R => dvi_red,
			DVI_G => dvi_green,
			DVI_B => dvi_blue,
			DVI_STROBE => dvi_pixel,
			DVI_DE => dvi_window,

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

			PS2_DAT_I => ps2k_dat_in,
			PS2_CLK_I => ps2k_clk_in,
			PS2_MDAT_I => ps2m_dat_in,
			PS2_MCLK_I => ps2m_clk_in,

			PS2_DAT_O => ps2k_dat_out,
			PS2_CLK_O => ps2k_clk_out,
			PS2_MDAT_O => ps2m_dat_out,
			PS2_MCLK_O => ps2m_clk_out,

			AMIGA_RESET_N => '1',
			AMIGA_KEY => (others=>'-'),
			AMIGA_KEY_STB => '0',

			c64_keys => (others => '1'),

			JOYA => joya,
			JOYB => joyb,
			JOYC => joyc,
			JOYD => joyd,

			SD_MISO => sd_miso,
			SD_MOSI => sd_mosi,
			SD_CLK => sd_clk,
			SD_CS => sd_csn,
			SD_ACK => '1',

			usb_dp => usb_dp,
			usb_dn => usb_dn
		);

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
			screen      : in  std_logic_vector(1 downto 0);
			short_frame : in  std_logic;
			interlace   : in  std_logic;

			rgb : in  std_logic_vector(23 downto 0);

			audio_sample_word_0 : in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_word_1 : in  std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);
			audio_sample_en     : out std_logic;

			tmds       : out std_logic_vector(2 downto 0);
			tmds_clock : out std_logic
		); end component;

		component video_analyzer
		port (
			clk         : in  std_logic;
			hs          : in  std_logic;
			vs          : in  std_logic;
			screen      : in  std_logic_vector(1 downto 0);
			pal         : out std_logic;
			short_frame : out std_logic;
			interlace   : out std_logic;
			vreset      : out std_logic
		); end component;

		signal vreset : std_logic;
		signal vpal : std_logic;
		signal interlace : std_logic;
		signal short_frame : std_logic;
		signal screen : std_logic_vector(1 downto 0);
		signal tmds_clock : std_logic;
		signal tmds : std_logic_vector(2 downto 0);
		signal rgb : std_logic_vector(23 downto 0);

	begin
		video_analyzer_inst : component video_analyzer
		port map (
			clk => clk_pixel,
			hs => dvi_hsync,
			vs => dvi_vsync,
			pal => vpal,
			short_frame => short_frame,
			screen => screen,
			interlace => interlace,
			vreset => vreset
		);
		screen <= (others => '0');

		hdmi_inst : component hdmi
		generic map (
			VIDEO_RATE => 28571400,
			AUDIO_RATE => 48000,
			AUDIO_BIT_WIDTH => 16
		)
		port map (
			clk_pixel_x5 => clk_tmds,
			clk_pixel => clk_pixel,
			reset => vreset,

			pal_mode => vpal,
			short_frame => short_frame,
			screen => screen,
			interlace => interlace,

			rgb => rgb,

			audio_sample_word_0 => audio_l,
			audio_sample_word_1 => audio_r,
			audio_sample_en => open,

			tmds => tmds,
			tmds_clock => tmds_clock
		);

		rgb <= dvi_red & dvi_green & dvi_blue;
		gpdi_dp <= tmds_clock & tmds;

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

	end block;
end architecture;
-- vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
