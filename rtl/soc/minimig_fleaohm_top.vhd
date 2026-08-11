library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;
use work.board_config.all;

entity minimig_fleaohm_top is
port(
	-- System clock and reset
	clk	: in	std_logic;	-- 25MHz clock input from external xtal oscillator.
	reset_n	: in	std_logic;	-- master reset input from reset header.

	-- On-board user buttons and status LED
	n_led1	: out	std_logic;

	-- Digital video out
	lvds_dp : out std_logic_vector(3 downto 0);	-- Quasi-differential output for digital video.

	-- USB Slave (FT230x) debug interface
	slave_tx_o	: out	std_logic;
	slave_rx_i	: in	std_logic;
	slave_cts_i	: in	std_logic;	-- Receives signal from #RTS pin on FT230x, where applicable.

	-- SDRAM interface (For use with 16Mx16bit or 32Mx16bit SDR DRAM, depending on version)
	sdram_clk	: out	std_logic;	-- clock to SDRAM
	sdram_cke	: out	std_logic;	-- clock to SDRAM
	sdram_rasn	: out	std_logic;	-- SDRAM RAS
	sdram_casn	: out	std_logic;	-- SDRAM CAS
	sdram_wen	: out	std_logic;	-- SDRAM write-enable
	sdram_ba	: out	std_logic_vector(1 downto 0);	-- SDRAM bank-address
	sdram_dqm	: out	std_logic_vector(1 downto 0);
	sdram_a		: out	std_logic_vector(12 downto 0);	-- SDRAM address bus
	sdram_dq	: inout	std_logic_vector(15 downto 0);	-- data bus to/from SDRAM
	sdram_csn	: out	std_logic;

	-- GPIO Header (RasPi compatible GPIO format)
	GPIO_2	: in	std_logic;
	GPIO_3	: out	std_logic;
	GPIO_4	: in	std_logic;
	GPIO_5	: inout	std_logic;
	GPIO_6	: inout	std_logic;
	GPIO_7	: in	std_logic;
	GPIO_8	: in	std_logic;
	GPIO_9	: in	std_logic;
	GPIO_10	: in	std_logic;
	GPIO_11	: in	std_logic;
	GPIO_12	: out	std_logic;
	GPIO_13	: out	std_logic;
	GPIO_14	: inout	std_logic;
	GPIO_15	: in	std_logic;
	GPIO_16	: in	std_logic;

	GPIO_17	: in	std_logic;
	GPIO_18	: in	std_logic;
	GPIO_19	: out	std_logic;
	GPIO_20	: in	std_logic;
	GPIO_21	: in	std_logic;
	GPIO_22	: in	std_logic;
	GPIO_23	: in	std_logic;
	GPIO_24	: in	std_logic;
	GPIO_25	: inout	std_logic;
	GPIO_26	: inout	std_logic;
	GPIO_27	: inout	std_logic;
	GPIO_IDSD	: inout	std_logic;
	GPIO_IDSC	: inout	std_logic;

	-- Sigma Delta ADC ('Enhanced' Ohm-specific GPIO functionality)
	-- NOTE: Must comment out GPIO_5, GPIO_7, GPIO_10 AND GPIO_24 as instructed in the pin constraints file (.LPF) in order to use
	--ADC0_input	: in		std_logic;
	--ADC0_error	: buffer	std_logic;
	--ADC1_input	: in		std_logic;
	--ADC1_error	: buffer	std_logic;
	--ADC2_input	: in		std_logic;
	--ADC2_error	: buffer	std_logic;
	--ADC3_input	: in		std_logic;
	--ADC3_error	: buffer	std_logic;

	-- SD/MMC Interface (Support either SPI or nibble-mode)
	mmc_dat1	: in	std_logic;
	mmc_dat2	: in	std_logic;
	mmc_n_cs	: out	std_logic;
	mmc_clk	: out	std_logic;
	mmc_mosi	: out	std_logic;
	mmc_miso	: in	std_logic;

	usb_dp	:	inout std_logic_vector(1 downto 0);
	usb_dn	:	inout std_logic_vector(1 downto 0);
	usb_pull	:	out std_logic
);
end entity;

architecture rtl of minimig_fleaohm_top is
-- SPI signals
	signal led_power	:	std_logic;

-- Video
	signal dvi_red	:	std_logic_vector(7 downto 0);
	signal dvi_green	:	std_logic_vector(7 downto 0);
	signal dvi_blue	:	std_logic_vector(7 downto 0);
	signal dvi_hsync	:	std_logic := '0';
	signal dvi_vsync	:	std_logic := '0';
	signal dvi_window	:	std_logic;
	signal dvi_pixel	:	std_logic;
	signal blank	:	std_logic := '0';
	signal videoblank	:	std_logic;
	signal vbl	:	std_logic;

	signal display_pal	:	std_logic;
	signal long_frame	:	std_logic;
	signal interlace	:	std_logic;

	signal video_xoffset	:	std_logic_vector(7 downto 0);
	signal video_yoffset	:	std_logic_vector(7 downto 0);

