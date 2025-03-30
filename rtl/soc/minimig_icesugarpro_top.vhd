-- PMOD pin numbers for icesugarpro

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package icesugarpro_pmod_pkg is
	-- Pin numberings for SD card PMOD
	constant PMOD_SD_CS : integer := 0;
	constant PMOD_SD_MOSI : integer := 1;
	constant PMOD_SD_MISO : integer := 2;
	constant PMOD_SD_CLK : integer := 3;
	constant PMOD_SD_DAT1 : integer := 4;
	constant PMOD_SD_DAT2 : integer := 5;
	constant PMOD_SD_CD : integer := 6;
	constant PMOD_SD_WP : integer := 7;
	
	-- Pin numberings for PS/2 PMOD
	constant PMOD_PS2_KDAT : integer := 0; 
	constant PMOD_PS2_MDAT : integer := 1;
	constant PMOD_PS2_KCLK : integer := 2;
	constant PMOD_PS2_MCLK : integer := 3;
	
	-- Pin numberings for I2S PMOD
	constant PMOD_I2S_DA_MCLK : integer := 0;
	constant PMOD_I2S_DA_LRCK : integer := 1;
	constant PMOD_I2S_DA_SCLK : integer := 2;
	constant PMOD_I2S_DA_SDIN : integer := 3;
	constant PMOD_I2S_AD_MCLK : integer := 4;
	constant PMOD_I2S_AD_LRCK : integer := 5;
	constant PMOD_I2S_AD_SCLK : integer := 6;
	constant PMOD_I2S_AD_SDOUT : integer := 7;
	
end package;

----------------------------
-- icesugarpro Top level for MINIMIG
-- http://github.com/emard
----------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

library ecp5u;
use ecp5u.components.all;

library work;
use work.icesugarpro_pmod_pkg.all;
use work.minimig_virtual_pkg.all;

entity minimig_icesugarpro_top is
generic
(
  C_programn: boolean := false; -- hold BTN0 to pull PROGRAMN low
  C_spdif:    boolean := false  -- SPDIF audio, may cause synthesis problems if enabled on 85F
);
port
(
	-- JTAG "pins"
	TDO : out std_logic;
	TDI : in std_logic;
	TCK : in std_logic;
	TMS : in std_logic;
	
	clk_25MHz: in std_logic;  -- main clock input from 25MHz clock source

	-- UART0 (FTDI USB slave serial)
	ftdi_txd: out   std_logic;
	ftdi_rxd: in    std_logic;
-- FTDI additional signaling
--  ftdi_ndsr: inout  std_logic;
--  ftdi_nrts: inout  std_logic;
--  ftdi_txden: inout std_logic;

  -- UART1 (WiFi serial)
--  wifi_rxd: out   std_logic;
--  wifi_txd: in    std_logic;
  -- WiFi additional signaling
--  wifi_en: inout  std_logic := 'Z'; -- '0' will disable wifi by default
--  wifi_gpio0, wifi_gpio2, wifi_gpio16, wifi_gpio17: inout std_logic := 'Z';

  -- ADC MAX11123
--  adc_csn, adc_sclk, adc_mosi: out std_logic;
--  adc_miso: in std_logic;

	-- SDRAM
	sdram_clk: out std_logic;
	sdram_cke: out std_logic;
	sdram_cs_n: out std_logic;
	sdram_ras_n: out std_logic;
	sdram_cas_n: out std_logic;
	sdram_we_n: out std_logic;
	sdram_a: out std_logic_vector (12 downto 0);
	sdram_ba: out std_logic_vector(1 downto 0);
	sdram_dm: out std_logic_vector(1 downto 0);
	sdram_dq: inout std_logic_vector (15 downto 0);

	-- Onboard blinky
	led_red : out std_logic;
	led_green : out std_logic;
	led_blue : out std_logic;
  
--  led: out std_logic_vector(7 downto 0);

--  btn: in std_logic_vector(6 downto 0);
--  sw: in std_logic_vector(3 downto 0);
  
	gpdi_dp : out std_logic_vector(3 downto 0);	-- Quasi-differential output for digital video.
	gpdi_dn : out std_logic_vector(3 downto 0);

	P2_pmod_high : inout std_logic_vector(7 downto 0);
	P2_gpio : inout std_logic_vector(3 downto 0);
	P2_pmod_low : inout std_logic_vector(7 downto 0);
	P3_pmod_high : inout std_logic_vector(7 downto 0);
	P3_gpio : inout std_logic_vector(3 downto 0);
	P3_pmod_low : inout std_logic_vector(7 downto 0);
	P4_pmod_low : inout std_logic_vector(7 downto 0);
	P4_gpio : inout std_logic_vector(3 downto 0);
	P4_gpio2 : inout std_logic_vector(5 downto 0); -- Two pins not connected, so called GPIO instead of PMOD.
	P5_pmod_high : inout std_logic_vector(7 downto 0); -- Pins shared with breakout board's DAPLink.
	P5_gpio : inout std_logic_vector(3 downto 0);
	P5_pmod_low : inout std_logic_vector(7 downto 0);
	P6_pmod_high : inout std_logic_vector(7 downto 0);
	P6_gpio : inout std_logic_vector(3 downto 0);
	P6_pmod_low : inout std_logic_vector(7 downto 0)
);
end;

