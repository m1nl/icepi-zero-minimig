library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.minimig_virtual_pkg.all;

-- -----------------------------------------------------------------------

entity minimig_fleaohm_top is
 
	port(
	-- JTAG
	TDO : out std_logic;
	TDI : in std_logic;
	TMS : in std_logic;
	TCK : in std_logic;

	-- System clock and reset
	sys_clock		: in		std_logic;	-- 25MHz clock input from external xtal oscillator.
	sys_reset		: in		std_logic;	-- master reset input from reset header.

	-- On-board user buttons and status LED
	n_led1			: out		std_logic;
 
	-- Digital video out
	LVDS_Red		: out		std_logic_vector(0 downto 0);	-- 
	LVDS_Green		: out		std_logic_vector(0 downto 0);	-- 
	LVDS_Blue		: out		std_logic_vector(0 downto 0);	-- 
	LVDS_ck			: out		std_logic_vector(0 downto 0);	-- 
	
	-- USB Slave (FT230x) debug interface 
	slave_tx_o 		: out		std_logic;
	slave_rx_i 		: in		std_logic;
	slave_cts_i 	: in		std_logic;	-- Receives signal from #RTS pin on FT230x, where applicable.

	-- SDRAM interface (For use with 16Mx16bit or 32Mx16bit SDR DRAM, depending on version)
	Dram_Clk		: out		std_logic;	-- clock to SDRAM
	Dram_CKE		: out		std_logic;	-- clock to SDRAM
	Dram_n_Ras		: out		std_logic;	-- SDRAM RAS
	Dram_n_Cas		: out		std_logic;	-- SDRAM CAS
	Dram_n_We		: out		std_logic;	-- SDRAM write-enable
	Dram_BA			: out		std_logic_vector(1 downto 0);	-- SDRAM bank-address
	Dram_Addr		: out		std_logic_vector(12 downto 0);	-- SDRAM address bus
	Dram_Data		: inout		std_logic_vector(15 downto 0);	-- data bus to/from SDRAM
	Dram_n_cs		: out		std_logic;
	--Dram_dqm		: out		std_logic_vector(1 downto 0);
	Dram_DQMH		: out		std_logic;
	Dram_DQML		: out		std_logic;

    -- GPIO Header (RasPi compatible GPIO format)
	GPIO_2			: in		std_logic;
	GPIO_3			: out		std_logic;
	GPIO_4			: in		std_logic;
	GPIO_5			: inout		std_logic;
	GPIO_6			: inout		std_logic;	
	GPIO_7			: in		std_logic;	
	GPIO_8			: in		std_logic;	
	GPIO_9			: in		std_logic;	
	GPIO_10			: in		std_logic;
	GPIO_11			: in		std_logic;	
	GPIO_12			: out		std_logic;	
	GPIO_13			: out		std_logic;	
	GPIO_14			: inout		std_logic;	
	GPIO_15			: in		std_logic;	
	GPIO_16			: in		std_logic;
	
	GPIO_17			: in		std_logic;
	GPIO_18			: in		std_logic;	
	GPIO_19			: out		std_logic;	
	GPIO_20			: in		std_logic;
	GPIO_21			: in		std_logic;	
	GPIO_22			: in		std_logic;	
	GPIO_23			: in		std_logic;
	GPIO_24			: in		std_logic;
	GPIO_25			: inout		std_logic;	
	GPIO_26			: inout		std_logic;	
	GPIO_27			: inout		std_logic;
	GPIO_IDSD		: inout		std_logic;
	GPIO_IDSC		: inout		std_logic;

	
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
	mmc_dat1		: in		std_logic;
	mmc_dat2		: in		std_logic;
	mmc_n_cs		: out		std_logic;
	mmc_clk			: out		std_logic;
	mmc_mosi		: out		std_logic; 
	mmc_miso		: in		std_logic;

	-- PS/2 Mode enable, keyboard and Mouse interfaces
	PS2_enable		: out		std_logic;
	PS2_clk1		: inout		std_logic;
	PS2_data1		: inout		std_logic;
	
	PS2_clk2		: inout		std_logic;
	PS2_data2		: inout		std_logic
	);
end entity;

  
architecture arch of minimig_fleaohm_top is
constant reset_cycles : integer := 131071;
	
-- System clocks

	signal sysclk : std_logic;

-- SPI signals

	signal diskled :std_logic;
	signal floppyled : std_logic;
	signal powerled : unsigned(1 downto 0);

	signal sd_clk : std_logic;
	signal sd_cs : std_logic;
	signal sd_mosi : std_logic;
	signal sd_miso : std_logic;
	
	
-- Video
	signal dvi_red     : std_logic_vector(7 downto 0);
	signal dvi_green   : std_logic_vector(7 downto 0);
	signal dvi_blue    : std_logic_vector(7 downto 0);
	signal dvi_hsync   : std_logic := '0';
	signal dvi_vsync   : std_logic := '0';
	signal dvi_window : std_logic;
	signal dvi_pixel : std_logic;
	signal blank   : std_logic := '0';
	signal videoblank: std_logic;  
	signal vbl : std_logic;
	signal n_15khz : std_logic;
	
	
