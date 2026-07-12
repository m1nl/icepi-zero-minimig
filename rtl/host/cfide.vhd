------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2008-2011 Tobias Gubener                                   --
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published        --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- Modifications by Alastair M. Robinson to work with a cheap
-- Ebay Cyclone III board.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity cfide is
	generic (
		spimux : integer := 0;
		havespirtc : integer := 0;
		haveiec : integer := 0;
		havereconfig : integer := 0;
		havecart : integer := 0;
		haveclockport : integer := 0;
		haveamiga : integer := 0
	);
	port (
		sysclk	: in std_logic;
		usbclk  : in std_logic;

		n_reset	: in std_logic;

		addr	: in std_logic_vector(31 downto 2);
		d		: in std_logic_vector(31 downto 0);
		q		: out std_logic_vector(31 downto 0);
		req 	: in std_logic;
		wr 	: in std_logic;
		ack 	: buffer std_logic;

		sd_di		: in std_logic;
		sd_cs 	: out std_logic_vector(7 downto 0);
		sd_clk 	: out std_logic;
		sd_do		: out std_logic;
		sd_dimm	: in std_logic;		--for sdcard
		sd_ack 	: in std_logic; -- indicates that SPI signal has made it to the wire
		debugTxD : out std_logic;
		debugRxD : in std_logic;
		menu_button	: in std_logic:='1';
		scandoubler	: out std_logic;
		invertsync : out std_logic;

		audio_ena : out std_logic;
		audio_clear : out std_logic;
		audio_buf : in std_logic;
		audio_amiga : in std_logic;

		vbl_int	: in std_logic;
		interrupt	: out std_logic;
		c64_keys	: in std_logic_vector(63 downto 0) :=X"FFFFFFFFFFFFFFFF";
		c64_present : in std_logic := '0';
		amiga_key	: out std_logic_vector(15 downto 0);
		amiga_key_stb	: out std_logic;

		amiga_addr : in std_logic_vector(7 downto 0);
		amiga_d : in std_logic_vector(15 downto 0);
		amiga_q : out std_logic_vector(15 downto 0);
		amiga_req : in std_logic;
		amiga_wr : in std_logic;
		amiga_ack : out std_logic;

		rtc_q : out std_logic_vector(63 downto 0);
		reconfig : out std_logic;
		iecserial : out std_logic;

		usb_dp : inout std_logic_vector(1 downto 0);
		usb_dn : inout std_logic_vector(1 downto 0);

		usb_connected : out std_logic_vector(1 downto 0);

		joya : out std_logic_vector(11 downto 0);
		joyb : out std_logic_vector(11 downto 0);

		joy_invert : out std_logic := '0';

		-- 28Mhz signals
		clk_28	: in std_logic;
		tick_in : in std_logic	-- 44.1KHz - makes it easy to keep timer in lockstep with audio.
);

end cfide;


architecture rtl of cfide is

signal shift: std_logic_vector(9 downto 0);
signal clkgen: unsigned(9 downto 0);
signal shiftout: std_logic;
signal txbusy: std_logic;
signal uart_ld: std_logic;
--signal IO_select : std_logic;
signal platform_select: std_logic;
signal timer_select: std_logic;
signal SPI_select: std_logic;
signal platformdata: std_logic_vector(15 downto 0);
signal IOdata: std_logic_vector(15 downto 0);
signal IOcpuena: std_logic;

type support_states is (idle, io_aktion);
signal support_state		: support_states;
signal next_support_state		: support_states;

signal sd_out	: std_logic_vector(15 downto 0);
signal sd_in	: std_logic_vector(15 downto 0);
signal sd_in_shift	: std_logic_vector(15 downto 0);
signal sd_di_in	: std_logic;
signal shiftcnt	: unsigned(13 downto 0);
signal sck		: std_logic;
signal scs		: std_logic_vector(7 downto 0);
--signal dscs		: std_logic;
signal SD_busy		: std_logic;
signal spi_div: unsigned(8 downto 0);
signal spi_speed: unsigned(7 downto 0);
signal spi_wait : std_logic;
signal spi_wait_d : std_logic;

