library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity minimig_autoconfig_rom is
port (
	clk : in std_logic;
	d : in std_logic_vector(3 downto 0);
	a_read : in std_logic_vector(8 downto 0);
	a_write : in std_logic_vector(8 downto 0);
	we : in std_logic;
	q : out std_logic_vector(3 downto 0)
);
end entity;

architecture rtl of minimig_autoconfig_rom is
	constant z2base : integer := 16#00#;
	constant z3base: integer := 16#40#;
	constant z3base2: integer := 16#80#;
	constant z3base3: integer := 16#c0#;
	constant ethbase: integer := 16#100#;
	constant sndbase: integer := 16#140#;
	constant ctrlbase: integer := 16#180#;
	type storage is array(0 to (2**9)-1) of std_logic_vector(3 downto 0);
	signal ram : storage := (
		-- Use the upper two bits as an index
		-- so 00 is ZII RAM, 01 is ZIII RAM and 10 is ETH
		-- with a NULL board at 11 to terminate the chain.

		-- Up to 8 meg of 24-bit Fast RAM

		 z2base+16#0#  => "1110",	-- Zorro-II card, add mem, no ROM
		 z2base+16#2#/2  => "0000",	-- 0110 => 2MB, 0111 => 4MB, 0000 => 8MB
		 z2base+16#10#/2  => "1110",	-- Manufacturer ID: 0x139c
		 z2base+16#12#/2  => "1100",
		 z2base+16#14#/2  => "0110",
		 z2base+16#16#/2  => "0011",
		 z2base+16#26#/2  => "1110",	-- Serial no: 1


		-- 16 or 64 meg of 32-bit Fast RAM

		 z3base+16#0#  => "1010",	-- Zorro-III card, add mem, no ROM
		 z3base+16#2#/2  => "0000",	-- 8MB (extended to 16 in reg 08)
		 z3base+16#4#/2  => "1110",	-- ProductID = 0x10 (only setting upper nybble)
		 z3base+16#8#/2  => "0000",	-- Memory card, not silenceable, extended size (16 meg), reserved
		 z3base+16#a#/2  => "1111",	-- 0000 - logical size matches physical size
		 z3base+16#10#/2  => "1110",	-- Manufacturer ID: 0x139c
		 z3base+16#12#/2  => "1100",
		 z3base+16#14#/2  => "0110",
		 z3base+16#16#/2  => "0011",
		 z3base+16#26#/2  => "1101",	-- Serial no: 2


		-- Extra 32 meg of RAM for 64-meg platforms

		 z3base2+16#0#  => "1010",	-- Zorro-III card, add mem, no ROM
		 z3base2+16#2#/2  => "0001",	-- 64kb (extended to 32 meg in reg 08)
		 z3base2+16#4#/2  => "1110",	-- ProductID = 0x11
		 z3base2+16#6#/2  => "1110",	-- ProductID = 0x11
		 z3base2+16#8#/2  => "0000",	-- Memory card, not silenceable, extended size (16 meg), reserved
		 z3base2+16#a#/2  => "1111",	-- 0000 - logical size matches physical size
		 z3base2+16#10#/2  => "1110",	-- Manufacturer ID: 0x1399
		 z3base2+16#12#/2  => "1100",
		 z3base2+16#14#/2  => "0110",
		 z3base2+16#16#/2  => "0110",
		 z3base2+16#26#/2  => "1011",	-- Serial no: 4


		-- 2 or 4 meg of 32-bit Fast RAM (unused RAM in Bank 0)

		 z3base3+16#0#  => "1010",	-- Zorro-III card, add mem, no ROM
		 z3base3+16#2#/2  => "0000",	-- 8MB (extended to 16 in reg 08, actual size specified in reg 0a)
		 z3base3+16#4#/2  => "1110",	-- ProductID = 0x11
		 z3base3+16#6#/2  => "1110",	-- ProductID = 0x11
		 z3base3+16#8#/2  => "0010",	-- Memory card, not silenceable, reserved
		 z3base3+16#a#/2  => "1000",	-- 0111 - 2 meg
		 z3base3+16#10#/2  => "1110",	-- Manufacturer ID: 0x1399
		 z3base3+16#12#/2  => "1100",
		 z3base3+16#14#/2  => "0110",
		 z3base3+16#16#/2  => "0110",
		 z3base3+16#26#/2  => "1100",	-- Serial no: 3


		-- Ethernet

		 ethbase+16#0#  => "1000",	-- Zorro-III card, no link, no ROM
		 ethbase+16#2#/2  => "0001",	-- Next board not related, size 16#40k
		 ethbase+16#4#/2  => "1101",	-- ProductID = 0x20 (only setting upper nybble)
		 ethbase+16#8#/2  => "1110",	-- Not memory, silenceable, normal size, Zorro III
		 ethbase+16#a#/2  => "1101",	-- logical size 16#40k
		 ethbase+16#10#/2  => "1110",	-- Manufacturer ID: 0x139c
		 ethbase+16#12#/2  => "1100",
		 ethbase+16#14#/2  => "0110",
		 ethbase+16#16#/2  => "0011",
		 ethbase+16#26#/2  => "1100",	-- Serial no: 3

		-- Toccata sound card

		 sndbase+16#0#  => "1100",    -- Zorro-II card, no link, no ROM
		 sndbase+16#2#/2  => "0001",  -- Next board not related, size 'h64k
		-- Inverted from here on
		 sndbase+16#6#/2  => "0011",  -- Lower byte product number
		 sndbase+16#a#/2  => "1111",  -- logical size matches physical size
		 sndbase+16#10#/2  => "1011", -- Manufacturer ID: 0x4754
		 sndbase+16#12#/2  => "1000",
		 sndbase+16#14#/2  => "1010",
		 sndbase+16#16#/2  => "1011",

		-- Minimig Control board

		 ctrlbase+16#0#  => "1100",    -- Zorro-II card, no link, no ROM
		 ctrlbase+16#2#/2  => "0001",  -- Next board not related, size 16#64k
		-- Inverted from here on
		 ctrlbase+16#4#/2  => "1110",	-- ProductID = 0x11
		 ctrlbase+16#6#/2  => "1101",	-- ProductID = 0x12
		 ctrlbase+16#a#/2  => "1111",  -- logical size matches physical size
		 ctrlbase+16#10#/2  => "1110",	-- Manufacturer ID: 0x1399
		 ctrlbase+16#12#/2  => "1100",
		 ctrlbase+16#14#/2  => "0110",
		 ctrlbase+16#16#/2  => "0110",
		others => "1111"
	);

	signal q_loc : std_logic_vector(3 downto 0);
	signal a_loc : unsigned(8 downto 0);
begin

process(clk) begin
	if rising_edge(clk) then
		a_loc<=unsigned(a_read);
		if we='1' then
			ram(to_integer(unsigned(a_write))) <= d;
		end if;
		q_loc<=ram(to_integer(a_loc));
	end if;
end process;

q <= q_loc;

end architecture;
