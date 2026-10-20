library ieee;
use ieee.std_logic_1164.all;

library work;
use work.board_config.all;

entity amiga_clk_lattice_pll is
port (
  areset : in std_logic;
  inclk0 : in std_logic;
  c0 : out std_logic;
  c1 : out std_logic;
  c2 : out std_logic;
  c3 : out std_logic;
  c4 : out std_logic;
  locked : out std_logic
);
end entity;

architecture rtl of amiga_clk_lattice_pll is
  signal clocks_a : std_logic_vector(3 downto 0);
begin

  -- E5-only: 52 MHz feedback, 572 MHz VCO, and /5, /20, /4 outputs.
  -- CLKOP is reserved for feedback; the two 28.6 MHz consumers share CLKOS2.
  clk0 : entity work.ecp5pll
  generic map
  (
        in_Hz => natural( base_frequency ),
      out0_Hz => natural( 52.0e6 ),                out0_tol_hz => 0,
      out1_Hz => natural(114.4e6 ), out1_deg => 0, out1_tol_hz => 0,
      out2_Hz => natural( 28.6e6 ), out2_deg => 0, out2_tol_hz => 0,
      out3_Hz => natural(143.0e6 ), out3_deg => 0, out3_tol_hz => 0

  )
  port map
  (
    clk_i   => inclk0,
    clk_o   => clocks_a,
    locked  => locked
  );
  c0 <= '0';
  c1 <= clocks_a(1);
  c2 <= clocks_a(2);
  c3 <= clocks_a(2);
  c4 <= clocks_a(3);

end architecture;