architecture struct of minimig_icesugarpro_top is
  -- FLEA OHM aliasing
  -- keyboard
--  alias ps2_clk1 : std_logic is usb_fpga_bd_dp;
--  alias ps2_data1 : std_logic is usb_fpga_bd_dn;
  --alias ps2_clk1 : std_logic is gp(0);
  --alias ps2_data1 : std_logic is gn(0);
  --signal ps2_clk1 : std_logic := '1';
  --signal ps2_data1 : std_logic := '1';
--  signal PS_enable: std_logic; -- dummy on ulx3s v1.7.x
  -- mouse
--  alias ps2_clk2 : std_logic is gp(1);
--  alias ps2_data2 : std_logic is gn(1);
  --signal ps2_clk2 : std_logic := '1';
  --signal ps2_data2 : std_logic := '1';

-- PS/2 keyboard and mouse
	constant ps2_pmod_offset : integer := 4; -- Set this to 4 to use the bottom row of pins, 0 to use the top row.
	alias ps2_pmod : std_logic_vector(7 downto 0) is P6_pmod_high;

	alias ps2_clk1 : std_logic is P6_pmod_high(PMOD_PS2_KCLK+ps2_pmod_offset);
	alias ps2_data1 : std_logic is ps2_pmod(PMOD_PS2_KDAT+ps2_pmod_offset);
	alias ps2_clk2 : std_logic is ps2_pmod(PMOD_PS2_MCLK+ps2_pmod_offset);
	alias ps2_data2 : std_logic is ps2_pmod(PMOD_PS2_MDAT+ps2_pmod_offset);

	-- Audio
	alias sigmadelta_pmod is P2_pmod_high;
	alias i2s_pmod is P2_pmod_low;

	-- SD Card
	constant use_pmod_sdcard : boolean := true; -- Set to false to use the built-in (but awkwardly-placed) micro-SD slot
	alias sdcard_pmod is P5_pmod_low;

	-- VGA
	alias vga_pmod_high is P3_pmod_high;
	alias vga_pmod_low is P3_pmod_low;


  alias sys_clock: std_logic is clk_25MHz;
  alias slave_rx_i: std_logic is ftdi_txd;
  alias slave_tx_o: std_logic is ftdi_rxd;
	
  signal sys_reset: std_logic;

  alias mmc_n_cs: std_logic is sdcard_pmod(PMOD_SD_CS);
  alias mmc_clk: std_logic is sdcard_pmod(PMOD_SD_CLK);
  alias mmc_mosi: std_logic is sdcard_pmod(PMOD_SD_MOSI);
  alias mmc_miso: std_logic is sdcard_pmod(PMOD_SD_MISO);
  -- END FLEA OHM ALIASING

  signal sysclk : std_logic;