-- Audio
	signal audio_l	:	std_logic_vector(15 downto 0);
	signal audio_r	:	std_logic_vector(15 downto 0);

-- IO
	signal n_joy1	:	std_logic_vector(6 downto 0);
	signal n_joy2	:	std_logic_vector(6 downto 0);

-- System clocks

	signal clk_sys	:	std_logic;
	signal clk_usb	:	std_logic;
	signal clk_pixel	:	std_logic;
	signal clk_tmds	:	std_logic;
	signal auxclks	:	std_logic_vector(3 downto 0);

	signal pll_locked	:	std_logic;

	signal VTEMP_DAC	:	std_logic_vector(4 downto 0);
	signal audio_data	:	std_logic_vector(17 downto 0);
	signal convert_audio_data	:	std_logic_vector(17 downto 0);

	component ODDRX1F
	port (
		D0	:	in std_logic;
		D1	:	in std_logic;
		Q	:	out std_logic;
		SCLK	:	in std_logic;
		RST	:	in std_logic
	);
	end component;
begin

ddr_sdramclk: ODDRX1F port map (D0=>'0', D1=>'1', Q=>sdram_clk, SCLK=>clk_sys, RST=>'0');

-- Joystick bits(5-0) = fire2,fire,right,left,down,up mapped to GPIO header
n_joy1(3) <= GPIO_4 ; -- up
n_joy1(2) <= GPIO_7 ; -- down
n_joy1(1) <= GPIO_8 ; -- left
n_joy1(0) <= GPIO_9 ; -- right
n_joy1(4) <= GPIO_10 ; -- fire
n_joy1(5) <= GPIO_11 ; -- fire2

n_joy2(3) <= GPIO_15 ; -- up
n_joy2(2) <= GPIO_17 ; -- down
n_joy2(1) <= GPIO_18 ; -- left
n_joy2(0) <= GPIO_22 ; -- right
n_joy2(4) <= GPIO_23 ; -- fire
n_joy2(5) <= GPIO_24 ; -- fire2

-- Pull-down both USB lines
usb_pull <= '0';

-- SPI
n_led1 <= NOT led_power;

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
generic map (
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
	haveauxspi => 0,
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
	RESET_N => '1',

	LED_POWER => led_power,
	LED_DISK => open,
	LED_USB => open,
	LED_AUX => open,

	MENU_BUTTON => GPIO_2,

	CTRL_TX => slave_tx_o,
	CTRL_RX => slave_rx_i,

	AMIGA_TX => GPIO_12,
	AMIGA_RX => GPIO_16,

	AMIGA_RESET_N => reset_n,
	AMIGA_KEY => (others=>'-'),
	AMIGA_KEY_STB => '0',

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
--	SDRAM_CLK => sdram_clk,
	SDRAM_CKE => sdram_cke,

	AUDIO_PAULA_L => audio_l,
	AUDIO_PAULA_R => audio_r,
	AUDIO_TICK => open,

	PS2_DAT_I => '1',
	PS2_CLK_I => '1',
	PS2_MDAT_I => '1',
	PS2_MCLK_I => '1',

	PS2_DAT_O => open,
	PS2_CLK_O => open,
	PS2_MDAT_O => open,
	PS2_MCLK_O => open,

	JOYA => n_joy1,
	JOYB => n_joy2,
	JOYC => (others => '1'),
	JOYD => (others => '1'),

	SD_MISO => mmc_miso,
	SD_MOSI => mmc_mosi,
	SD_CLK => mmc_clk,
	SD_CS => mmc_n_cs,
	SD_ACK => '1',

	C64_KEYS => (others => '1'),

	USB_DP => usb_dp,
	USB_DN => usb_dn,

	AUX_SPI_CSN => open,
	AUX_SPI_CLK => open,
	AUX_SPI_MOSI => open
);

-- Instantiate HDMI out:
genvideo: block
	component hdmi
	generic (
		IT_CONTENT : std_logic := '1';
		DVI_OUTPUT : std_logic := '0';
		VIDEO_RATE : integer := 28571400;
		AUDIO_RATE : integer := 48000;
		AUDIO_BIT_WIDTH : integer := 16;
		VENDOR_NAME : std_logic_vector(8*8-1 downto 0) := x"4100000000000000";  -- "A" + zero padding
		PRODUCT_DESCRIPTION : std_logic_vector(8*16-1 downto 0) := x"41000000000000000000000000000000"; -- "A" + padding
		SOURCE_DEVICE_INFORMATION : std_logic_vector(7 downto 0) := x"09"
	);
	port (
		clk_pixel_x5 : in  std_logic;
		clk_pixel    : in  std_logic;
		reset        : in  std_logic;

		pal_mode    : in  std_logic;
		long_frame  : in  std_logic;
		interlace   : in  std_logic;

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
	lvds_dp <= tmds_clock & tmds;
end block;
end architecture;
