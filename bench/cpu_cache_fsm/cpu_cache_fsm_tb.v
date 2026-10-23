`timescale 1ns/1ps
// Same external protocol checks run against the full-line and small-cache FSMs.
module cpu_cache_fsm_tb #(parameter LEGACY_WRITE_COMBINE=0);
  reg clk=0; always #5 clk=~clk;
  reg rst=1, cpu_cs=0, cpu_we=0, cpu_ir=0, cpu_dr=0;
  reg cache_inhibit=0, cacheline_clr=0;
  reg [26:0] cpu_adr=0;
  reg [15:0] cpu_dat_w=0, sdr_dat_r=0;
  reg [1:0] cpu_bs=3;
  reg sdr_read_pre=0, sdr_read_ack=0, sdr_write_ack=0;
  reg cpu_long_cand=0, cpu_longword=0;
  reg [15:0] cpu_dat_w_lo=0;
  wire [15:0] cpu_dat_r_hi;
  wire cpu_ack, sdr_read_req, sdr_write_req;
  wire [15:0] cpu_dat_r;
  wire [25:1] sdr_adr;
  wire [31:0] sdr_dat_w;
  wire [3:0] sdr_dqm_w;
  reg [15:0] memory[0:8191];
  integer delay_cycles=0, beats_left=0, first_word=0, writes=0, requests=0, index;
  reg busy_override=0;
`ifndef SMALL_CACHE
  reg [31:0] line_before_reset;
`endif
  cpu_cache_new
`ifdef SMALL_CACHE
  #(.unaligned_write_combine(LEGACY_WRITE_COMBINE))
`endif
  dut (
    .clk(clk), .rst(rst), .cache_en(1'b1), .clk28_en(1'b1),
    .cpu_cache_ctrl(4'b0001), .cache_inhibit(cache_inhibit), .cacheline_clr(cacheline_clr),
    .cpu_cs(cpu_cs), .cpu_adr(cpu_adr), .cpu_bs(cpu_bs),
`ifdef SMALL_CACHE
    .cpu_longword(cpu_longword), .cpu_long_cand(cpu_long_cand),
    .cpu_dat_w_lo(cpu_dat_w_lo), .cpu_dat_r_hi(cpu_dat_r_hi),
`else
    .cpu_32bit(1'b0),
`endif
    .cpu_we(cpu_we), .cpu_ir(cpu_ir), .cpu_dr(cpu_dr), .cpu_dat_w(cpu_dat_w),
    .cpu_dat_r(cpu_dat_r), .cpu_ack(cpu_ack),
    .sdr_dat_r(sdr_dat_r), .sdr_read_req(sdr_read_req), .sdr_read_ack(sdr_read_ack),
    .sdr_read_pre(sdr_read_pre), .sdr_adr(sdr_adr), .sdr_dat_w(sdr_dat_w),
    .sdr_dqm_w(sdr_dqm_w), .sdr_write_req(sdr_write_req), .sdr_write_ack(sdr_write_ack),
    .snoop_act(1'b0), .snoop_adr(26'b0), .snoop_dat_w(32'b0), .snoop_bs(4'b0)
  );
  always @(negedge clk) begin
    if(rst) begin
      sdr_read_ack=0; sdr_write_ack=0; beats_left=0; delay_cycles=0;
    end else begin
      sdr_read_ack=busy_override;
      if(beats_left>0) begin
        sdr_read_ack=1;
        sdr_dat_r=memory[(first_word & ~7) | ((first_word+8-beats_left)&7)];
        beats_left=beats_left-1;
      end else if(delay_cycles>0) begin
        delay_cycles=delay_cycles-1;
        if(delay_cycles==0) beats_left=8;
      end else if(sdr_read_req && !busy_override) begin
        first_word=cpu_adr[13:1]; delay_cycles=7; requests=requests+1;
      end
      if(sdr_write_ack!=sdr_write_req) begin
        if(!sdr_dqm_w[0]) memory[sdr_adr[13:1]][7:0]=sdr_dat_w[7:0];
        if(!sdr_dqm_w[1]) memory[sdr_adr[13:1]][15:8]=sdr_dat_w[15:8];
        if(!sdr_dqm_w[2]) memory[sdr_adr[13:1]+1][7:0]=sdr_dat_w[23:16];
        if(!sdr_dqm_w[3]) memory[sdr_adr[13:1]+1][15:8]=sdr_dat_w[31:24];
        sdr_write_ack=sdr_write_req; writes=writes+1;
      end
    end
  end
  task tick;
    begin @(negedge clk); #2; end
  endtask
  task idle;
    input integer count;
    begin cpu_cs=0; repeat(count) tick; end
  endtask
  task start_read;
    input integer address, instruction;
    begin
      idle(12); cpu_adr=address; cpu_we=0; cpu_ir=instruction; cpu_dr=!instruction;
      idle(3); cpu_cs=1;
    end
  endtask
  task expect_blocked;
    input integer count;
    begin
      repeat(count) begin
        tick;
        if(sdr_read_req!==0 || cpu_ack!==0)
          $fatal(1,"Read launched/acked before allowed: pre=%b busy=%b state=%0d",sdr_read_pre,sdr_read_ack,dut.cpu_sm_state);
      end
    end
  endtask
  task allow_launch;
    begin
      sdr_read_pre=1; tick;
      if(sdr_read_req!==1) $fatal(1,"Miss did not launch at allowed slot");
      sdr_read_pre=0;
      // Arbitration may deny the first slot: retain the request until data arrives.
      repeat(4) begin tick; if(sdr_read_req!==1) $fatal(1,"Pending request was dropped"); end
    end
  endtask
  task finish_read;
    input integer address;
    integer timeout;
    begin
      timeout=0;
      begin: await_ack
        forever begin
          @(posedge clk);
          if(cpu_ack===1) begin
