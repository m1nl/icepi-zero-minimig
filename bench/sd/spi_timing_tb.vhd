-- GPL-3.0-or-later. Exercise the production SPI engine at the board system clock.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
entity spi_timing_tb is
 generic (slow_divider : natural := 72; fast_divider : natural := 1;
          free_running : integer := 1; rtc_enabled : integer := 0; trace_path : string := "");
end;
architecture tb of spi_timing_tb is
 signal clk : std_logic := '0';
 signal rst : std_logic := '0';
 signal addr : std_logic_vector(31 downto 2) := (others=>'0');
 signal d,q : std_logic_vector(31 downto 0) := (others=>'0');
 signal req,wr,ack,sclk,mosi : std_logic := '0';
 signal cs : std_logic_vector(7 downto 0);
 signal usb_dp,usb_dn : std_logic_vector(1 downto 0) := (others=>'Z');
 signal stage : integer := 0;
 signal edges : natural := 0;
 signal min_period : time := 1 ms;
 signal max_period : time := 0 ns;
 signal previous : time := 0 ns;
begin
 clk <= not clk after 4375 ps;
 dut: entity work.cfide generic map(spimux=>0,haveauxspi=>0,haveusbhid=>0,sd_free_running=>free_running,havespirtc=>rtc_enabled) port map(
 sysclk=>clk,usbclk=>clk,reset_n=>rst,addr=>addr,d=>d,q=>q,req=>req,wr=>wr,ack=>ack,
 aux_spi_csn=>'1',aux_spi_clk=>'0',aux_spi_mosi=>'1',
 sd_di=>'1',sd_cs=>cs,sd_clk=>sclk,sd_do=>mosi,sd_dimm=>mosi,sd_ack=>'1',
 debugTxD=>open,debugRxD=>'1',scandoubler=>open,invertsync=>open,
 audio_ena=>open,audio_clear=>open,audio_buf=>'0',audio_amiga=>'0',vbl_int=>'0',interrupt=>open,
 amiga_key=>open,amiga_key_stb=>open,keyboard_done=>'0',keyboard_unavailable=>'0',
 amiga_addr=>(others=>'0'),amiga_req=>'0',amiga_ack=>open,amiga_wr=>'0',amiga_d=>(others=>'0'),amiga_q=>open,
 rtc_q=>open,reconfig=>open,iecserial=>open,usb_dp=>usb_dp,usb_dn=>usb_dn,usb_connected=>open,
 joya=>open,joyb=>open,clk_28=>clk,tick_in=>'0');
 process(sclk,stage)
  variable delta : time;
 begin
  if stage'event then edges<=0;previous<=0 ns;min_period<=1 ms;max_period<=0 ns;
  elsif rising_edge(sclk) and rst='1' then
   edges<=edges+1;
   if previous/=0 ns then
    delta:=now-previous;
    if delta<min_period then min_period<=delta;end if;
    if delta>max_period then max_period<=delta;end if;
   end if;
   previous<=now;
  end if;
 end process;
 -- No short pulses when software selects a device or changes the divider.
 process(sclk)
  variable last_edge : time := 0 ns;
 begin
  if sclk'event and rst='1' then
   if last_edge/=0 ns then
    assert now-last_edge>=20 ns report "SPI clock has a runt pulse" severity failure;
   end if;
   last_edge:=now;
  end if;
 end process;
 process(cs)
  variable previous_cs : std_logic_vector(7 downto 0) := (others=>'1');
 begin
  if cs'event and rst='1' then
   for device in 1 to 7 loop
    if cs(device)='0' and previous_cs(device)='1' then
     assert sclk='1' report "CS asserted before idle clock parked high" severity failure;
    end if;
   end loop;
  end if;
  previous_cs:=cs;
 end process;
 process
  procedure write_reg(a : natural;v : natural) is
  begin
   wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a/4,30));d<=std_logic_vector(to_unsigned(v,32));wr<='1';req<='1';
   wait until rising_edge(clk) and ack='1';
   wait until falling_edge(clk);req<='0';wr<='0';
   wait until rising_edge(clk) and ack='0';
  end;
  procedure read_reg(a : natural;variable v : out std_logic_vector(31 downto 0)) is
  begin
   wait until falling_edge(clk);addr<=std_logic_vector(to_unsigned(a/4,30));wr<='0';req<='1';
   wait until rising_edge(clk) and ack='1';v:=q;
   wait until falling_edge(clk);req<='0';
   wait until rising_edge(clk) and ack='0';
  end;
  variable v, saved : std_logic_vector(31 downto 0);
  variable before : natural;
  variable connected : boolean;
  variable current_cs : integer := -1;
  variable active_cs, tx, divider : integer;
  file trace_file : text;
  variable trace_line : line;
 begin
  wait for 100 ns;rst<='1';stage<=10;wait for 50 us;
  if free_running/=0 then
   assert edges>1 and min_period>=2500 ns report "unsafe/missing reset idle clock" severity failure;
   assert mosi='1' and cs(7 downto 1)="1111111" report "unsafe idle reset pins" severity failure;
  else
   assert edges=0 report "disabled idle clock toggled" severity failure;
  end if;
  write_reg(16#0fffffe8#,slow_divider);write_reg(16#0fffffe4#,2);
  stage<=1;write_reg(16#0fffffe0#,16#a5#);read_reg(16#0fffffe0#,v);
  assert edges=8 and v(7 downto 0)=x"a5" report "8-bit loopback failed" severity failure;
  assert min_period>=2500 ns report "selected initialization SCK exceeds 400 kHz" severity failure;
  report "slow SCK edges="&integer'image(edges)&" period="&time'image(min_period)&".."&time'image(max_period)&" frequency_hz="&real'image(1.0e12/real(min_period/1 ps));
  write_reg(16#0fffffe8#,fast_divider);stage<=2;
  write_reg(16#0fffffe0#,16#5a#);read_reg(16#0fffffe0#,v);
  assert edges=8 and v(7 downto 0)=x"5a" report "fast loopback failed" severity failure;
  assert min_period>=40 ns report "transfer SCK exceeds 25 MHz" severity failure;
  report "fast SCK period="&time'image(min_period)&".."&time'image(max_period)&" frequency_hz="&real'image(1.0e12/real(min_period/1 ps));
  write_reg(16#0fffffe4#,16#40#);stage<=3;
  write_reg(16#0fffffe0#,255);read_reg(16#0fffffe0#,v);
  assert edges=4096 report "direct read clock count wrong" severity failure;
  report "direct-read clocks="&integer'image(edges);
  write_reg(16#0fffffe4#,16#41#);write_reg(16#0fffffe4#,3);stage<=4;
  wait for 10 us;
  if free_running/=0 then
   assert edges>1 and mosi='1' report "missing idle clocks or unsafe idle MOSI" severity failure;
  else
   assert edges=0 report "unexpected free-running clocks" severity failure;
  end if;
  report "after deselect: clocks="&integer'image(edges);
  write_reg(16#0fffffe8#,slow_divider);stage<=5;
  write_reg(16#0fffffe0#,255);read_reg(16#0fffffe0#,v);
  assert edges>=8 report "deselected dummy clock count wrong" severity failure;
  assert min_period>=2500 ns report "deselected initialization SCK exceeds 400 kHz" severity failure;
  report "slow with CS high: period="&time'image(min_period)&" frequency_hz="&real'image(1.0e12/real(min_period/1 ps));
  -- Exercise actual and unused selects, including the optional RTC mux.
  write_reg(16#0fffffe8#,fast_divider);
  for device in 1 to 7 loop
   connected:=device=1 or device=4 or device=5 or device=6 or
              (device=7 and rtc_enabled=1);
   write_reg(16#0fffffe4#,2**device);
   stage<=20+device;wait for 10 us;
   if not connected then
    assert cs(device)='1' report "unused select output is not held inactive" severity failure;
   end if;
   assert cs(0)='1' report "unused legacy select is not held inactive" severity failure;
   if connected or free_running=0 then
    assert edges=0 report "idle clocks reached a selected SPI device" severity failure;
   else
    assert edges>1 and mosi='1' report "unused select inhibited safe idle clocks" severity failure;
   end if;
   before:=edges;
   write_reg(16#0fffffe0#,16#a5#);read_reg(16#0fffffe0#,v);
   if device=6 then
    assert edges=before+4096 report "direct mode has stray clocks" severity failure;
   elsif connected or free_running=0 then
    assert edges=before+8 report "selected byte has stray clocks" severity failure;
   else
    assert edges>=before+8 report "unused-select transfer did not finish" severity failure;
   end if;
   if device=1 or (device=7 and rtc_enabled=1) then
    assert v(7 downto 0)=x"a5" report "selected loopback failed" severity failure;
   elsif device/=6 then
    assert v(7 downto 0)=x"ff" report "unused/disabled select changed receive mux" severity failure;
   end if;
   saved:=v;stage<=30+device;wait for 10 us;
   if connected or free_running=0 then
    assert edges=0 report "selected firmware gap consumed bits" severity failure;
   else
    assert edges>1 report "unused select stopped idle clocking" severity failure;
   end if;
   write_reg(16#0fffffe4#,2**device+1);
   wait for 10 us;read_reg(16#0fffffe0#,v);
   assert v=saved report "idle clocks overwrote receive register" severity failure;
  end loop;
  if trace_path/="" then
   file_open(trace_file,trace_path,read_mode);
   while not endfile(trace_file) loop
    readline(trace_file,trace_line);read(trace_line,active_cs);read(trace_line,tx);read(trace_line,divider);
    write_reg(16#0fffffe8#,divider);
    if active_cs/=current_cs then
     if active_cs=1 then write_reg(16#0fffffe4#,2);
     else write_reg(16#0fffffe4#,3);end if;
     current_cs:=active_cs;
    end if;
    stage<=stage+1;wait for 7 us;
    if active_cs=1 then assert edges=0 report "firmware gap clocked selected card" severity failure;
    else assert cs(1)='1' report "firmware deselection lost" severity failure;end if;
    before:=edges;
    write_reg(16#0fffffe0#,tx);read_reg(16#0fffffe0#,v);
    if active_cs=1 then
     assert edges=before+8 and v(7 downto 0)=std_logic_vector(to_unsigned(tx,8))
      report "firmware wire byte corrupted or extra selected clocks" severity failure;
    end if;
   end loop;
   file_close(trace_file);
  end if;
  report "PASS: SPI clock limits, idle safety, shared selects, receive retention and firmware trace";
  stop;
 end process;
 process begin wait for 200 ms;assert false report "audit timeout" severity failure;end process;
end;
