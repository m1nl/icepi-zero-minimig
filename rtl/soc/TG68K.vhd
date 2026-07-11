------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2011 Tobias Gubener                                   --
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This is the TOP-Level for TG68KdotC_Kernel to generate 68K Bus signals   --
-- It also includes glue logic for non-standard non-minimig components      --
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity TG68K is
generic (
		havertg : integer := 1;
		haveaudio : integer := 1;
		havec2p : integer := 1;
		haveamigahost : integer := 1;
		havecart : integer := 1;
		dualsdram : integer := 0;
		useprofiler : integer := 0;
		usethrottle : integer := 1
);
port (
	clk           : in      std_logic;
	reset         : in      std_logic;
	clkena_in     : in      std_logic:='1';
	IPL           : in      std_logic_vector(2 downto 0):="111";
	dtack         : in      std_logic;
	freeze        : in      std_logic:='0';
	vpa           : in      std_logic:='1';
	ein           : in      std_logic:='1';
	addr          : out     std_logic_vector(31 downto 0);
	data_read     : in      std_logic_vector(15 downto 0);
	data_read2    : in      std_logic_vector(15 downto 0);
	data_write    : out     std_logic_vector(15 downto 0);
	data_write2   : out     std_logic_vector(15 downto 0);
	fast_rd       : buffer  std_logic;
	as            : out     std_logic;
	uds           : out     std_logic;
	lds           : out     std_logic;
	uds2          : out     std_logic;
	lds2          : out     std_logic;
	rw            : out     std_logic;
	vma           : buffer  std_logic:='1';
	ena7RDreg     : in      std_logic:='1';
	ena7WRreg     : in      std_logic:='1';
	fromram       : in      std_logic_vector(15 downto 0);
	toram         : out     std_logic_vector(15 downto 0);
	ramready      : in      std_logic:='0';
	overclock     : in      std_logic:='0';
	cpu           : in      std_logic_vector(1 downto 0);
	ziiram_active : in      std_logic;
	ziiiram_active : in     std_logic;
	ziiiram2_active : in     std_logic;
	ziiiram3_active : in     std_logic;

	eth_en        : in      std_logic:='0';
	sel_eth       : buffer  std_logic;
	frometh       : in      std_logic_vector(15 downto 0);
	ethready      : in      std_logic;
	slow_config   : in      std_logic_vector(1 downto 0);
	aga           : in      std_logic;
	turbochipram  : in      std_logic;
	turbokick     : in      std_logic;
	cache_inhibit : out     std_logic;
	cacheline_clr : out     std_logic;
	--	ovr           : in      std_logic;
	ramaddr       : out     std_logic_vector(31 downto 0);
	cpustate      : out     std_logic_vector(3 downto 0);
--	chipset_ramsel: out     std_logic;
	nResetOut     : buffer  std_logic;
	--	cpuDMA        : buffer  std_logic;
	ramlds        : out     std_logic;
	ramuds        : out     std_logic;
	CACR_out      : buffer  std_logic_vector(3 downto 0);
	VBR_out       : buffer  std_logic_vector(31 downto 0);
	-- RTG interface
	rtg_reg_addr : out std_logic_vector(10 downto 0);
	rtg_reg_d    : out std_logic_vector(15 downto 0);
	rtg_reg_wr   : out std_logic;
	-- Audio interface
	audio_buf    : in std_logic;
	audio_ena    : out std_logic;
	audio_int    : out std_logic;
	-- Host interface
	host_addr    : in std_logic_vector(7 downto 0);
	host_req     : out std_logic;
	host_ack     : in std_logic;
	host_wr      : out std_logic;
	host_q       : in std_logic_vector(15 downto 0);
	host_d       : out std_logic_vector(15 downto 0)
);
end TG68K;

architecture logic of TG68K is

signal addrtg68         : std_logic_vector(31 downto 0);
signal cpuaddr          : std_logic_vector(31 downto 0);
signal r_data           : std_logic_vector(15 downto 0);
signal cpuIPL           : std_logic_vector(2 downto 0);

