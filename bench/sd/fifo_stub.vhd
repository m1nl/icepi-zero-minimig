-- GPL-3.0-or-later. Inert binding for the unused AUX FIFO; AUX SPI is disabled.
library ieee;
use ieee.std_logic_1164.all;
entity circular_fifo is
 generic(WIDTH:integer:=8;DEPTH:integer:=8);
 port(clk,rst,wr_en:in std_logic;din:in std_logic_vector(WIDTH-1 downto 0);rd_ack:in std_logic;dout:out std_logic_vector(WIDTH-1 downto 0);empty:out std_logic);
end;
architecture unused of circular_fifo is begin dout<=(others=>'0');empty<='1';end;