-- Amiga UART
    signal amiga_rs232_txd : std_logic;
	signal amiga_rs232_rxd : std_logic;
	
-- RS232 serial
	signal rs232_rxd : std_logic;
	signal rs232_txd : std_logic;

	signal audio_l : std_logic_vector(23 downto 0);
	signal audio_r : std_logic_vector(23 downto 0);
	
-- IO

	signal n_joy1 : std_logic_vector(6 downto 0);
	signal n_joy2 : std_logic_vector(6 downto 0);
	signal joyc : std_logic_vector(6 downto 0);
	signal joyd : std_logic_vector(6 downto 0);

	signal clk28m  : std_logic := '0';   
	
   signal red_u     : std_logic_vector(7 downto 0);
   signal green_u   : std_logic_vector(7 downto 0);
   signal blue_u    : std_logic_vector(7 downto 0);
  
	signal VTEMP_DAC		:std_logic_vector(4 downto 0);
	signal audio_data : std_logic_vector(17 downto 0);
	signal convert_audio_data : std_logic_vector(17 downto 0);
	
	constant cnt_div: integer:=617;                  -- Countervalue for 48khz Audio Enable,  567 for 25MHz PCLK
    signal   cnt:     integer range 0 to cnt_div-1; 
    signal   ce:      std_logic;

	signal ps2k_data_in : std_logic;
	signal ps2k_clk_in : std_logic;
	signal ps2k_data_out : std_logic;
	signal ps2k_clk_out : std_logic;
	signal ps2m_data_in : std_logic;
	signal ps2m_clk_in : std_logic;
	signal ps2m_data_out : std_logic;
	signal ps2m_clk_out : std_logic;
begin


-- Joystick bits(5-0) = fire2,fire,right,left,down,up mapped to GPIO header
n_joy1(3)<= GPIO_4 ; -- up
n_joy1(2)<= GPIO_7 ; -- down
n_joy1(1)<= GPIO_8 ; -- left
n_joy1(0)<= GPIO_9 ; -- right
n_joy1(4)<= GPIO_10 ; -- fire
n_joy1(5)<= GPIO_11 ; -- fire2

n_joy2(3)<= GPIO_15 ; -- up
n_joy2(2)<= GPIO_17 ; -- down
n_joy2(1)<= GPIO_18 ; -- left 
n_joy2(0)<= GPIO_22 ; -- right  
n_joy2(4)<= GPIO_23 ; -- fire
n_joy2(5)<= GPIO_24 ; -- fire2 

-- Video output horizontal scanrate select 15/30kHz select via GPIO header
n_15khz <= GPIO_21 ; -- Default is 30kHz video out if pin left unconnected. Connect to GND for 15kHz video. 

-- Amiga UART connection to GPIO header
amiga_rs232_rxd <= GPIO_16;
GPIO_12 <= amiga_rs232_txd;


PS2_enable <= '1';


-- SPI
n_led1<=NOT sd_cs;
mmc_n_cs<=sd_cs;
mmc_mosi<=sd_mosi;
sd_miso<=mmc_miso;
mmc_clk<=sd_clk;


virtual_top : COMPONENT minimig_virtual_top
generic map (
	  havertg => 1,
	  haveaudio => 1,
	  havec2p => 0,
	  vga_width => 8,
	  havecart => 0,
	  haveaga => 0
)
PORT map
	(
		sys_tms => TMS,
		sys_tdo => TDO,
		sys_tdi => TDI,
		sys_tck => TCK,
		CLK_IN => sys_clock,
		CLK_114 => sysclk,
		RESET_N => sys_reset,
		LED_POWER => open,
		LED_DISK => open,
--		n_15khz => n_15khz,
		MENU_BUTTON => GPIO_2,
		CTRL_TX => rs232_txd,
		CTRL_RX => rs232_rxd,
		AMIGA_TX => amiga_rs232_txd,
		AMIGA_RX => amiga_rs232_rxd,
		
		DVI_HS => dvi_hsync,
		DVI_VS => dvi_vsync,
		DVI_R	=> dvi_red,
		DVI_G	=> dvi_green,
		DVI_B	=> dvi_blue,
		DVI_STROBE => dvi_pixel,
		DVI_DE => dvi_window,
	
		SDRAM_DQ	=> Dram_Data,
		SDRAM_A => Dram_Addr,
		SDRAM_DQML => Dram_DQML,
		SDRAM_DQMH => Dram_DQMH,
		SDRAM_nWE => Dram_n_We,
		SDRAM_nCAS => Dram_n_Cas,
		SDRAM_nRAS => Dram_n_Ras,
		SDRAM_nCS => Dram_n_cs,
		SDRAM_BA => Dram_BA,
		SDRAM_CLK => Dram_Clk,
		SDRAM_CKE => Dram_CKE,

		AUDIO_L => audio_l,
		AUDIO_R => audio_r,

		PS2_DAT_I => ps2k_data_in,
		PS2_DAT_O => ps2k_data_out,
		PS2_CLK_I => ps2k_clk_in,
		PS2_CLK_O => ps2k_clk_out,
		
		PS2_MDAT_I => ps2m_data_in,
		PS2_MDAT_O => ps2m_data_out,
		PS2_MCLK_I => ps2m_clk_in,
		PS2_MCLK_O => ps2m_clk_out,

		JOYA => n_joy1,
		JOYB => n_joy2,
		JOYC => (others => '1'),
		JOYD => (others => '1'),
		
		SD_MISO => sd_miso,
		SD_MOSI => sd_mosi,
		SD_CLK => sd_clk,
		SD_CS => sd_cs,
		SD_ACK => '1',
		C64_KEYS => (others => '1'),
		amiga_key => (others =>'0'),
		amiga_reset_n=>'1',
		amiga_key_stb=>'0'
	);

