-- Bridge to interface 32-bit CPU to 16-bit host CPU  bus

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity EightThirtyTwo_Bridge is
	generic (
		debug : integer := 0
	);
	port(
		clk             : in std_logic;
		nReset            : in std_logic;			--low active
		addr					: out std_logic_vector(31 downto 2);
		q			      	: out std_logic_vector(31 downto 0);
		sel					: out std_logic_vector(3 downto 0);
		wr						: out std_logic;

		ram_req				: out std_logic;
		ram_ack				: in std_logic;
		ram_d					: in std_logic_vector(15 downto 0);

		hw_req            : out std_logic;
		hw_ack            : in std_logic;
		hw_d					: in std_logic_vector(31 downto 0);
		interrupt			: in std_logic
	);
end EightThirtyTwo_Bridge;

architecture rtl of EightThirtyTwo_Bridge is

type bridgestates is (waiting,ram,hw,rom);
signal state : bridgestates;

signal cpu_req : std_logic;
signal cpu_ack : std_logic;
signal cpu_d 	: std_logic_vector(31 downto 0);
signal cpu_q	: std_logic_vector(31 downto 0);
signal cpu_addr	: std_logic_vector(31 downto 2);
signal cpu_wr	: std_logic;
signal cpu_sel : std_logic_vector(3 downto 0);

signal cache_req : std_logic;
signal cache_ack : std_logic;
signal cache_q : std_logic_vector(31 downto 0);

signal debug_d : std_logic_vector(31 downto 0);
signal debug_q : std_logic_vector(31 downto 0);
signal debug_req : std_logic;
signal debug_ack : std_logic;
signal debug_wr : std_logic;

signal rom_q : std_logic_vector(31 downto 0);
signal rom_wr : std_logic;
signal rom_select : std_logic;
signal hw_select : std_logic;

signal jtag_reset_n : std_logic;

signal cpu_reset_n : std_logic;

component hostcache
port
(
	sysclk : in std_logic;
	reset_n : in std_logic;
	a : in std_logic_vector(25 downto 2);
	d : in std_logic_vector(31 downto 0);
	q : out std_logic_vector(31 downto 0);
	req : in std_logic;
	wr : in std_logic;
	ack : out std_logic;
	bytesel : in std_logic_vector(3 downto 0);
	sdram_d : in std_logic_vector(15 downto 0);
	sdram_req : out std_logic;
	sdram_ack : in std_logic
);
end component;

begin

cpu_reset_n <= nReset and jtag_reset_n;

gendebugbridge:
if debug=1 generate

my832 : entity work.eightthirtytwo_cpu
generic map (
	littleendian => false,
	interrupts => true,
	dualthread => false,
	forwarding => false,
	prefetch => false,
	multiplier => true,
--  inserting additional waitstate helps with timing closure
	multiplier_waitstate => true,
	debug => true
)
port map(
	clk => clk,
	reset_n => cpu_reset_n,
	addr => cpu_addr,
	d => cpu_d,
	q => cpu_q,
	wr => cpu_wr,
	req => cpu_req,
	ack => cpu_ack,
	bytesel => cpu_sel,
	interrupt => interrupt,
	debug_d => debug_d,
	debug_q => debug_q,
	debug_req => debug_req,
	debug_ack => debug_ack,
	debug_wr => debug_wr
);

debugbridge : entity work.debug_bridge_jtag
port map(
	clk => clk,
	reset_n => nReset,
	d => debug_q,
	q => debug_d,
	req => debug_req,
	ack => debug_ack,
	wr => debug_wr
);
end generate;

nodebug:
if debug=0 generate
my832 : entity work.eightthirtytwo_cpu
generic map (
	littleendian => false,
	interrupts => true,
	dualthread => false,
	forwarding => false,
	prefetch => false,
	multiplier => true,
	multiplier_waitstate => true,
	debug => false
)
port map(
	clk => clk,
	reset_n => cpu_reset_n,
	addr => cpu_addr,
	d => cpu_d,
	q => cpu_q,
	wr => cpu_wr,
	req => cpu_req,
	ack => cpu_ack,
	bytesel => cpu_sel,
	interrupt => interrupt
);