signal clkena_e         : std_logic;
signal clkena_f         : std_logic;
signal wr_n             : std_logic;
signal uds_in           : std_logic;
signal lds_in           : std_logic;
signal state            : std_logic_vector(1 downto 0);
signal longword         : std_logic;
signal clkena_akiko     : std_logic;
signal clkena           : std_logic;
signal sel_ram          : std_logic;
signal ram_req          : std_logic;
signal sel_chip         : std_logic;
signal sel_chipram      : std_logic;
signal overclock_d      : std_logic := '0';
signal turbochip_d      : std_logic := '0';
signal turbokick_d      : std_logic := '0';
signal slow_config_d    : std_logic_vector(1 downto 0);
signal turboslow_d      : std_logic := '0';
signal slower           : std_logic_vector(3 downto 0);
signal skipfetch        : std_logic := '0';

signal datatg68_c       : std_logic_vector(15 downto 0);
signal datatg68         : std_logic_vector(15 downto 0);
signal w_datatg68       : std_logic_vector(15 downto 0);
signal ramcs_n          : std_logic;

signal z2ram_ena        : std_logic;
signal z3ram_ena        : std_logic;
signal z3ram2_ena       : std_logic;
signal z3ram3_ena       : std_logic;
signal eth_base         : std_logic_vector(7 downto 0);
signal eth_cfgd         : std_logic;
signal sel_z2ram        : std_logic;
signal sel_z3ram        : std_logic;
signal sel_z3ram2       : std_logic;
signal sel_z3ram3       : std_logic;
signal sel_kick         : std_logic;
signal sel_kickram      : std_logic;
signal sel_slow         : std_logic;
signal sel_slowram      : std_logic;
signal sel_cart         : std_logic;
signal sel_32           : std_logic;
signal sel_undecoded    : std_logic;
signal sel_undecoded_d  : std_logic;
signal sel_akiko        : std_logic;
signal sel_akiko_d      : std_logic;
signal sel_host         : std_logic;
signal sel_host_d       : std_logic;
signal sel_audio        : std_logic;
signal sel_gayle_ide    : std_logic;

signal cpu_mode         : std_logic_vector(1 downto 0);
signal cpu_internal     : std_logic;
signal cpu_fetch        : std_logic;
signal cpu_read         : std_logic;
signal cpu_write        : std_logic;
signal cpu_disablecache : std_logic;

-- Akiko registers
signal akiko_d          : std_logic_vector(15 downto 0);
signal akiko_q          : std_logic_vector(15 downto 0);
signal akiko_wr         : std_logic;
signal akiko_req        : std_logic;
signal akiko_ack        : std_logic;

-- Host ACK delayed (because we register output)
signal host_ack_d       : std_logic;

-- Throttling
signal block_turbo      : std_logic := '0';
signal throttle_sel     : std_logic_vector(1 downto 0);

-- HRTMon
signal sel_nmi_vector   : std_logic;

component profile_cpu
port (
	clk        : in std_logic;
	reset_n    : in std_logic;
	clkena     : in std_logic;
	cpustate   : in std_logic_vector(1 downto 0);
	sel_chip   : in std_logic;
	sel_kick   : in std_logic;
	sel_fast24 : in std_logic;
	sel_fast32 : in std_logic
);
end component;

component akiko
port (
	clk     : in  std_logic;
	reset_n : in  std_logic;
	addr    : in  std_logic_vector(5 downto 0);
	wr      : in  std_logic;
	req     : in  std_logic;
	ack     : out std_logic;
	d       : in  std_logic_vector(15 downto 0);
	q       : out std_logic_vector(15 downto 0)
);
end component;

begin

sel_eth <= '0';

-- AMR just for convenience / clarity
cpu_fetch    <= '1' when state="00" else '0';
cpu_internal <= '1' when state="01" or skipfetch='1' else '0';
cpu_read     <= '1' when state="10" else '0';
cpu_write    <= '1' when state="11" else '0';
cpu_disablecache <= not CACR_out(0);

