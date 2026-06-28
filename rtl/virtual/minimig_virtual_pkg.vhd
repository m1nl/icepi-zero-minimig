library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

package minimig_virtual_pkg is

	COMPONENT minimig_virtual_top
	generic
	( hostonly : integer := 0;
	  debug : integer := 0;
	  spimux : integer := 0;
	  ram_64meg : integer := 0;
	  vga_width : integer := 5;
	  haveiec : integer := 0;
	  havereconfig : integer := 0;
	  havertg : integer := 1;
	  haveaudio : integer := 1;
	  havec2p : integer := 1;
	  havespirtc : integer := 0;
	  havecart : integer := 1;
	  haveaga : integer := 1;
	  haventscswitch : integer := 1
	);
	PORT
	(
		-- JTAG "pins"
		sys_tdo : out std_logic;
		sys_tdi : in std_logic := '1';
		sys_tck : in std_logic := '1';
		sys_tms : in std_logic := '1';

		CLK_IN 		:   in std_logic;
		CLK_USB_IN 	:   in std_logic;
		RESET_N 	:   in STD_LOGIC;

		CLK_114		:	 out STD_LOGIC;
		CLK_28		:	 out STD_LOGIC;
		CLK_142		:	 out STD_LOGIC;
		PLL_LOCKED  :   out std_logic;

		MENU_BUTTON :   IN STD_LOGIC;
		LED_POWER	:	 OUT STD_LOGIC;
		LED_DISK		:	 OUT STD_LOGIC;
		LED_USB         :    OUT STD_LOGIC_VECTOR(1 downto 0);
		LED_AUX		:	 OUT STD_LOGIC;
		CTRL_TX		:	 OUT STD_LOGIC;
		CTRL_RX		:	 IN STD_LOGIC;
		AMIGA_TX		:	 OUT STD_LOGIC;
		AMIGA_RX		:	 IN STD_LOGIC;
		VGA_HS		:	 OUT STD_LOGIC;
		VGA_VS		:	 OUT STD_LOGIC;
		VGA_R		:	 OUT STD_LOGIC_VECTOR(vga_width-1 DOWNTO 0);
		VGA_G		:	 OUT STD_LOGIC_VECTOR(vga_width-1 DOWNTO 0);
		VGA_B		:	 OUT STD_LOGIC_VECTOR(vga_width-1 DOWNTO 0);
		VGA_STROBE  :   OUT STD_LOGIC;
		VGA_DE      :   OUT STD_LOGIC;
		DVI_HS		:	 OUT STD_LOGIC;
		DVI_VS		:	 OUT STD_LOGIC;
		DVI_R		:	 OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		DVI_G		:	 OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		DVI_B		:	 OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		DVI_STROBE  :   OUT STD_LOGIC;
		DVI_DE      :   OUT STD_LOGIC;
		SDRAM_DQ		:	 INOUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		SDRAM_A		:	 OUT STD_LOGIC_VECTOR(12 DOWNTO 0);
		SDRAM_DQML		:	 OUT STD_LOGIC;
		SDRAM_DQMH		:	 OUT STD_LOGIC;
		SDRAM_nWE		:	 OUT STD_LOGIC;
		SDRAM_nCAS		:	 OUT STD_LOGIC;
		SDRAM_nRAS		:	 OUT STD_LOGIC;
		SDRAM_nCS		:	 OUT STD_LOGIC;
		SDRAM_BA		:	 OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
		SDRAM_CLK		:	 OUT STD_LOGIC;
		SDRAM_CKE		:	 OUT STD_LOGIC;
		AUDIO_MIX_L		:	 OUT STD_LOGIC_VECTOR(23 downto 0);
		AUDIO_MIX_R		:	 OUT STD_LOGIC_VECTOR(23 downto 0);
		AUDIO_PAULA_L		:	 OUT STD_LOGIC_VECTOR(15 downto 0);
		AUDIO_PAULA_R		:	 OUT STD_LOGIC_VECTOR(15 downto 0);
		AUDIO_TICK	:	 OUT STD_LOGIC;
		PS2_DAT_I		:	 IN STD_LOGIC;
		PS2_CLK_I		:	 IN STD_LOGIC;
		PS2_MDAT_I		:	 IN STD_LOGIC;
		PS2_MCLK_I		:	 IN STD_LOGIC;
		PS2_DAT_O	:	 OUT STD_LOGIC;
		PS2_CLK_O	:	 OUT STD_LOGIC;
		PS2_MDAT_O	:	 OUT STD_LOGIC;
		PS2_MCLK_O	:	 OUT STD_LOGIC;
		AMIGA_RESET_N : IN STD_LOGIC;
		AMIGA_KEY	: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		AMIGA_KEY_STB : IN STD_LOGIC;
		C64_KEYS	:	IN STD_LOGIC_VECTOR(63 DOWNTO 0);
		JOYA		:	 IN STD_LOGIC_VECTOR(6 DOWNTO 0);
		JOYB		:	 IN STD_LOGIC_VECTOR(6 DOWNTO 0);
		JOYC		:	 IN STD_LOGIC_VECTOR(6 DOWNTO 0);
		JOYD		:	 IN STD_LOGIC_VECTOR(6 DOWNTO 0);
		SD_MISO	:	 IN STD_LOGIC;
		SD_MOSI	:	 OUT STD_LOGIC;
		SD_CLK	:	 OUT STD_LOGIC;
		SD_CS		:	 OUT STD_LOGIC;
		SD_ACK	:	 IN STD_LOGIC;
		usb_dp  :    INOUT std_logic_vector(1 downto 0);
		usb_dn  :    INOUT std_logic_vector(1 downto 0);
		RTC_CS   :   OUT STD_LOGIC;
		RECONFIG	:	 OUT STD_LOGIC;
		IECSERIAL:	 OUT STD_LOGIC;
		FREEZE   :  in std_logic := '0'
	);
	END COMPONENT;
end package;
