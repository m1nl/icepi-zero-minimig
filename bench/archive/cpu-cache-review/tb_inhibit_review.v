`timescale 1ns/1ps
// Same external protocol checks run against the full-line and small-cache FSMs.
module cpu_cache_fsm_tb;
  reg clk=0; always #5 clk=~clk;
  reg rst=1, cpu_cs=0, cpu_we=0, cpu_ir=0, cpu_dr=0;
  reg cache_inhibit=0, cacheline_clr=0;
  reg [26:0] cpu_adr=0;
  reg [15:0] cpu_dat_w=0, sdr_dat_r=0;
  reg [1:0] cpu_bs=3;
  reg sdr_read_pre=0, sdr_read_ack=0, sdr_write_ack=0;
  wire cpu_ack, sdr_read_req, sdr_write_req;
  wire [15:0] cpu_dat_r;
  wire [25:1] sdr_adr;
  wire [31:0] sdr_dat_w;
  wire [3:0] sdr_dqm_w;
  reg [15:0] memory[0:2047];
  integer delay_cycles=0, beats_left=0, first_word=0, writes=0, requests=0, index;
  reg busy_override=0;
  cpu_cache_new dut (
    .clk(clk), .rst(rst), .cache_en(1'b1), .clk28_en(1'b1),
    .cpu_cache_ctrl(4'b0001), .cache_inhibit(cache_inhibit), .cacheline_clr(cacheline_clr),
    .cpu_cs(cpu_cs), .cpu_adr(cpu_adr), .cpu_bs(cpu_bs), .cpu_32bit(1'b0),
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
        first_word=cpu_adr[11:1]; delay_cycles=7; requests=requests+1;
      end
      if(sdr_write_ack!=sdr_write_req) begin
        if(!sdr_dqm_w[0]) memory[sdr_adr[11:1]][7:0]=sdr_dat_w[7:0];
        if(!sdr_dqm_w[1]) memory[sdr_adr[11:1]][15:8]=sdr_dat_w[15:8];
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
  initial begin
    for(index=0;index<2048;index=index+1) memory[index]=(index*31)^16'habcd;
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
    // Review check: does an inhibited read bypass an already valid main-cache entry?
    cache_inhibit=1;
    start_read('h100,0);
    begin: inhibit_check
      repeat(20) begin
        @(posedge clk);
        if(cpu_ack===1) begin
          $display("REVIEW: inhibited cached read acknowledged with no SDRAM request; state=%0d requests=%0d",dut.cpu_sm_state,requests);
          $finish;
        end
        #2;
      end
      $fatal(1,"Inhibited cached read did not hit");
    end
  end
  initial begin #100000; $fatal(1,"Global timeout"); end
endmodule