-- NMI handling for HRTMon cartridge
gen_nmi: if havecart=1 generate
	nmiblock : block
		signal NMI_addr            : std_logic_vector(31 downto 0);
		signal sel_nmi_vector_addr : std_logic;
	begin
		-- NMI
		process(reset, clk,VBR_out) begin
			if reset='0' then
				NMI_addr <= X"0000007c";
				sel_nmi_vector_addr <= '0';
			elsif rising_edge(clk) then
				NMI_addr <= VBR_out + X"0000007c";
				sel_nmi_vector_addr <= '0';
				if (cpuaddr(31 downto 2)=NMI_addr(31 downto 2)) then
					sel_nmi_vector_addr <= '1';
				end if;
			end if;
		end process;

		sel_nmi_vector <= '1' when sel_nmi_vector_addr='1' and cpu_read='1' else '0';
	end block;
end generate;

no_nmi: if havecart=0 generate
	sel_nmi_vector <= '0';
end generate;

--

process(clk) begin
	if rising_edge(clk) then
		if (reset='0' or nResetOut='0') then
			sel_akiko_d <= '0';

			sel_host_d <= '0';
			host_ack_d <= '0';

			ram_req <= '0';
			sel_undecoded_d <= '0';
		else
			sel_akiko_d <= sel_akiko;

			sel_host_d <= sel_host;
			host_ack_d <= host_ack;

			ram_req <= sel_ram and NOT block_turbo and NOT sel_nmi_vector and NOT cpu_internal;
			sel_undecoded_d <= sel_32 and not sel_ram;
		end if;
	end if;
end process;

datatg68 <= fromram when ram_req='1' else akiko_q when sel_akiko_d='1' else datatg68_c;
toram <= w_datatg68;

-- Register incoming data
process(clk) begin
	if rising_edge(clk) then
		if (reset='0' or nResetOut='0' or sel_undecoded_d ='1') then
			datatg68_c <= X"FFFF";
		elsif sel_host_d='1' then
			datatg68_c <= host_q;
		elsif sel_eth='1' then
			datatg68_c <= frometh;
		else
			datatg68_c <= r_data;
		end if;
	end if;
end process;

DUALRAM_ZIII: if dualsdram=1 generate
-- First block of ZIII RAM - 0x40000000 - 0x43ffffff
	sel_z3ram       <= '1' when (cpuaddr(31 downto 30)="01") and cpuaddr(26)='0' else '0';
-- Second block of ZIII RAM - 32 meg from 0x44000000 - 0x45ffffff
-- Also matches third block, 16 meg from 0x46000000 - 0x46ffffff, but excludes 0x47000000 onwards since it would alias onto Bank 0 / chipram
	sel_z3ram2      <= '1' when (cpuaddr(31 downto 30)="01") and cpuaddr(26)='1' else '0';
-- Third block of ZIII RAM - either 2 or 4 meg, starting at either 0x41000000 or 0x44000000
	sel_z3ram3      <= '0';
end generate;

SINGLERAM_ZIII: if dualsdram=0 generate
-- First block of ZIII RAM - 0x40000000 - 0x40ffffff
	sel_z3ram       <= '1' when (cpuaddr(31 downto 30)="01") and cpuaddr(26 downto 24)="000" else '0';
-- Second block of ZIII RAM - 32 meg from 0x42000000 - 0x43ffffff
	sel_z3ram2      <= '1' when (cpuaddr(31 downto 30)="01") and cpuaddr(25)='1' else '0';
-- Third block of ZIII RAM - either 2 or 4 meg, starting at either 0x41000000 or 0x44000000
	sel_z3ram3      <= '1' when (cpuaddr(31 downto 30)="01") and (cpuaddr(26)='1' or cpuaddr(25 downto 24)="01") else '0';
end generate;

