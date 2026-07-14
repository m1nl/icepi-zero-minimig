library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity soc_firmware is
generic	(
	NB_COL : integer := 4;
	COL_WIDTH : integer :=8;
	maxAddrBitBRAM  : integer := 8 -- ROM's address width (words, not bytes)
	);
port (
	clk : in std_logic;
	reset_n : in std_logic := '1';
	addr : in std_logic_vector(maxAddrBitBRAM -2 downto 0);
	q : out std_logic_vector(31 downto 0);
	-- Allow writes - defaults supplied to simplify projects that don't need to write.
	d : in std_logic_vector(31 downto 0) := X"00000000";
	we : in std_logic := '0';
	bytesel : in std_logic_vector(3 downto 0) := "1111"
);
end entity;

architecture arch of soc_firmware is

-- type word_t is std_logic_vector(31 downto 0);
type ram_type is array (0 to 2 ** (maxAddrBitBRAM-1)  - 1) of std_logic_vector(31 downto 0);

signal ram : ram_type :=
(