end generate;


-- JCapture debug infrastructure
capture : block

	constant jcapture_width : integer := 32;

	component jcapture
	generic (
		capturewidth : integer := 32;
		capturedepth : integer := 9;
		triggerwidth : integer := 32;
		id : integer := 16#35ac#
	);
	port (
		clk : in std_logic;
		reset_n : in std_logic;
		stb : in std_logic;
		d : in std_logic_vector(capturewidth-1 downto 0);
		q : out std_logic_vector(capturewidth-1 downto 0);
		update : out std_logic
	);
	end component;

	signal capture : std_logic_vector(jcapture_width-1 downto 0);
	signal cap_q : std_logic_vector(jcapture_width-1 downto 0);
	signal cap_upd : std_logic;

begin

	capture(0) <= cpu_req;
	capture(1) <= cpu_ack;
	capture(31 downto 2) <= cpu_addr;

	jtag_reset_n <= '1';

--	capture_inst : component jcapture
--	generic map (
--		capturewidth => jcapture_width,
--		triggerwidth => jcapture_width
--	)
--	port map (
--		clk => clk,
--		reset_n => nReset,
--		stb => '1',
--		d => capture,
--		q => cap_q,
--		update => cap_upd
--	);

--	process(clk) begin
--		if rising_edge(clk) then
--			if cap_upd='1' then
--				jtag_reset_n <= not cap_q(0);
--			end if;
--			if nReset = '0' then
--				jtag_reset_n <= '1';
--			end if;
--		end if;
--	end process;

end block;


bootrom: entity work.OSDBoot_832_ROM
	generic map
	(
		maxAddrBitBRAM => 12
	)
	PORT MAP
	(
		addr => cpu_addr(12 downto 2),
		clk   => clk,
		d	=> cpu_q,
		we	=> rom_wr,
		bytesel => cpu_sel,
		q		=> rom_q
	);

rom_select <= '1' when cpu_addr(24 downto 13)=X"000"&"000" ELSE '0';

hw_select <= cpu_addr(27);

process(clk,nReset)
begin

	if nReset='0' then
		state<=waiting;
		hw_req<='0';
		wr<='0';
		rom_wr<='0';
		cache_req<='0';
		cpu_d<=(others=>'0');
		cpu_ack<='0';
		addr<=(others=>'0');
		q<=(others=>'0');
		sel<=(others=>'0');
	elsif rising_edge(clk) then

		cpu_ack<='0';
		rom_wr<='0';

		-- Map host processor's address space to 0x680000
		-- (makes more sense to do it here than in the SDRAM controller.)
		addr<=(cpu_addr(31 downto 16) xor X"0068") & cpu_addr(15 downto 2);
		q<=cpu_q;
		sel<=cpu_sel;
		wr<=cpu_wr;

		case state is
			when waiting =>
				if hw_ack='0' and cpu_ack='0' and cpu_req='1' then
					if rom_select='1' then
						rom_wr<=cpu_wr;
						state<=rom;
					elsif hw_select='1' then
						hw_req<='1';
						state<=hw;
					else
						cache_req<='1';
						state<=ram;
					end if;
				end if;

			when rom =>
				cpu_d<=rom_q;
				wr<='0';
				rom_wr<='0';
				cpu_ack<='1';
				state<=waiting;

			when ram =>
				if cache_ack='1' then
					cache_req<='0';
					cpu_d<=cache_q;
					wr<='0';
					cpu_ack<='1';
					state<=waiting;
				end if;

			when hw =>
				if hw_ack='1' then
					cpu_d<=hw_d;
					wr<='0';
					hw_req<='0';
					cpu_ack<='1';
					state<=waiting;
				end if;

			when others =>
				null;
		end case;
	end if;
end process;

hostcache_inst : component hostcache
port map
(
	sysclk => clk,
	reset_n => nReset,
	a => cpu_addr(25 downto 2),
	q => cache_q,
	d => cpu_q,
	req => cache_req,
	wr => cpu_wr,
	ack => cache_ack,
	bytesel => cpu_sel,
	sdram_d => ram_d,
	sdram_req => ram_req,
	sdram_ack => ram_ack
);

end architecture;