sel_gayle_ide <= '0'; -- '1' when state(1 downto 0)="10" and cpuaddr(31 downto 14)=X"00DA"&"00" else '0';
sel_akiko <= '1' when (cpuaddr(31 downto 12)=X"00B80" and (havec2p=1)) else '0'; -- $B80xxx
sel_host <= '1' when (cpuaddr(31 downto 12)=X"00B81" and (haveamigahost=1)) else '0'; -- $B81xxx
sel_32 <= '1' when cpu(1)='1' and cpuaddr(31 downto 24)/=X"00" and cpuaddr(31 downto 24)/=X"ff" else '0'; -- Decode 32-bit space, but exclude interrupt vectors
sel_z2ram <= '1' when (cpuaddr(31 downto 24)=X"00") and
		((cpuaddr(23 downto 21)="001") or
		(cpuaddr(23 downto 21)="010") or
		(cpuaddr(23 downto 21)="011") or
		(cpuaddr(23 downto 21)="100")) else '0';
--	sel_eth         <= '1' when (cpuaddr(31 downto 24)=eth_base) and eth_cfgd='1' else '0';
sel_chip        <= '1' when (cpuaddr(31 downto 24)=X"00") and (cpuaddr(23 downto 21)="000") else '0'; -- $000000 - $1FFFFF
sel_chipram     <= '1' when sel_chip='1' and turbochip_d='1' else '0';
sel_kick        <= '1' when (cpuaddr(31 downto 24)=X"00") and ((cpuaddr(23 downto 19)="11111") or (cpuaddr(23 downto 19)="11100")) and cpu_write='0' else '0'; -- $F8xxxx, $E0xxxx
sel_kickram     <= '1' when sel_kick='1' and turbokick_d='1' else '0';
sel_slow        <= '1' when (cpuaddr(31 downto 24)=X"00") and ((cpuaddr(23 downto 20)=X"C" and ((cpuaddr(19)='0' and slow_config_d/="00") or (cpuaddr(19)='1' and slow_config_d(1)='1'))) or (cpuaddr(23 downto 19)=X"D"&'0' and slow_config_d="11")) else '0'; -- $C00000 - $D7FFFF
sel_slowram     <= '1' when sel_slow='1' and turboslow_d='1' else '0';
sel_cart        <= '1' when (cpuaddr(31 downto 24)=X"00") and (cpuaddr(23 downto 20)="1010") else '0'; -- $A00000 - $A7FFFF (actually matches up to $AFFFFF)
sel_audio       <= '1' when (cpuaddr(31 downto 24)=X"00") and (cpuaddr(23 downto 18)="111011") else '0'; -- $EC0000 - $EFFFFF
--	sel_undecoded   <= '1' when sel_32='1' and (sel_z3ram and z3ram_ena)='0' and (sel_z3ram2 and z3ram2_ena)='0' and (sel_z3ram3 and z3ram3_ena)='0' else '0';
sel_ram         <= '1' when (
	(sel_z2ram='1' and z2ram_ena='1') or
	(sel_z3ram='1' and z3ram_ena='1') or
	(sel_z3ram2='1' and z3ram2_ena='1') or
	(sel_z3ram3='1' and z3ram3_ena='1') or
	sel_chipram='1' or
	sel_slowram='1' or
	sel_kickram='1' or
	sel_audio='1') else '0';

ramcs_n <= '0' when ram_req='1' and slower(1)='0' and skipfetch='0' else '1';
cpustate <= longword&ramcs_n&state(1 downto 0);
ramlds <= lds_in;
ramuds <= uds_in;

-- This is the mapping to the SDRAM
-- map $00-$1F to $00-$1F (chipram), $A0-$FF to $20-$7F. All non-fastram goes into the first
-- 8M block (i.e. SDRAM bank 0). This map should be the same as in minimig_sram_bridge.v
-- 8M Zorro II RAM $20-9F goes to $80-$FF (SDRAM bank 1)

-- Boolean logic can handle this mapping.  Furthermore, applying the same
-- mapping to the other three banks is harmless, so there's no point expending logic
-- to make it specific to the first bank.

-- ABCD  B|C  A^(B|C)
--
-- 0000  0    0       0 -> 0
--
-- 0010  1    1       2 -> A
-- 0100  1    1       4 -> C
-- 0110  1    1       6 -> E
-- 1000  0    1       8 -> 8
--
-- 1010  1    0       A -> 2
-- 1100  1    0       C -> 4
-- 1110  1    0       E -> 6