signal timecnt: unsigned(23 downto 0);

signal rs232_select : std_logic;
signal rs232data : std_logic_vector(15 downto 0);

signal audio_q : std_logic_vector(15 downto 0);
signal audio_select : std_logic;

signal interrupt_select : std_logic;
signal interrupt_ena : std_logic;
signal keyboard_select : std_logic;
signal keyboard_q : std_logic_vector(15 downto 0);
signal amigatohost  : std_logic_vector(15 downto 0);
signal amiga_select : std_logic;
signal amiga_ready_d : std_logic;

signal usb_select_0 : std_logic;
signal usbtohost_0 : std_logic_vector(31 downto 0);

signal usb_select_1 : std_logic;
signal usbtohost_1 : std_logic_vector(31 downto 0);

signal rtc_select : std_logic;
signal reconfigpresent : std_logic;
signal spirtcpresent : std_logic;
signal iecpresent : std_logic;
signal cartpresent : std_logic;
signal clockportpresent : std_logic;

begin

-- Peripheral registers, which are only 16-bits wide.

q(15 downto 0) <=
	IOdata WHEN rs232_select='1' or SPI_select='1' ELSE
	std_logic_vector(timecnt(23 downto 8)) when timer_select='1' ELSE
	audio_q when audio_select='1' else
	keyboard_q when keyboard_select='1' else
	amigatohost when amiga_select='1' else
	usbtohost_0(15 downto 0) when usb_select_0='1' else
	usbtohost_1(15 downto 0) when usb_select_1='1' else
	platformdata;

-- Peripheral registers, which are 32-bits wide.

q(31 downto 16) <=
	usbtohost_0(31 downto 16) when usb_select_0='1' else
	usbtohost_1(31 downto 16) when usb_select_1='1' else
	(others => '0');

spirtcpresent <= '1' when havespirtc=1 else '0';
iecpresent <= '1' when haveiec=1 else '0';
reconfigpresent <= '1' when havereconfig=1 else '0';
cartpresent <= '1' when havecart=1 else '0';
clockportpresent <= '1' when haveclockport=1 else '0';

platformdata <=  X"00" & cartpresent & c64_present & clockportpresent & iecpresent & reconfigpresent & spirtcpresent & "1" & menu_button;

IOdata <= sd_in;

process(clk_28)
begin
	if rising_edge(clk_28) then
		ack<='0';
		if req='1' then
			if rs232_select='1' or SPI_select='1' then
				ack<=IOcpuena;
			elsif timer_select='1' or platform_select='1' or audio_select='1' or usb_select_0='1' or usb_select_1='1' or interrupt_select='1'
						or keyboard_select='1' or amiga_select='1' or rtc_select='1' then
				ack<='1';
			end if;
		end if;
	end if;
end process;


sd_in(15 downto 8) <= (others=>'0');
sd_in(7 downto 0) <= sd_in_shift(7 downto 0);

audio_q<=X"000"&"00"&audio_amiga&audio_buf;

SPI_select <= '1' when addr(27)='1' and addr(7 downto 4)=X"E" ELSE '0';
rs232_select <= '1' when addr(27)='1' and addr(7 downto 4)=X"F" ELSE '0';
timer_select <= '1' when addr(27)='1' and addr(7 downto 4)=X"D" ELSE '0';
platform_select <= '1' when addr(27)='1' and addr(7 downto 4)=X"C" ELSE '0';
audio_select <='1' when addr(27)='1' and addr(7 downto 4)=X"B" else '0';
interrupt_select <='1' when addr(27)='1' and addr(7 downto 4)=X"A" else '0';
keyboard_select <='1' when addr(27)='1' and addr(7 downto 4)=X"9" else '0';
amiga_select <= '1' when addr(27)='1' and addr(7 downto 4)=X"8" else '0';
rtc_select <= spirtcpresent when addr(27)='1' and addr(7 downto 4)=X"7" else '0';
usb_select_0 <= '1' when addr(27)='1' and addr(7 downto 4)=X"6" else '0';
usb_select_1 <= '1' when addr(27)='1' and addr(7 downto 4)=X"5" else '0';