ps2k_data_in <= PS2_data1;
ps2k_clk_in <= PS2_clk1;
PS2_data1 <= '0' when ps2k_data_out='0' else 'Z';
PS2_clk1 <= '0' when ps2k_clk_out='0' else 'Z';

ps2m_data_in <= PS2_data2;
ps2m_clk_in <= PS2_clk2;
PS2_data2 <= '0' when ps2m_data_out='0' else 'Z';
PS2_clk2 <= '0' when ps2m_clk_out='0' else 'Z';	
	
slave_tx_o<=rs232_txd;
rs232_rxd<=slave_rx_i;

joyc<=(others=>'1');
joyd<=(others=>'1');

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
		
	begin

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

		dvi_inst : component dvi
		generic map (
			DDR_ENABLED => useddr
		)
		port map (
			pclk => clk_video,
			tmds_clk => clk_tmds,

			in_vga_red => dvi_red,
			in_vga_green => dvi_green,
			in_vga_blue => dvi_blue,

			in_vga_vsync => dvi_vsync,
			in_vga_hsync => dvi_hsync,
			in_vga_pixel => dvi_pixel,
			in_vga_window => dvi_window,

			out_tmds_red => tmds_r,
			out_tmds_green => tmds_g,
			out_tmds_blue => tmds_b,
			out_tmds_clk => tmds_clk,
			out_tmds_red_n => tmds_r_n,
			out_tmds_green_n => tmds_g_n,
			out_tmds_blue_n => tmds_b_n,
			out_tmds_clk_n => tmds_clk_n
		);

		dviout_c : component ODDRX1F port map (D0 => tmds_clk(0), D1=>tmds_clk(1), Q => LVDS_ck(0), SCLK =>clk_tmds, RST=>'0');
		dviout_r : component ODDRX1F port map (D0 => tmds_r(0), D1=>tmds_r(1), Q => LVDS_Red(0), SCLK =>clk_tmds, RST=>'0');
		dviout_g : component ODDRX1F port map (D0 => tmds_g(0), D1=>tmds_g(1), Q => LVDS_Green(0), SCLK =>clk_tmds, RST=>'0');
		dviout_b : component ODDRX1F port map (D0 => tmds_b(0), D1=>tmds_b(1), Q => LVDS_Blue(0), SCLK =>clk_tmds, RST=>'0');
--		dviout_c_n : component ODDRX1F port map (D0 => tmds_clk_n(0), D1=>tmds_clk_n(1), Q => gpdi_dn(3), SCLK =>clk_tmds, RST=>'0');
--		dviout_r_n : component ODDRX1F port map (D0 => tmds_r_n(0), D1=>tmds_r_n(1), Q => gpdi_dn(2), SCLK =>clk_tmds, RST=>'0');
--		dviout_g_n : component ODDRX1F port map (D0 => tmds_g_n(0), D1=>tmds_g_n(1), Q => gpdi_dn(1), SCLK =>clk_tmds, RST=>'0');
--		dviout_b_n : component ODDRX1F port map (D0 => tmds_b_n(0), D1=>tmds_b_n(1), Q => gpdi_dn(0), SCLK =>clk_tmds, RST=>'0');

	end block;

audio : block 
	signal DAC_L : std_logic;
	signal DAC_R : std_logic;

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
	-- Audio output mapped to GPIO header
	GPIO_13 <= DAC_R; 
	GPIO_19 <= DAC_L;
	
	audiosd : COMPONENT hybrid_pwm_sd
	PORT map
	(
		clk => sysclk,
		terminate => '0',
		d_l(15) => not audio_l(23),
		d_l(14 downto 0) => audio_l(22 downto 8),
		q_l => DAC_L,
		d_r(15) => not audio_r(23),
		d_r(14 downto 0) => audio_r(22 downto 8),
		q_r => DAC_R
	);

end block;

end arch;