--  signal clk_usb : std_logic; -- 6MHz or 48MHz
   
  signal ps2k_clk_in : std_logic;
  signal ps2k_clk_out : std_logic;
  signal ps2k_dat_in : std_logic;
  signal ps2k_dat_out : std_logic;	
  signal ps2m_clk_in : std_logic;
  signal ps2m_clk_out : std_logic;
  signal ps2m_dat_in : std_logic;
  signal ps2m_dat_out : std_logic;	
 
	signal joya : std_logic_vector(6 downto 0);
	signal joyb : std_logic_vector(6 downto 0);
	signal joyc : std_logic_vector(6 downto 0);
	signal joyd : std_logic_vector(6 downto 0);
	
  signal vga_red     : std_logic_vector(3 downto 0);
  signal vga_green   : std_logic_vector(3 downto 0);
  signal vga_blue    : std_logic_vector(3 downto 0);
  signal vga_hsync   : std_logic := '0';
  signal vga_vsync   : std_logic := '0';
  signal vga_window : std_logic;
  signal vga_pixel : std_logic;
  signal dvi_red     : std_logic_vector(7 downto 0);
  signal dvi_green   : std_logic_vector(7 downto 0);
  signal dvi_blue    : std_logic_vector(7 downto 0);
  signal dvi_hsync   : std_logic := '0';
  signal dvi_vsync   : std_logic := '0';
  signal dvi_window : std_logic;
  signal dvi_pixel : std_logic;
  signal blank   : std_logic := '0';
  signal videoblank: std_logic;  
 
  signal temp_we : std_logic := '0';
  signal diskoff : std_logic;
	
  signal pwm_accumulator : std_logic_vector(8 downto 0);
	
  -- signal clk_vga   : std_logic := '0';
  signal n_15khz   : std_logic := '1';
	
  constant cnt_div: integer:=617;                  -- Countervalue for 48khz Audio Enable,  567 for 25MHz PCLK
  signal   cnt:     integer range 0 to cnt_div-1; 
  signal   ce:      std_logic;

  signal   audio_l : std_logic_vector(23 downto 0);
  signal   audio_r : std_logic_vector(23 downto 0);

  signal amiga_rxd : std_logic;
  signal amiga_txd : std_logic;
	
begin
  sys_reset <= '1'; -- btn(0);

  -- Video output horizontal scanrate select 15/30kHz select
  n_15khz <= '1'; -- sw(0) ; -- Default is '1' for 30kHz video out. set to '0' for 15kHz video.

  -- PS/2 Keyboard and Mouse definitions
  ps2k_dat_in<=PS2_data1;
  PS2_data1 <= '0' when ps2k_dat_out='0' else 'Z';
  ps2k_clk_in<=PS2_clk1;
  PS2_clk1 <= '0' when ps2k_clk_out='0' else 'Z';	
--  usb_fpga_pu_dp <= '1';
--  usb_fpga_pu_dn <= '1';

  ps2m_dat_in<=PS2_data2;
  PS2_data2 <= '0' when ps2m_dat_out='0' else 'Z';
  ps2m_clk_in<=PS2_clk2;
  PS2_clk2 <= '0' when ps2m_clk_out='0' else 'Z';	 

joya<=(others=>'1');
joyb<=(others=>'1');
joyc<=(others=>'1');
joyd<=(others=>'1');