`ifdef SMALL_CACHE
            if(dut.cpu_pair!==0) $fatal(1,"Narrow read accepted as a pair");
`endif
            if(cpu_dat_r!==memory[address/2]) $fatal(1,"Read data mismatch at %h",address);
            disable await_ack;
          end
          #2; timeout=timeout+1;
          if(timeout>80) $fatal(1,"Read timed out at %h state=%0d",address,dut.cpu_sm_state);
        end
      end
      tick; cpu_cs=0; idle(20);
    end
  endtask
`ifdef SMALL_CACHE
  task narrow_write_word;
    input integer address;
    input [15:0] data;
    input [1:0] bytesel;
    input longword_hint;
    integer timeout;
    begin
      cpu_adr=address; cpu_we=1; cpu_ir=0; cpu_dr=0;
      cpu_dat_w=data; cpu_bs=bytesel; cpu_longword=longword_hint;
      idle(3); cpu_cs=1; timeout=0;
      begin: await_narrow_write
        forever begin
          @(posedge clk);
          if(cpu_ack===1) begin
            if(dut.cpu_pair!==0) $fatal(1,"Legacy write asserted new pair ACK");
            disable await_narrow_write;
          end
          #2; timeout=timeout+1;
          if(timeout>100) $fatal(1,"Legacy narrow write timeout at %h",address);
        end
      end
      tick; cpu_cs=0; idle(5); cpu_longword=0;
    end
  endtask
  task legacy_write;
    input integer address;
    input [1:0] first_bs, second_bs;
    integer before_writes, first_index, second_index;
    reg [15:0] expected_first, expected_second;
    begin
      idle(12); before_writes=writes;
      first_index=address/2; second_index=first_index+1;
      expected_first=memory[first_index]; expected_second=memory[second_index];
      if(first_bs[0]) expected_first[7:0]=8'h34;
      if(first_bs[1]) expected_first[15:8]=8'h12;
      if(second_bs[0]) expected_second[7:0]=8'hcd;
      if(second_bs[1]) expected_second[15:8]=8'hab;
      narrow_write_word(address,16'h1234,first_bs,1);
      if(writes!=before_writes+((LEGACY_WRITE_COMBINE && (address&14)!=14)?0:1))
        $fatal(1,"Legacy parameter did not select first-word buffering");
      narrow_write_word(address+2,16'habcd,second_bs,0);
      idle(15); cpu_bs=3;
      if(writes!=before_writes+((LEGACY_WRITE_COMBINE && (address&14)!=14)?1:2) ||
         memory[first_index]!==expected_first || memory[second_index]!==expected_second)
        $fatal(1,"Legacy write combining/masks failed at %h",address);
      // Check both touched cache pairs after invalidating any last-pair hits.
      start_read(address&~1,0); finish_read(address&~1);
      start_read((address&~1)+2,0); finish_read((address&~1)+2);
      start_read(address&~1,1); finish_read(address&~1);
      start_read((address&~1)+2,1); finish_read((address&~1)+2);
    end
  endtask
  task wide_read;
    input integer address, instruction;
    integer timeout;
    begin
      cpu_long_cand=1;
      start_read(address,instruction);
      timeout=0;
      begin: await_pair
        forever begin
          @(posedge clk);
          if(cpu_ack===1) begin
            if(dut.cpu_pair!==1 || {cpu_dat_r_hi,cpu_dat_r}!=={memory[address/2],memory[address/2+1]})
              $fatal(1,"Wide read mismatch at %h: %h %h",address,cpu_dat_r_hi,cpu_dat_r);
            disable await_pair;
          end
          #2; timeout=timeout+1;
          if(timeout>100) $fatal(1,"Wide read timeout at %h state=%0d",address,dut.cpu_sm_state);
        end
      end
      tick; cpu_cs=0; idle(20); cpu_long_cand=0;
    end
  endtask
  task wide_write;
    input integer address;
    input [31:0] data;
    integer timeout, before_writes;
    begin
      idle(12); cpu_adr=address; cpu_we=1; cpu_ir=0; cpu_dr=0;
      cpu_dat_w=data[31:16]; cpu_dat_w_lo=data[15:0]; cpu_long_cand=1; cpu_longword=1;
      idle(3); cpu_cs=1; timeout=0; before_writes=writes;
      begin: await_pair_write
        forever begin
          @(posedge clk);
          if(cpu_ack===1) begin
            if(dut.cpu_pair!==1) $fatal(1,"Wide write not accepted");
            disable await_pair_write;
          end
          #2; timeout=timeout+1;
          if(timeout>100) $fatal(1,"Wide write timeout");
        end
      end
      tick; cpu_cs=0; cpu_long_cand=0; cpu_longword=0; idle(20);
      if(writes!=before_writes+1 || {memory[address/2],memory[address/2+1]}!==data)
        $fatal(1,"Wide write did not store exactly one big-endian pair");
    end
  endtask
`endif
  initial begin
    for(index=0;index<8192;index=index+1) memory[index]=(index*31)^16'habcd;
    idle(3); rst=0; idle(280);
    start_read('h100,0); expect_blocked(12); allow_launch; finish_read('h100);
    // A main-cache or line-buffer hit must not depend on sdr_read_pre.
    start_read('h100,0); finish_read('h100);
    if(requests!=1) $fatal(1,"Cache hit unnecessarily fetched SDRAM");
    // Repeat with the instruction cache and a nonzero critical-word offset.
    start_read('h216,1); expect_blocked(12); allow_launch; finish_read('h216);
    start_read('h216,1); finish_read('h216);
    if(requests!=2) $fatal(1,"Instruction hit unnecessarily fetched SDRAM");
    // Previous read still active: pre alone must not start the next request.
    busy_override=1; sdr_read_pre=1;
    start_read('h300,0); expect_blocked(12);
    busy_override=0; sdr_read_pre=0; expect_blocked(8);
    allow_launch; finish_read('h300);
    // Writes are independent of the read launch slot.
    idle(12); cpu_adr='h100; cpu_we=1; cpu_ir=0; cpu_dr=0; cpu_dat_w=16'h1234;
    idle(3); cpu_cs=1;
    // The small variant mixes delayed and undelayed ACK assignments, so its
    // behavioral write ACK can be shorter than one clock period.
    fork: await_write
      begin wait(cpu_ack===1); end
      begin repeat(40) tick; $fatal(1,"Write stalled with pre low"); end
    join_any
    disable await_write;
    tick; cpu_cs=0; idle(20);
    if(writes!=1 || memory['h80]!==16'h1234) $fatal(1,"Write did not reach memory");
    start_read('h100,0); finish_read('h100);
    // Inhibited miss ends early, with the remainder of the burst still active.
    cache_inhibit=1;
    start_read('h400,0); expect_blocked(8); allow_launch;
    begin: early_ack
      repeat(40) begin @(posedge clk); if(cpu_ack===1) disable early_ack; #2; end
      $fatal(1,"Inhibited read timed out");
    end
    tick; cpu_cs=0; tick; cpu_adr='h500; idle(3); cpu_cs=1;
    // While the old burst drains and pre stays low, the next miss must wait.
    expect_blocked(12); allow_launch; finish_read('h500);
`ifdef SMALL_CACHE
    // Both cache types, misses, BRAM hits and last-pair hits; last aligned pair
    // in a burst must also complete without crossing the line boundary.
    cache_inhibit=0; sdr_read_pre=1;
    wide_read('h60c,0);
    wide_read('h600,0);
    wide_read('h600,0);
    wide_read('h70c,1);
    wide_read('h700,1);
    wide_read('h700,1);
    // Same-index conflicting tags exercise both ways and replacement.
    wide_read('h1600,0); wide_read('h600,0); wide_read('h2600,0);
    wide_read('h1600,0); wide_read('h600,0);
    wide_read('h1700,1); wide_read('h700,1); wide_read('h2700,1);
    wide_read('h1700,1); wide_read('h700,1);
    // Write-through updates both resident cache types and invalidates pairs.
    wide_read('h600,1);
    wide_write('h600,32'h1234abcd);
    wide_read('h600,0);
    wide_read('h600,1);
    wide_write('h700,32'h98765432);
    wide_read('h700,1);
    // A write miss must receive both words without a second CPU request.
    wide_write('h80c,32'h10203040);
    wide_read('h80c,0);
    // Unaligned candidates must fall back to a single word.
    cpu_long_cand=1; start_read('h602,0); finish_read('h602);
    if(dut.cpu_pair===1) $fatal(1,"Unaligned pair accepted");
    cpu_long_cand=0;
    cache_inhibit=1;
    wide_read('h90c,0);
    wide_read('ha00,1);
    cache_inhibit=0;
`endif
`ifdef SMALL_CACHE
    // The old longword hint is tested with its parameter both off and on.
    // Warm both cache types before writes, including the two entries touched
    // by a pair starting at address + 2 and the excluded line-end case.
    wide_read('hc00,0); wide_read('hc00,1);
    wide_read('hc04,0); wide_read('hc04,1);
    legacy_write('hc00,3,3);
    legacy_write('hc02,3,3);
    legacy_write('hc01,1,3);
    legacy_write('hc02,3,2);
    wide_read('hc0c,0); wide_read('hc0c,1);
    wide_read('hc10,0); wide_read('hc10,1);
    legacy_write('hc0e,3,3);
    // Reset between the two beats must discard the incomplete pair and ACK.
    cpu_long_cand=1; start_read('hb00,0);
    begin: await_first_beat
      repeat(100) begin
        tick;
        if(dut.read_pair_pending===1) disable await_first_beat;
      end
      $fatal(1,"Did not reach incomplete pair");
    end
    if(cpu_ack!==0) $fatal(1,"Pair acknowledged before second beat");
    rst=1; tick;
    if(cpu_ack!==0 || dut.cpu_pair!==0 || dut.read_pair_pending!==0)
      $fatal(1,"Reset retained incomplete pair/ACK");
    cpu_cs=0; rst=0; idle(280); cpu_long_cand=0;
    wide_read('hb00,0);
`endif
    // Deposit unexpected states to exercise the fallback transitions.
    dut.cpu_sm_state=4'hf; tick;
    if(dut.cpu_sm_state!==0) $fatal(1,"CPU FSM did not recover to INIT");
    dut.sdr_sm_state=2'bxx; tick;
    if(dut.sdr_sm_state!==0) $fatal(1,"SDRAM FSM did not recover to INIT0");
    idle(280);
    cache_inhibit=0; cacheline_clr=1; idle(3); cacheline_clr=0;
    sdr_read_pre=1; start_read('h100,0); finish_read('h100);
    // Reset while a matching CPU write would otherwise update the line buffer.
    idle(12); cpu_adr='h100; cpu_we=1; cpu_ir=0; cpu_dr=0; cpu_dat_w=16'h55aa;
    idle(3);
`ifndef SMALL_CACHE
    line_before_reset=dut.cpu_cacheline_d[0];
`endif
    cpu_cs=1; rst=1; tick;
`ifndef SMALL_CACHE
    if(dut.cpu_cacheline_d[0]!==line_before_reset) $fatal(1,"Line RAM changed during reset");
    if(dut.cpu_cacheline_d_dirty!==1) $fatal(1,"Reset did not invalidate data line");
`else
    if(dut.last_pair_valid_d!==0) $fatal(1,"Reset did not invalidate last pair");
`endif
    $display("PASS FSM: launch gating, I/D narrow and paired accesses, write-through, inhibited reads, reset");
    $finish;
  end
  initial begin #100000; $fatal(1,"Global timeout"); end
endmodule
