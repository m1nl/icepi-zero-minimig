library ieee;
use ieee.std_logic_1164.all;

package board_config is

	constant base_frequency : natural := 50e6;
	constant tg68k_datapath32 : std_logic_vector(2 downto 0) := "111";

end package;