-- On 64-meg platforms we need an extra 32 meg merged into the memory map.
-- If we configure that range second, it should end up in 42000000 - 43ffffff
-- so the extra 2 or 4 meg will end up at either 41000000 or 4400000, depending
-- on whether the extra 32 meg is configured.

-- addr(25) will be high only when 32-meg block is active
-- addr(24) will be high for the 16-meg block or the second half of the 32-meg block

-- The extra ZIII mapping maps 41000000 -> 200000, (or 44000000 -> 200000)
-- bits 23 downto 20 are mapped like so:
-- 0000->0010 (1st 2 meg), 0010->0100 (2nd 2 meg),
-- 0100->0010 (3rd 2 meg, aliases 1st), 0110->0100 (4th 2 meg, aliases 2nd),
-- addr(23) <= addr(23) and not sel_ziii_3;
-- addr(22) <= (addr(22) and not sel_ziii_3) or (addr(21) and sel_ziii_3);
-- addr(21) <= addr(21) xor sel_ziii_3;

DUALRAM_ADDR: if dualsdram=1 generate
-- With dual SDRAM setups we have 2 64 meg RAMs, and memory configured like so:
-- 64 meg from 0x40000000 to 0x43ffffff - bit 30 set, bit 26 clr, bit 25 d/c  =>  26 set, 25 src, 24 src
-- 32 meg from 0x44000000 to 0x45ffffff - bit 30 set, bit 26 set, bit 25 clr  =>  26 clr, 25 set, 24 d/c
-- 16 meg from 0x46000000 to 0x46ffffff - bit 30 set, bit 26 set, bit 25 set  =>  26 clr, 25 clr, 24 set
	ramaddr(31 downto 27) <= "00000";
	ramaddr(26) <= sel_z3ram;
	ramaddr(25) <= cpuaddr(25) xor sel_z3ram2; -- Second block of 32 meg in 1st SDRAM.
	ramaddr(24) <= cpuaddr(24) xor cpuaddr(25);
	ramaddr(23) <= (cpuaddr(23) xor (cpuaddr(22) or cpuaddr(21))) and not sel_z3ram3; -- ZII address mangling (disabled for RAM overlaid with trapdoor RAM.)
	ramaddr(22) <= cpuaddr(21) when sel_z3ram3='1' else cpuaddr(22);
	ramaddr(21) <= cpuaddr(21) xor sel_z3ram3;
	ramaddr(20 downto 0) <= cpuaddr(20 downto 0);
end generate;

SINGLERAM_ADDR: if dualsdram=0 generate
	ramaddr(31 downto 26) <= "000000";
	ramaddr(25) <= sel_z3ram2; -- Second block of 32 meg
	ramaddr(24) <= (cpuaddr(24) and sel_z3ram2) or sel_z3ram; -- Remap the first block of Zorro III RAM to 0x1000000
	ramaddr(23) <= (cpuaddr(23) xor (cpuaddr(22) or cpuaddr(21))) and not sel_z3ram3;
	ramaddr(22) <= cpuaddr(21) when sel_z3ram3='1' else cpuaddr(22);
	ramaddr(21) <= cpuaddr(21) xor sel_z3ram3;
	ramaddr(20 downto 0) <= cpuaddr(20 downto 0);
end generate;

-- 32bit address space for 68020, limit address space to 24bit for 68000/68010/68EC020.
cpuaddr <= addrtg68 when cpu="11" else X"00" & addrtg68(23 downto 0);
cpu_mode <= cpu(1) & (cpu(1) or cpu(0));

