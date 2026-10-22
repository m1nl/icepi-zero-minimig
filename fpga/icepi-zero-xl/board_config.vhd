library ieee;
use ieee.std_logic_1164.all;

package board_config is

	constant base_frequency : natural := 50e6;

	-- Optional pair transfers: bit 0=data, bit 1=immediate, bit 2=absolute address.
	constant tg68k_datapath32 : std_logic_vector(2 downto 0) := "111";

	-- Reduce the regular TG68K internal cycle length to 3
	constant tg68k_short_internal_cycle : boolean := true;

end package;