-- RTC handling at 0fffff70

process (clk_28,n_reset)
begin
	if n_reset='0' then
		rtc_q<=(others=>'0');
	elsif rising_edge(clk_28) then
		if rtc_select='1' and req='1' and wr='1' then
			case addr(3 downto 2) is
				when "00" =>
					rtc_q(63 downto 48)<=d(15 downto 0);
				when "01" =>
					rtc_q(47 downto 32)<=d(15 downto 0);
				when "10" =>
					rtc_q(31 downto 16)<=d(15 downto 0);
				when "11" =>
					rtc_q(15 downto 0)<=d(15 downto 0);
				when others =>
					null;
			end case;
		end if;
	end if;
end process;


-- Amiga interface at 0fffff80
gen_amiga : if haveamiga=1 generate
begin

process (clk_28,n_reset)
begin
	if rising_edge(clk_28) then

		amiga_ack<='0';

		if amiga_select='1' and req='1' then

			if wr='1' then
				amiga_q<=d(15 downto 0);
				amiga_ack<='1';
			end if;

			if addr(2)='1' then
				amigatohost<=amiga_d;
			else
				amigatohost<=amiga_req&amiga_wr&"000000"&amiga_addr;
			end if;

		end if;
	end if;
end process;
end generate;

gen_noamiga : if haveamiga=0 generate
begin
amiga_ack <= amiga_select;
end generate;



-- C64 Keyboard handling at 0fffff90

process (clk_28,n_reset)
begin
	if rising_edge(clk_28) then
		amiga_key_stb<='0';
		if keyboard_select='1' and req='1' then
			if  wr='1' then
				amiga_key<=d(15 downto 0);
				amiga_key_stb<='1';
			end if;
			case addr(3 downto 2) is
				when "00" =>
					keyboard_q<=c64_keys(63 downto 48);
				when "01" =>
					keyboard_q<=c64_keys(47 downto 32);
				when "10" =>
					keyboard_q<=c64_keys(31 downto 16);
				when "11" =>
					keyboard_q<=c64_keys(15 downto 0);
				when others =>
					null;
			end case;
		end if;
	end if;
end process;


-- Interrupt handling at 0fffffa0
-- Any access to this range will clear the interrupt flag;

process (clk_28,n_reset)
begin
	if n_reset='0' then
		interrupt<='0';
		interrupt_ena<='0';
	elsif rising_edge(clk_28) then
		amiga_ready_d<=amiga_req;
		if vbl_int='1' or (amiga_req='1' and amiga_ready_d='0') then
			interrupt<=interrupt_ena;
		end if;
		if interrupt_select='1' and req='1' then
			interrupt<='0';
			if  wr='1' then
				interrupt_ena<=d(0);
			end if;
		end if;
	end if;
end process;


---------------------------------
-- Platform specific registers --
---------------------------------

process(clk_28,n_reset)
begin
	if n_reset='0' then
		reconfig<='0';
		iecserial<='0';
		invertsync<='0';
	elsif rising_edge(clk_28) then
		if req='1' and wr='1' then

			if platform_select='1' then	-- Write to platform registers
				scandoubler<=d(0);
				invertsync<=d(1);
				reconfig<=d(3);
				iecserial<=d(4);
			end if;

			if audio_select='1' then
				audio_clear<=d(1);
				audio_ena<=d(0);
			end if;

		end if;
	end if;
end process;


-----------------------------------------------------------------
-- Support States
-----------------------------------------------------------------
process(sysclk, shift)
begin
	IF rising_edge(sysclk) THEN