pf68K_Kernel_inst: entity work.TG68KdotC_Kernel
	generic map (
		SR_Read         => 2, -- 0=>user,   1=>privileged,    2=>switchable with CPU(0)
		VBR_Stackframe  => 2, -- 0=>no,     1=>yes/extended,  2=>switchable with CPU(0)
		extAddr_Mode    => 2, -- 0=>no,     1=>yes,           2=>switchable with CPU(1)
		MUL_Mode        => 2, -- 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,
		DIV_Mode        => 2, -- 0=>16Bit,  1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,
		BitField        => 2, -- 0=>no,     1=>yes,           2=>switchable with CPU(1)
		MUL_Hardware    => 1  -- 0=>no,     1=>yes
	)
	PORT MAP (
		clk             => clk,           -- : in std_logic;
		nReset          => reset,         -- : in std_logic:='1';      --low active
		clkena_in       => clkena,        -- : in std_logic:='1';
		data_in         => datatg68,      -- : in std_logic_vector(15 downto 0);
		IPL             => cpuIPL,        -- : in std_logic_vector(2 downto 0):="111";
		IPL_autovector  => '1',           -- : in std_logic:='0';
		CPU             => cpu_mode,
		regin_out       => open,          -- : out std_logic_vector(31 downto 0);
		addr_out        => addrtg68,      -- : buffer std_logic_vector(31 downto 0);
		data_write      => w_datatg68,    -- : out std_logic_vector(15 downto 0);
		busstate        => state,         -- : buffer std_logic_vector(1 downto 0);
		longword        => longword,
		nWr             => wr_n,          -- : out std_logic;
		nUDS            => uds_in,
		nLDS            => lds_in,        -- : out std_logic;
		nResetOut       => nResetOut,
		skipFetch       => skipFetch,     -- : out std_logic
		CACR_out        => CACR_out,
		VBR_out         => VBR_out
	);

process (clk) begin
	if rising_edge(clk) then
		if (reset='0' or nResetOut='0') then
			z2ram_ena <= '0';
			z3ram_ena <= '0';
			z3ram2_ena <= '0';
			z3ram3_ena <= '0';
			slow_config_d <= "00";

			overclock_d <= '0';
			turbochip_d <= '0';
			turbokick_d <= '0';
			turboslow_d <= '0';

			cacheline_clr <= '0';

		elsif (cpu_internal='1' and slower(0)='0') then
			z2ram_ena <= ziiram_active;
			z3ram_ena <= ziiiram_active;
			z3ram2_ena <= ziiiram2_active;
			z3ram3_ena <= ziiiram3_active;
			slow_config_d <= slow_config;

			overclock_d <= overclock;
			turbochip_d <= turbochipram;
			turbokick_d <= turbokick;
			turboslow_d <= turbochipram;

			cacheline_clr <= (turbochipram XOR turbochip_d) or (turbokick XOR turbokick_d);
		end if;
	end if;
end process;

u_akiko: akiko
port map
(
	clk => clk,
	reset_n => reset,
	addr => cpuaddr(5 downto 0),
	wr => akiko_wr,
	req => akiko_req,
	ack => akiko_ack,
	d => akiko_d,
	q => akiko_q
);

akiko_req <= '1' when sel_akiko_d='1' and slower(0)='0' and (cpu_write='1' or cpu_read='1') else '0';
akiko_wr <= '1' when cpu_write='1' else '0';
akiko_d <= w_datatg68;

host_req <= '1' when sel_host_d='1' and slower(0)='0' and (cpu_write='1' or cpu_read='1') else '0';
host_wr <= '1' when cpu_write='1' else '0';
host_d <= w_datatg68;

buslogic : block
	signal throttle         : std_logic_vector(2 downto 0);
	signal chipset_cycle    : std_logic;
	signal vpad             : std_logic;
	signal waitm            : std_logic;
	signal S_state          : std_logic_vector(1 downto 0);
	signal vmaena           : std_logic;
	signal eind             : std_logic;
	signal eindd            : std_logic;
	type   sync_states      is (sync0, sync1, sync2, sync3, sync4, sync5, sync6, sync7, sync8, sync9);
	signal sync_state       : sync_states;
	signal sel_chip_d       : std_logic;
	signal fast_rd_d        : std_logic;
	signal clkena_pre       : std_logic;
