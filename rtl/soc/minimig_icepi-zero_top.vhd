library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;

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

	gpio : inout std_logic_vector(27 downto 0);

	gpdi_dp : out std_logic_vector(3 downto 0)	-- Quasi-differential output for digital video.
	-- gpdi_dn : out std_logic_vector(3 downto 0)  -- Don't declare the _n pins - the _p pins are declared as
	                                               -- LVCMOS33D so their conjugate pairs will be used automatically.
);
end entity;

architecture rtl of minimig_icepizero_top is

	alias sigma_l is gpio(0);
	alias sigma_r is gpio(1);

	-- Internal signals

	signal ps2k_dat_in : std_logic;
	signal ps2k_dat_out : std_logic;
	signal ps2k_clk_in : std_logic;
	signal ps2k_clk_out : std_logic;
	signal ps2m_dat_in : std_logic;
	signal ps2m_dat_out : std_logic;
	signal ps2m_clk_in : std_logic;
	signal ps2m_clk_out : std_logic;

	signal audio_l_msb : std_logic;
	signal audio_l : std_logic_vector(23 downto 0);
	signal audio_r_msb : std_logic;
	signal audio_r : std_logic_vector(23 downto 0);

	signal clk_sys : std_logic;
	signal dvi_red     : std_logic_vector(7 downto 0);
	signal dvi_green   : std_logic_vector(7 downto 0);
	signal dvi_blue    : std_logic_vector(7 downto 0);
	signal dvi_hsync   : std_logic := '0';
	signal dvi_vsync   : std_logic := '0';
	signal dvi_window : std_logic;
	signal dvi_pixel : std_logic;

	signal reset_n : std_logic;

	signal amiga_txd : std_logic;
	signal amiga_rxd : std_logic;
	
	signal joya : std_logic_vector(6 downto 0);
	signal joyb : std_logic_vector(6 downto 0);
	signal joyc : std_logic_vector(6 downto 0);
	signal joyd : std_logic_vector(6 downto 0);
	

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

begin

	ddr_sdramclk:   ODDRX1F port map (D0=>'0',   D1=>'1',   Q=>sdram_clk, SCLK=>clk_sys, RST=>'0');

	reset_n <= button(0);

	ps2k_clk_in <= '1';
	ps2k_dat_in <= '1';
	ps2m_clk_in <= '1';
	ps2m_dat_in <= '1';
	
	joya<=(others=>'1');
	joyb<=(others=>'1');
	joyc<=(others=>'1');
	joyd<=(others=>'1');

	amiga_rxd <= '1';

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
			CLK_IN => clk,
			CLK_114 => clk_sys,
			RESET_N => reset_n,
			LED_POWER => led(4),
			LED_DISK => led(3),
			LED_USB => led(2 downto 1),
			MENU_BUTTON => button(1),
			CTRL_TX => usb_tx,
			CTRL_RX => usb_rx,
			AMIGA_TX => amiga_txd,
			AMIGA_RX => amiga_rxd,

			DVI_HS => dvi_hsync,
			DVI_VS => dvi_vsync,
			DVI_R	=> dvi_red,
			DVI_G	=> dvi_green,
			DVI_B	=> dvi_blue,
			DVI_STROBE => dvi_pixel,
			DVI_DE => dvi_window,
		
			SDRAM_DQ	=> sdram_dq,
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
			
			SD_MISO => sd_miso,
			SD_MOSI => sd_mosi,
			SD_CLK => sd_clk,
			SD_CS => sd_csn,
			SD_ACK => '1',
			
			usb_dp => usb_dp,
			usb_dn => usb_dn
		);

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

		process(clk_sys) begin

			-- Clock multiplexing:  Video timings are derived from the 114Hz clock.
			-- dvi_pixel is high for one cycle at the start of each pixel, so by counting
			-- the number of clocks between each pulse we can determine the pixel clock and
			-- thus the appropriate TMDS clock to use.
			-- We will see a pcnt value of 1 for 56MHz modes and 3 for 28MHz modes
			-- Since we don't seem to be able to cascade DCSCs, we're stuck with just two
			-- TDMS clocks, which will be 5*28MHz and 5*56Mhz.
			if rising_edge(clk_sys) then
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
			clk_i => clk_sys,
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

	end block;

	audioblock : block
		COMPONENT hybrid_pwm_sd
		PORT
		(
			clk		:	 IN STD_LOGIC;
			terminate : in std_logic:='0';
			d_l		:	 IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			q_l		:	 OUT STD_LOGIC;
			d_r		:	 IN STD_LOGIC_VECTOR(15 DOWNTO 0);
			q_r		:	 OUT STD_LOGIC
		);
		END COMPONENT;
	begin
	
		audiosd : COMPONENT hybrid_pwm_sd
		PORT map
		(
			clk => clk_sys,
			terminate => '0',
			d_l(15) => not audio_l(23),
			d_l(14 downto 0) => audio_l(22 downto 8),
			q_l => sigma_l,
			d_r(15) => not audio_r(23),
			d_r(14 downto 0) => audio_r(22 downto 8),
			q_r => sigma_r
		);
	end block;

end architecture;