--		support_state <= idle;
		IOcpuena <= '0';
		CASE support_state IS
			WHEN idle =>
				uart_ld <= '0';
				IF rs232_select='1' AND req='1' and wr='1' THEN
					IF txbusy='0' THEN
						uart_ld <= '1';
						IOcpuena <= '1';
					END IF;
					if uart_ld='1' and txbusy = '1' then
						uart_ld <= '0';
						support_state <= io_aktion;
					end if;
				ELSIF SPI_select='1' and req='1' THEN
					IF SD_busy='0' THEN
						support_state <= io_aktion;
						IOcpuena <= '1';
					END IF;
				END IF;

			WHEN io_aktion =>
				if req='0' then
					support_state <= idle;
				else
					IOcpuena <= '1';
				end if;

			WHEN others =>
				support_state <= idle;
		END CASE;
	END IF;
end process;

-----------------------------------------------------------------
-- SPI-Interface
-----------------------------------------------------------------
	sd_cs <= NOT scs;
	sd_clk <= NOT sck;
	sd_do <= sd_out(15);
	SD_busy <= shiftcnt(13);

	PROCESS (sysclk, n_reset, scs, sd_di, sd_dimm) BEGIN
		IF scs(1)='0' and scs(7)='0' THEN
			sd_di_in <= sd_di;
		ELSE
			sd_di_in <= sd_dimm;
		END IF;
		IF n_reset ='0' THEN
			shiftcnt <= (others => '0');
			spi_div <= (others => '0');
			scs <= (others => '0');
			sck <= '0';
			spi_speed <= "00000000";
--			dscs <= '0';
			spi_wait <= '0';
			sd_out<=(others=>'0');
			sd_in_shift<=(others=>'0');
		ELSIF rising_edge(sysclk) THEN

			spi_wait_d<=spi_wait;

			if spi_wait_d='1' and sd_ack='1' then -- Unpause SPI as soon as the IO controller has written to the MUX
				spi_wait<='0';
			end if;

			IF SPI_select='1' AND req='1' and wr='1' AND SD_busy='0' THEN	 --SD write
				case addr(3 downto 2) is
					when "10" => -- 8
						spi_speed <= unsigned(d(7 downto 0));
					when "01" => -- 4
						scs(0) <= not d(0);
						IF d(7)='1' THEN
							scs(7) <= not d(0);
						END IF;
						IF d(6)='1' THEN
							scs(6) <= not d(0);
						END IF;
						IF d(5)='1' THEN
							scs(5) <= not d(0);
						END IF;
						IF d(4)='1' THEN
							scs(4) <= not d(0);
						END IF;
						IF d(3)='1' THEN
							scs(3) <= not d(0);
						END IF;
						IF d(2)='1' THEN
							scs(2) <= not d(0);
						END IF;
						IF d(1)='1' THEN
							scs(1) <= not d(0);
						END IF;
					when "00" => -- 0
	--						ELSE							--DA4000
						if scs(1)='1' THEN -- Wait for io component to propagate signals.
							spi_wait<='1'; -- Only wait if SPI needs to go through the MUX
							if spimux = 1 then
								spi_div(8 downto 1) <= spi_speed+4;
							else
								spi_div(8 downto 1) <= spi_speed;
							end if;
						else
							spi_div(8 downto 1) <= spi_speed;
						end if;
						IF scs(6)='1' THEN		-- SPI direkt Mode
							shiftcnt <= "10111111111111";
							sd_out <= X"FFFF";
						ELSE
							shiftcnt <= "10000000000111";
							sd_out(15 downto 8) <= d(7 downto 0);
						END IF;
						sck <= '1';
					when others =>
						null;
				end case;
			ELSE
				IF spi_div="0000000000" THEN
					if scs(1)='1' THEN -- Wait for io component to propagate signals.
						spi_wait<='1'; -- Only wait if SPI needs to go through the MUX
						if spimux=1 then
							spi_div(8 downto 1) <= spi_speed+4;
						else
							spi_div(8 downto 1) <= spi_speed;
						end if;
					else
						spi_div(8 downto 1) <= spi_speed;
					end if;
					IF SD_busy='1' THEN
						IF sck='0' THEN
							IF shiftcnt(12 downto 0)/="0000000000000" THEN
								sck <='1';
							END IF;
							shiftcnt <= shiftcnt-1;
							sd_out <= sd_out(14 downto 0)&'1';
						ELSE
							sck <='0';
							sd_in_shift <= sd_in_shift(14 downto 0)&sd_di_in;
						END IF;
					END IF;
				ELSif spi_wait='0' then
					spi_div <= spi_div-1;
				END IF;
			END IF;

		END IF;
	END PROCESS;