begin
	clkena <= '1' when slower(0)='0' and
			((clkena_in='1' and ((ena7RDreg='1' and clkena_e='1') or (ena7WRreg='1' and clkena_f='1') or fast_rd='1')) or
			cpu_internal='1' or sel_undecoded_d='1' or akiko_ack='1' or host_ack_d='1' or (ramready='1' and block_turbo='0')) else '0';

	-- AMR - attempt to imitate A1200 speed more closely on chipram fetches:
	-- Perform throttling of the CPU depending on turbo mode:  (Temporary mapping for evaluation)
	-- Turbo set to both: no throttling
	-- Turbo set to kick only: mild throttling
	-- Turbo set to chip only: more severe throttling
	-- Turbo set to none: severe throttling selected but has no effect since all chipram accesses go through the slow path.

	-- When throttling is enabled:
	--   Data reads to Chip RAM go through the slow path as normal
	--   Fetches go via the cache (unless CACR says otherwise) but the CPU is slowed by the throttling
	--   Writes go through the fast path (since real AGA hardware buffers writes.) but again the CPU is slowed by throttling.

	-- Need to decide how to handle C00000 RAM and Fast RAM in throttled modes
	--   For compatibility, C00000 RAM should probably run at chip RAM speeds
	--   Fast RAM should perhaps be throttled in Chip (i.e. A1200) mode, but not otherwise?

	process (clk) begin
		if rising_edge(clk) then
			if (reset='0' or nResetOut='0' or usethrottle=0) then
				throttle_sel <= "00";
			elsif clkena='1' then
				-- If throttling is enabled, block turbo for CPU data reads, and instruction fetch if cache is disabled.
				throttle_sel(0) <= freeze or (turbochipram xor turbokick);
				throttle_sel(1) <= freeze or (turbochipram and not turbokick);
			end if;
--			sel_chip_d  <= sel_chip;
			-- All contributing signals are valid 3 clocks after clkena, so valid after clkena+4
			block_turbo <= aga and sel_chip and throttle_sel(0) and (cpu_read or (cpu_fetch and cpu_disablecache));