ddr_sdramclk:   ODDRX1F port map (D0=>'0',   D1=>'1',   Q=>sdram_clk, SCLK=>sysclk, RST=>'0');

	virtual_top : COMPONENT minimig_virtual_top
	generic map
		(
			hostonly => 0,
			debug => 0,
			spimux => 0,
			haveiec => 0,
			havereconfig => 0,
			havertg => 1,
			haveaudio => 0,
			havec2p => 0,
			havespirtc => 0,
			ram_64meg => 0,
			vga_width => 4,
			havecart => 0,
			haveaga => 0
		)
	PORT map
		(
			sys_tck => TCK,
			sys_tdo => TDO,
			sys_tdi => TDI,
			sys_tms => TMS,
			CLK_IN => clk_25Mhz,
			CLK_114 => sysclk,
			RESET_N => '1',
			LED_POWER => led_red,
			LED_DISK => led_green,
			MENU_BUTTON => '1',
			CTRL_TX => ftdi_txd,
			CTRL_RX => ftdi_rxd,
			AMIGA_TX => amiga_txd,
			AMIGA_RX => amiga_rxd,
			VGA_HS => vga_hsync,
			VGA_VS => vga_vsync,
			VGA_R	=> vga_red,
			VGA_G	=> vga_green,
			VGA_B	=> vga_blue,
			VGA_STROBE => vga_pixel,
			VGA_DE => vga_window,

			DVI_HS => dvi_hsync,
			DVI_VS => dvi_vsync,
			DVI_R	=> dvi_red,
			DVI_G	=> dvi_green,
			DVI_B	=> dvi_blue,
			DVI_STROBE => dvi_pixel,
			DVI_DE => dvi_window,
		
			SDRAM_DQ	=> sdram_dq,
			SDRAM_A => sdram_a,
			SDRAM_DQML => sdram_dm(0),
			SDRAM_DQMH => sdram_dm(1),
			SDRAM_nWE => sdram_we_n,
			SDRAM_nCAS => sdram_cas_n,
			SDRAM_nRAS => sdram_ras_n,
			SDRAM_nCS => sdram_cs_n,
			SDRAM_BA => sdram_ba,
--			SDRAM_CLK => sdram_clk,
			SDRAM_CKE => sdram_cke,

			AUDIO_L => audio_l,
			AUDIO_R => audio_r,
			
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
			
			SD_MISO => mmc_miso,
			SD_MOSI => mmc_mosi,
			SD_CLK => mmc_clk,
			SD_CS => mmc_n_cs,
			SD_ACK => '1'
		);

	genaudio: block
		signal i2s_mclk : std_logic;
		signal i2s_sclk : std_logic;
		signal i2s_lrclk : std_logic;
		signal i2s_sdata : std_logic;		
	begin

		i2s_inst : entity work.i2s_dac
		generic map (
			sysclk_frequency => 113,
			mclk_to_lrclk => 256,
			samplerate => 48000,
			samplewidth => 16
		)
		port map (
			reset_n => sys_reset,
			sysclk => sysclk,
			mclk => i2s_mclk,
			sclk => open, -- i2s_sclk,
			lrclk => i2s_lrclk,
			sdata => i2s_sdata,
			left_in => audio_l(23 downto 8),
			right_in => audio_r(23 downto 8)
		);
		i2s_sclk <= '1';
		i2s_pmod(PMOD_I2S_DA_MCLK)<=i2s_mclk;
		i2s_pmod(PMOD_I2S_DA_SCLK)<=i2s_sclk;
		i2s_pmod(PMOD_I2S_DA_LRCK)<=i2s_lrclk;
		i2s_pmod(PMOD_I2S_DA_SDIN)<=i2s_sdata;
	end block;


	-- Instantiate DVI out:
	genvideo: block
		constant useddr : integer := 1;
		
		component dvi
		generic ( DDR_ENABLED : integer := useddr );
		port (
			pclk : in std_logic;
			tmds_clk : in std_logic; -- 10 times faster of pclk

			in_vga_red : in std_logic_vector(7 downto 0);
			in_vga_green : in std_logic_vector(7 downto 0);
			in_vga_blue : in std_logic_vector(7 downto 0);

			in_vga_vsync : in std_logic;
			in_vga_hsync : in std_logic;
			in_vga_pixel : in std_logic;
			in_vga_window : in std_logic;

			out_tmds_red : out std_logic_vector(useddr downto 0);
			out_tmds_green : out std_logic_vector(useddr downto 0);
			out_tmds_blue : out std_logic_vector(useddr downto 0);
			out_tmds_clk : out std_logic_vector(useddr downto 0);
			out_tmds_red_n : out std_logic_vector(useddr downto 0);
			out_tmds_green_n : out std_logic_vector(useddr downto 0);
			out_tmds_blue_n : out std_logic_vector(useddr downto 0);
			out_tmds_clk_n : out std_logic_vector(useddr downto 0)
		); end component;
		
		component ODDRX1F
		port (
			D0 : in std_logic;
			D1 : in std_logic;
			Q : out std_logic;
			SCLK : in std_logic;
			RST : in std_logic
		); end component;

		component DCSC
		generic (
			DCSMODE : string := "POS"
		);
		port (
			CLK1, CLK0 : in std_logic;
			SEL1, SEL0 : in std_logic;
			MODESEL : in std_logic;
			DCSOUT : out std_logic
		);
		end component;

		signal pcnt : unsigned(3 downto 0);
		signal clksel : std_logic_vector(1 downto 0);

		signal tmds_r : std_logic_vector(useddr downto 0);
		signal tmds_g : std_logic_vector(useddr downto 0);
		signal tmds_b : std_logic_vector(useddr downto 0);
		signal tmds_clk : std_logic_vector(useddr downto 0);
		signal tmds_r_n : std_logic_vector(useddr downto 0);
		signal tmds_g_n : std_logic_vector(useddr downto 0);
		signal tmds_b_n : std_logic_vector(useddr downto 0);
		signal tmds_clk_n : std_logic_vector(useddr downto 0);
		signal vidclks : std_logic_vector(3 downto 0);
		signal clk_video : std_logic;
		signal clk_tmds : std_logic;
		
		signal heartbeat_ctr : unsigned(27 downto 0);
		-- Video signal with blanking applied.
		signal br : std_logic_vector(7 downto 0);
		signal bg : std_logic_vector(7 downto 0);
		signal bb : std_logic_vector(7 downto 0);
		signal bhs : std_logic;
		signal bvs : std_logic;
		signal bpe : std_logic;
		signal bde : std_logic;
	begin
	
		--process(clk_tmds) begin
			--if rising_edge(clk_tmds) then
				--heartbeat_ctr <= heartbeat_ctr+1;
			--end if;
			--led_blue <= heartbeat_ctr(heartbeat_ctr'high);
		--end process;

		process(clk_video) begin

			-- Clock multiplexing:  Video timings are derived from the 114Hz clock.
			-- dvi_pixel is high for one cycle at the start of each pixel, so by counting
			-- the number of clocks between each pulse we can determine the pixel clock and
			-- thus the appropriate TMDS clock to use.
			-- We will see a pcnt value of 1 for 56MHz modes and 3 for 28MHz modes
			-- Since we don't seem to be able to cascade DCSCs, we're stuck with just two
			-- TDMS clocks, which will be 5*28MHz and 5*56Mhz.
			if rising_edge(sysclk) then
				if dvi_pixel='1' then
					pcnt <=(others => '0');
					clksel(0)<='0';
					case pcnt is 
						when X"1" => -- 56MHz pixel clock in RTG mode
							clksel(0) <= '0';
						when others => -- 28MHz pixel clock otherwise
							clksel(0) <= '1';
							null;
					end case;
				else
					pcnt<=pcnt+1;
				end if;
			end if;
			clksel(1) <= not clksel(0);
		end process;

		vidpll : entity work.ecp5pll
		generic map(
			in_hz => natural(114.2857e6),
			out0_hz => natural(142.857125e6),
			out1_hz => natural(285.71425e6),
			out2_hz => natural(114.2857e6)
		)
		port map (
			clk_i => sysclk,
			clk_o => vidclks
		);
		
		clkmux1 : component DCSC
		port map (
			CLK0 => vidclks(0),
			CLK1 => vidclks(1),
			SEL1 => clksel(1),
			SEL0 => clksel(0),
			MODESEL => '1',
			DCSOUT => clk_tmds
		);

		clk_video <= vidclks(2);
		
		-- Blank and buffer the video signal
		process(clk_video) begin
			if rising_edge(clk_video) then
				if dvi_window='1' then
					br<=dvi_red;
					bg<=dvi_green;
					bb<=dvi_blue;
				else
					br<=(others => '0');
					bg<=(others => '0');
					bb<=(others => '0');
				end if;
				bhs <= dvi_hsync;
				bvs <= dvi_vsync;
				bpe <= dvi_pixel;
				bde <= dvi_window;
			end if;
		end process;

		dvi_inst : component dvi
		generic map (
			DDR_ENABLED => useddr
		)
		port map (
			pclk => clk_video,
			tmds_clk => clk_tmds,

			in_vga_red => br,
			in_vga_green => bg,
			in_vga_blue => bb,

			in_vga_vsync => bvs,
			in_vga_hsync => bhs,
			in_vga_pixel => bpe,
			in_vga_window => bde,

			out_tmds_red => tmds_r,
			out_tmds_green => tmds_g,
			out_tmds_blue => tmds_b,
			out_tmds_clk => tmds_clk,
			out_tmds_red_n => tmds_r_n,
			out_tmds_green_n => tmds_g_n,
			out_tmds_blue_n => tmds_b_n,
			out_tmds_clk_n => tmds_clk_n
		);

		dviout_c : component ODDRX1F port map (D0 => tmds_clk(0), D1=>tmds_clk(1), Q => gpdi_dp(3), SCLK =>clk_tmds, RST=>'0');
		dviout_r : component ODDRX1F port map (D0 => tmds_r(0), D1=>tmds_r(1), Q => gpdi_dp(2), SCLK =>clk_tmds, RST=>'0');
		dviout_g : component ODDRX1F port map (D0 => tmds_g(0), D1=>tmds_g(1), Q => gpdi_dp(1), SCLK =>clk_tmds, RST=>'0');
		dviout_b : component ODDRX1F port map (D0 => tmds_b(0), D1=>tmds_b(1), Q => gpdi_dp(0), SCLK =>clk_tmds, RST=>'0');
		dviout_c_n : component ODDRX1F port map (D0 => tmds_clk_n(0), D1=>tmds_clk_n(1), Q => gpdi_dn(3), SCLK =>clk_tmds, RST=>'0');
		dviout_r_n : component ODDRX1F port map (D0 => tmds_r_n(0), D1=>tmds_r_n(1), Q => gpdi_dn(2), SCLK =>clk_tmds, RST=>'0');
		dviout_g_n : component ODDRX1F port map (D0 => tmds_g_n(0), D1=>tmds_g_n(1), Q => gpdi_dn(1), SCLK =>clk_tmds, RST=>'0');
		dviout_b_n : component ODDRX1F port map (D0 => tmds_b_n(0), D1=>tmds_b_n(1), Q => gpdi_dn(0), SCLK =>clk_tmds, RST=>'0');

		vga_pmod_high(7 downto 4)<=std_logic_vector(dvi_red(7 downto 4));
		vga_pmod_high(3 downto 0)<=std_logic_vector(dvi_blue(7 downto 4));
		vga_pmod_low(7 downto 4)<=std_logic_vector(dvi_green(7 downto 4));
		vga_pmod_low(3 downto 0)<="00"&dvi_vsync&dvi_hsync;

	end block;

end struct;