-----------------------------------------------------------------
-- Simple UART only TxD
-----------------------------------------------------------------
debugTxD <= not shiftout;
process(n_reset, clk_28, shift)
	constant CLKGEN_28_115 : unsigned(9 downto 0) := "0011110110";
begin
	if shift="0000000000" then
		txbusy <= '0';
	else
		txbusy <= '1';
	end if;

	if n_reset='0' then
		shiftout <= '0';
		shift <= "0000000000";
		clkgen<=CLKGEN_28_115;
	elsif rising_edge(clk_28) then
		if uart_ld = '1' then
			shift <=  '1' & d(7 downto 0) & '0';			--STOP,MSB...LSB, START
		end if;
		if clkgen/=0 then
			clkgen <= clkgen-1;
		else
--			clkgen <= "1111011001";--985;		--113.5MHz/115200
			clkgen <= CLKGEN_28_115;--246;		--28.36MHz/115200
			shiftout <= not shift(0) and txbusy;
			shift <=  '0' & shift(9 downto 1);
		end if;
	end if;
end process;


-----------------------------------------------------------------
-- timer
-----------------------------------------------------------------
process(clk_28)
begin
	IF rising_edge(clk_28) THEN
		if tick_in='1' then
			timecnt <= timecnt+1;
		END IF;
	end if;
end process;

-----------------------------------------------------------------
-- USB
-----------------------------------------------------------------