--			cache_inhibit <= sel_kickram and aga and (throttle_sel(1) or throttle_sel(0));
		end if;
	end process;

	cache_inhibit <= '0';

	process (clk) begin
		if rising_edge(clk) then
			if (reset='0' or nResetOut='0' or usethrottle=0 or overclock_d='1') then
				throttle <= "000";
			elsif (clkena='1' or freeze='1') and cpu_write='0' and block_turbo='0' then
				if throttle_sel(1)='1' or (sel_chip='1' and throttle_sel(0)='1') then
					throttle <= "111";
				end if;
			elsif clkena_in='1' then
				throttle <= '0'&throttle(throttle'high downto 1);
			end if;
		end if;
	end process;

	process (clk) begin
		if rising_edge(clk) then
			if (reset='0' or nResetOut='0') then
				slower <= (others => '1');
			elsif clkena='1' then
				if overclock_d='1' then
					slower <= "0011";
				else
					slower <= throttle_sel(0)&"111"; -- AMR - in Turbo Chip and Kick modes allow one extra cycle for block_turbo etc to propagate
				end if;
			else
				slower <= (aga and throttle(0))&slower(slower'high downto 1); -- enaWRreg&slower(3 downto 1);
			end if;
		end if;
	end process;

	-- Block_turbo is only valid on the 4th cycle after clkena, but is only high when throttling is enabled, at which point
	-- slower(0) is guaranteed to be high for more than 4 cycles.
	-- When throttling chip-only cycles, block_turbo and sel_nmi_vector will prevent ram_cs going low, so their being late here shouldn't matter.
	chipset_cycle <= '1' when cpu_internal='0' and clkena_in='1' and slower(0)='0' and (sel_ram='0' or sel_nmi_vector='1' or block_turbo='1')
		 and sel_gayle_ide='0' and sel_akiko='0' and sel_host='0' and sel_undecoded_d='0' else '0';

	process (clk) begin
		if rising_edge(clk) then
			if ena7WRreg='1' then
				eind <= ein;
				eindd <= eind;
				case sync_state is
					when sync0  => sync_state <= sync1;
					when sync1  => sync_state <= sync2;
					when sync2  => sync_state <= sync3;
					when sync3  => sync_state <= sync4;
							 vma <= vpa;
					when sync4  => sync_state <= sync5;
					when sync5  => sync_state <= sync6;
					when sync6  => sync_state <= sync7;
					when sync7  => sync_state <= sync8;
					when sync8  => sync_state <= sync9;
					when others => sync_state <= sync0;
							 vma <= '1';
				end case;
				if eind='1' and eindd='0' then
					sync_state <= sync7;
				end if;
			end if;
		end if;
	end process;

	process (clk, reset) begin
		if reset='0' then
			S_state <= "00";
			as <= '1';
			rw <= '1';
			uds <= '1';
			lds <= '1';
			uds2 <= '1';
			lds2 <= '1';
			clkena_e <= '0';
			clkena_f <= '0';
			addr <= (others => '0');
			fast_rd <= '0';
			r_data <= (others => '0');
			data_write <= (others => '0');
			data_write2 <= (others => '0');
		elsif rising_edge(clk) then
			if S_state="01" and clkena_e='1' then
				uds2 <= uds_in;
				lds2 <= lds_in;
				data_write2 <= w_datatg68;
			end if;

			-- AMR - Fast chipset path for Gayle
			if slower(0)='0' and clkena_in='1' and sel_gayle_ide='1' and S_state="00" then
				addr <= cpuaddr;
				fast_rd <= '1';
			end if;

			if fast_rd='1' and clkena_in='1' then
				fast_rd <= '0';
			end if;

			if fast_rd='1' then
				r_data <= data_read;
			end if;

			-- Regular chipset path

			if ena7WRreg='1' then
				case S_state is
					when "00" =>
						if cpu_internal='0' and chipset_cycle='1' then
							uds <= uds_in;
							lds <= lds_in;
							uds2 <= '1';
							lds2 <= '1';
							as <= '0';
							rw <= wr_n;
							data_write <= w_datatg68;
							addr <= cpuaddr;
							if aga='1' and cpu(1)='1' and longword='1' and cpu_write='1' and cpuaddr(1 downto 0)="00" and sel_chip='1' then
								-- 32 bit write
								clkena_e <= '1';
							end if;
							S_state <= "01";
						end if;
					when "01" =>
						clkena_e <= '0';
						S_state <= "10";
					when "10" =>
						if waitm='0' or (vma='0' and sync_state=sync9) then
							S_state <= "11";
						end if;
					when "11" =>
						if clkena_f='1' then
							clkena_f <= '0';
							r_data <= data_read2;
						end if;
					when others => null;
				end case;
			elsif ena7RDreg='1' then
				clkena_f <= '0';
				case S_state is
					when "00" =>
						cpuIPL <= IPL;
					when "01" =>
					when "10" =>
						cpuIPL <= IPL;
						waitm <= dtack;
					when "11" =>
						as <= '1';
						rw <= '1';
						uds <= '1';
						lds <= '1';
						uds2 <= '1';
						lds2 <= '1';
						if clkena_e='0' then
							r_data <= data_read;
						end if;

						clkena_e <= '1';
						-- AMR - can't do 32-bit read when reading NMI vector
						if aga='1' and sel_nmi_vector='0' and cpu(1)='1' and longword='1' and state(0)='0' and cpuaddr(1 downto 0)="00" and (sel_chip='1' or sel_kick='1') then
							-- 32 bit read
							clkena_f <= '1';
						end if;
						if clkena='1' then
							S_state <= "00";
							clkena_e <= '0';
						end if;
					when others => null;
				end case;
			end if;
		end if;
	end process;
end block;

genprofiler : if useprofiler=1 generate
	profiler : component profile_cpu
	port map (
		clk => clk,
		reset_n => reset,
		clkena => clkena,
		cpustate => state,
		sel_chip => sel_chip,
		sel_kick => sel_kick,
		sel_fast24 => sel_z2ram,
		sel_fast32 => sel_z3ram
	);
end generate;

end;
-- vim: set noexpandtab tabstop=2 shiftwidth=2 softtabstop=0:
