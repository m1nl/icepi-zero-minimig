-- Partial implementation of Akiko.
-- Copyright 2020, 2021 by Alastair M. Robinson
--
-- Contains the Chunky2Planar converter and ID register,
-- and an interface for handing off the remaining registers
-- to the host CPU.
--
-- Also hosts some extra registers for RTG and audio, even though they
-- don't logically belong here, to keep the logic footprint as small
-- as possible.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that they will
-- be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
-- of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity akiko is
generic
	(
		havertg : integer := 1;
		haveaudio : integer := 1;
		havec2p : integer := 1
	);
port (
	clk : in std_logic;
	reset_n : in std_logic;
	addr : in std_logic_vector(10 downto 0);
	req : in std_logic;
	wr : in std_logic;
	ack : out std_logic;
	d : in std_logic_vector(15 downto 0);
	q : out std_logic_vector(15 downto 0);
	-- Host interface
	host_req : out std_logic;
	host_ack : in std_logic;
	host_q : in std_logic_vector(15 downto 0);
	-- RTG signals
	rtg_reg_addr : out std_logic_vector(10 downto 0);
	rtg_reg_d : out std_logic_vector(15 downto 0);
	rtg_reg_wr : out std_logic;
	-- Audio signals
	audio_buf : in std_logic;
	audio_ena : out std_logic;
	audio_int : out std_logic
);
end entity;

architecture rtl of akiko is

signal id_q : std_logic_vector(15 downto 0);
signal id_sel : std_logic;
signal id_ack : std_logic;
signal ct_sel : std_logic;
signal ct_q : std_logic_vector(15 downto 0);
signal ct_ack : std_logic;

signal host_sel : std_logic;
signal host_ack_d : std_logic;

signal rtg_sel : std_logic;
signal rtg_ack : std_logic;
signal req_and_ct_sel : std_logic;

signal ahi_sel : std_logic;
signal ahi_q : std_logic_vector(15 downto 0);
signal audio_intena : std_logic;
signal audio_buf_d : std_logic;

begin

-- ID Register (assume C2P or audio is required to make Akiko visible)

id_sel <= '1' when addr(7 downto 2)=X"0"&"00" and (havec2p = 1 or haveaudio = 1) else '0';
id_q <= X"C0CA" when addr(1)='0' else X"CAFE";
id_ack<=req and id_sel;

req_and_ct_sel <= req and ct_sel;

-- Cornerturn for Chunky to Planar

ct_sel <= '1' when (addr(10 downto 8)="000" and addr(5 downto 2)="1110" and havec2p = 1) else '0';	-- Cornerturn at 0xb80038 with mirrors at 78, b8 and f8

c2p:
if havec2p=1 generate
myc2p: entity work.cornerturn
port map
(
	clk => clk,
	reset_n => reset_n,
	d => d,
	q => ct_q,
	wr => wr,
	req => req_and_ct_sel,
	ack => ct_ack
);
end generate;

noc2p:
if havec2p=0 generate
	ct_ack<='0';
end generate;

-- Host interface
-- Defer any requests not handled by the Cornerturn or RTG to the host CPU

host_sel <= not (rtg_sel or ahi_sel or ct_sel or id_sel);
host_req <= req and host_sel;

-- Audio registers

ahi_sel <= '1' when addr(10 downto 8)="010" and haveaudio = 1 else '0'; -- Audio registers at 0xb802xx

process(clk)
begin
	if rising_edge(clk) then
		if reset_n='0' then
			audio_intena<='0';
			audio_int<='0';
			audio_ena<='0';
		else
			-- Trigger an interrupt when the buffer flips
			audio_buf_d <= audio_buf;
			if audio_buf_d /= audio_buf then
				audio_int<=audio_intena;
			end if;

			if ahi_sel='1' and req='1'	then
				if wr='1' then	-- Write cycle
					case addr(4 downto 1) is
						when X"0" =>
							audio_ena <= d(0);
							audio_int <= '0'; -- Clear interrupt on write
							audio_intena <= d(1);
						when others =>
							null;
					end case;
				else	-- Read cycle
					ahi_q(15 downto 1)<=(others=>'0');
					ahi_q(0)<=audio_buf;
				end if;
			end if;
		end if;
	end if;
end process;

-- RTG registers and CLUT

rtg_sel <= '1' when (addr(10)='1' or addr(9 downto 8)="01") and havertg = 1 else '0';	-- RTG registers at 0xb801xx

rtg_ack <=req and rtg_sel;

process(clk)
begin
	if rising_edge(clk) then
		rtg_reg_wr<='0';

		-- RTG registers, includes a secondary framebuffer address to support
		-- screen dragging.
		if req='1' and wr='1' then
			if rtg_sel='1' then
				rtg_reg_wr<='1';
				rtg_reg_addr<=addr(10 downto 0);
				rtg_reg_d<=d;
			end if;
		end if;
	end if;
end process;


-- CPU read cycles

q <=
	ct_q when ct_sel='1'
	else host_q when host_sel='1'
	else ahi_q when ahi_sel='1'
	else id_q when id_sel='1'
	else X"8321" when rtg_sel='1' -- just ID number from RTG registers
	else X"ffff";

process(clk)
begin
	if rising_edge(clk) then
		if host_ack='1' then
			host_ack_d<='1';
		end if;
		if (req and host_sel)='0' then
			host_ack_d<='0';
		end if;

		ack <= ct_ack or id_ack or rtg_ack or host_ack_d;

	end if;
end process;

end architecture;