usbblock : block
	signal usb_dp_o  : std_logic_vector(1 downto 0);
	signal usb_dn_o  : std_logic_vector(1 downto 0);
	signal usb_oe : std_logic_vector(1 downto 0);

	signal rom_addra : std_logic_vector(9 downto 0);
	signal rom_douta : std_logic_vector(3 downto 0);
	signal rom_ena   : std_logic;

	signal rom_addrb : std_logic_vector(9 downto 0);
	signal rom_doutb : std_logic_vector(3 downto 0);
	signal rom_enb   : std_logic;

	signal usb_typ_0 : std_logic_vector(1 downto 0);
	signal usb_typ_1 : std_logic_vector(1 downto 0);

	signal usb_full_report_0 : std_logic;
	signal usb_full_report_1 : std_logic;

	signal usb_game_0 : std_logic_vector(13 downto 0);
	signal usb_game_1 : std_logic_vector(13 downto 0);

	signal usb_game_0_combined : std_logic;
	signal usb_game_1_combined : std_logic;

	signal usbreset       : std_logic;
	signal usbreset_sync1 : std_logic;
	signal usbreset_sync2 : std_logic;

	type sync3_t is array (0 to 1) of std_logic_vector(2 downto 0);
	signal hid_sync           : sync3_t := (others => (others => '0'));
	signal full_report_toggle : std_logic_vector(1 downto 0) := (others => '0');

	signal hid_report_ready_0 : std_logic;
	signal hid_report_ready_1 : std_logic;
	signal hid_report_ack_0 : std_logic;
	signal hid_report_ack_1 : std_logic;

	signal hid_report_0 : std_logic_vector(63 downto 0);
	signal hid_report_1 : std_logic_vector(63 downto 0);

	component usb_hid_host
		generic (
			FULL_SPEED       : integer := 1;
			KEYBOARD_SUPPORT : integer := 1;
			MOUSE_SUPPORT    : integer := 1;
			GAME_SUPPORT     : integer := 1
		);
		port (
			clk   : in  std_logic;
			reset : in  std_logic;
			cs    : in  std_logic;

			usb_dm_i : in  std_logic;
			usb_dp_i : in  std_logic;
			usb_dm_o : out std_logic;
			usb_dp_o : out std_logic;
			usb_oe   : out std_logic;

			typ         : out std_logic_vector(1 downto 0);
			full_report : out std_logic;
			connerr     : out std_logic;
			busy        : out std_logic;

			key_modifiers : out std_logic_vector(7 downto 0);
			key_0         : out std_logic_vector(7 downto 0);
			key_1         : out std_logic_vector(7 downto 0);
			key_2         : out std_logic_vector(7 downto 0);
			key_3         : out std_logic_vector(7 downto 0);
			key_4         : out std_logic_vector(7 downto 0);
			key_5         : out std_logic_vector(7 downto 0);

			mouse_btn : out std_logic_vector(2 downto 0);
			mouse_dx  : out signed(7 downto 0);
			mouse_dy  : out signed(7 downto 0);

			game_l   : out std_logic;
			game_r   : out std_logic;
			game_u   : out std_logic;
			game_d   : out std_logic;

			game_a   : out std_logic;
			game_b   : out std_logic;
			game_x   : out std_logic;
			game_y   : out std_logic;
			game_sel : out std_logic;
			game_sta : out std_logic;

			game_extra : out std_logic_vector(3 downto 0);

			dbg_hid_report : out std_logic_vector(63 downto 0);
			dbg_hid_regs   : out std_logic_vector(63 downto 0);

			rom_addr : out std_logic_vector(9 downto 0);
			rom_dout : in  std_logic_vector(3 downto 0);
			rom_en   : out std_logic
		);
	end component;

	component usb_hid_host_dual_rom
		generic (
			MEMORY_FILE : string := "usb_hid_host_rom.mem"
		);
		port (
			clk : in std_logic;

			addra : in  std_logic_vector(9 downto 0);
			douta : out std_logic_vector(3 downto 0);
			ena   : in  std_logic;

			addrb : in  std_logic_vector(9 downto 0);
			doutb : out std_logic_vector(3 downto 0);
			enb   : in  std_logic
		);
	end component;
begin
	-- Drive outputs onto the bus
	usb_dp(0) <= usb_dp_o(0) when usb_oe(0) = '1' else 'Z';
	usb_dn(0) <= usb_dn_o(0) when usb_oe(0) = '1' else 'Z';
	usb_dp(1) <= usb_dp_o(1) when usb_oe(1) = '1' else 'Z';
	usb_dn(1) <= usb_dn_o(1) when usb_oe(1) = '1' else 'Z';

	u_rom : usb_hid_host_dual_rom
	generic map (
		MEMORY_FILE => "../../rtl/usb_hid_host/rom/usb_hid_host_rom.mem"
	)
	port map (
		clk   => usbclk,
		addra => rom_addra,
		douta => rom_douta,
		ena   => rom_ena,
		addrb => rom_addrb,
		doutb => rom_doutb,
		enb   => rom_enb
	);

	u_usb_hid_host_0 : usb_hid_host
	generic map (
		FULL_SPEED       => 1,
		KEYBOARD_SUPPORT => 1,
		MOUSE_SUPPORT    => 1,
		GAME_SUPPORT     => 1
	)
	port map (
		clk   => usbclk,
		reset => usbreset,
		cs    => '1',

		-- USB only
		usb_dm_i => usb_dn(0),
		usb_dp_i => usb_dp(0),
		usb_dm_o => usb_dn_o(0),
		usb_dp_o => usb_dp_o(0),
		usb_oe   => usb_oe(0),

		-- ROM only
		rom_addr => rom_addra,
		rom_dout => rom_douta,
		rom_en   => open,

		-- everything else unused
		typ            => usb_typ_0,
		full_report    => usb_full_report_0,
		connerr        => open,
		busy           => open,

		key_modifiers  => open,
		key_0          => open,
		key_1          => open,
		key_2          => open,
		key_3          => open,
		key_4          => open,
		key_5          => open,

		mouse_btn      => open,
		mouse_dx       => open,
		mouse_dy       => open,

		game_l         => usb_game_0(0),
		game_r         => usb_game_0(1),
		game_u         => usb_game_0(2),
		game_d         => usb_game_0(3),

		game_a         => usb_game_0(4),
		game_b         => usb_game_0(5),
		game_x         => usb_game_0(6),
		game_y         => usb_game_0(7),
		game_sel       => usb_game_0(8),
		game_sta       => usb_game_0(9),

		game_extra     => usb_game_0(13 downto 10),

		dbg_hid_report => hid_report_0,
		dbg_hid_regs   => open
	);

	rom_ena <= '1';
	rom_enb <= '1';

	u_usb_hid_host_1 : usb_hid_host
	generic map (
		FULL_SPEED       => 1,
		KEYBOARD_SUPPORT => 1,
		MOUSE_SUPPORT    => 1,
		GAME_SUPPORT     => 1
	)
	port map (
		clk   => usbclk,
		reset => usbreset,
		cs    => '1',

		-- USB only
		usb_dm_i => usb_dn(1),
		usb_dp_i => usb_dp(1),
		usb_dm_o => usb_dn_o(1),
		usb_dp_o => usb_dp_o(1),
		usb_oe   => usb_oe(1),

		-- ROM only
		rom_addr => rom_addrb,
		rom_dout => rom_doutb,
		rom_en   => open,

		-- everything else unused
		typ            => usb_typ_1,
		full_report    => usb_full_report_1,
		connerr        => open,
		busy           => open,

		key_modifiers  => open,
		key_0          => open,
		key_1          => open,
		key_2          => open,
		key_3          => open,
		key_4          => open,
		key_5          => open,

		mouse_btn      => open,
		mouse_dx       => open,
		mouse_dy       => open,

		game_l         => usb_game_1(0),
		game_r         => usb_game_1(1),
		game_u         => usb_game_1(2),
		game_d         => usb_game_1(3),

		game_a         => usb_game_1(4),
		game_b         => usb_game_1(5),
		game_x         => usb_game_1(6),
		game_y         => usb_game_1(7),
		game_sel       => usb_game_1(8),
		game_sta       => usb_game_1(9),

		game_extra     => usb_game_1(13 downto 10),

		dbg_hid_report => hid_report_1,
		dbg_hid_regs   => open
	);

	process (usbclk, n_reset)
	begin
		if n_reset = '0' then
			usbreset_sync1 <= '1';
			usbreset_sync2 <= '1';

		elsif rising_edge(usbclk) then
			usbreset_sync1 <= '0';
			usbreset_sync2 <= usbreset_sync1;
		end if;
	end process;

	-- Convert pulses to toggles in usbclk domain so they survive CDC regardless of pulse width
	process (usbclk, n_reset)
	begin
		if n_reset = '0' then
			full_report_toggle <= (others => '0');

		elsif rising_edge(usbclk) then
			if usb_full_report_0 = '1' then full_report_toggle(0) <= not full_report_toggle(0); end if;
			if usb_full_report_1 = '1' then full_report_toggle(1) <= not full_report_toggle(1); end if;
		end if;
	end process;

	-- 3-stage shift-register sync in sysclk domain; bit(1) xor bit(2) gives a one-cycle set pulse
	process (sysclk, n_reset)
	begin
		if n_reset = '0' then
			hid_sync <= (others => (others => '0'));

		elsif rising_edge(sysclk) then
			for i in 0 to 1 loop
				hid_sync(i) <= hid_sync(i)(1 downto 0) & full_report_toggle(i);
			end loop;
		end if;
	end process;

	process (sysclk, n_reset) begin
		if n_reset = '0' then
			hid_report_ready_0 <= '0';

		elsif rising_edge(sysclk) then
			if hid_sync(0)(1) /= hid_sync(0)(2) then
				hid_report_ready_0 <= '1';
			end if;

			if hid_report_ack_0 = '1' then
				hid_report_ready_0 <= '0';
			end if;
		end if;
	end process;

	process (sysclk, n_reset) begin
		if n_reset = '0' then
			hid_report_ready_1 <= '0';

		elsif rising_edge(sysclk) then
			if hid_sync(1)(1) /= hid_sync(1)(2) then
				hid_report_ready_1 <= '1';
			end if;

			if hid_report_ack_1 = '1' then
				hid_report_ready_1 <= '0';
			end if;
		end if;
	end process;

	process (sysclk) begin
		if rising_edge(sysclk) then
			hid_report_ack_0 <= '0';

			if usb_select_0 = '1' and req = '1' then
				if wr = '1' then
					case addr(3 downto 2) is
						when "00" =>
							if d(2) = '1' then
								hid_report_ack_0 <= '1';
							end if;
						when others =>
							null;
					end case;
				else
					case addr(3 downto 2) is
						when "00" =>
							usbtohost_0(31 downto 16) <= "00" & usb_game_0;
							usbtohost_0(15 downto 3) <= (others => '0');
							usbtohost_0(2 downto 0) <= hid_report_ready_0 & usb_typ_0;
						when "01" =>
							usbtohost_0 <= hid_report_0(31 downto 0);
						when "10" =>
							usbtohost_0 <= hid_report_0(63 downto 32);
						when others =>
							null;
					end case;
				end if;
			end if;
		end if;
	end process;

	process (sysclk) begin
		if rising_edge(sysclk) then
			hid_report_ack_1 <= '0';

			if usb_select_1 = '1' and req = '1' then
				if wr = '1' then
					case addr(3 downto 2) is
						when "00" =>
							if d(2) = '1' then
								hid_report_ack_1 <= '1';
							end if;
						when others =>
							null;
					end case;
				else
					case addr(3 downto 2) is
						when "00" =>
							usbtohost_1(31 downto 16) <= "00" & usb_game_1;
							usbtohost_1(15 downto 3) <= (others => '0');
							usbtohost_1(2 downto 0) <= hid_report_ready_1 & usb_typ_1;
						when "01" =>
							usbtohost_1 <= hid_report_1(31 downto 0);
						when "10" =>
							usbtohost_1 <= hid_report_1(63 downto 32);
						when others =>
							null;
					end case;
				end if;
			end if;
		end if;
	end process;

	joya <= not (
		(usb_game_0(8) or usb_game_0_combined) &
		 usb_game_0(9)  &
		 usb_game_0(13) &
		 usb_game_0(11) &
		 usb_game_0(6)  &
		 usb_game_0(7)  &
		 usb_game_0(5)  &
		 usb_game_0(4)  &
		(usb_game_0(2) or usb_game_0(10)) &
		(usb_game_0(3) or usb_game_0(12)) &
		 usb_game_0(0)  &
		 usb_game_0(1)
	) when usb_typ_0 = "11" else (others => '1');

	joyb <= not (
		(usb_game_1(8) or usb_game_1_combined) &
		 usb_game_1(9)  &
		 usb_game_1(13) &
		 usb_game_1(11) &
		 usb_game_1(6)  &
		 usb_game_1(7)  &
		 usb_game_1(5)  &
		 usb_game_1(4)  &
		(usb_game_1(2) or usb_game_1(10)) &
		(usb_game_1(3) or usb_game_1(12)) &
		 usb_game_1(0)  &
		 usb_game_1(1)
	) when usb_typ_1 = "11" else (others => '1');

	usb_game_0_combined <= '1' when usb_game_0(7 downto 4) = "1111" else '0';
	usb_game_1_combined <= '1' when usb_game_1(7 downto 4) = "1111" else '0';

	usb_connected(0) <= '1' when usb_typ_0 /= "00" else '0';
	usb_connected(1) <= '1' when usb_typ_1 /= "00" else '0';

	usbreset <= usbreset_sync2;
end block;
end;
-- vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
