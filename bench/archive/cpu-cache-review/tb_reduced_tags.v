`timescale 1ns/1ps
module tb;
parameter ADDR_BITS=26;
reg clk=0; always #5 clk=~clk;
reg rst=1, cache_en=1, clk28_en=1, cache_inhibit=0, cacheline_clr=0;
reg [3:0] cpu_cache_ctrl=1;
reg cpu_cs=0, cpu_32bit=0, cpu_we=0, cpu_ir=0, cpu_dr=0;
reg [ADDR_BITS:0] cpu_adr=0;
reg [1:0] cpu_bs=3;
reg [15:0] cpu_dat_w=0, sdr_dat_r=0;
reg sdr_read_ack=0, sdr_write_ack=0;
reg snoop_act=0;
reg [25:0] snoop_adr=0;
reg [31:0] snoop_dat_w=0;
reg [3:0] snoop_bs=0;
wire [15:0] ref_dat, dut_dat;
wire ref_ack, dut_ack, ref_read_req, dut_read_req, ref_write_req, dut_write_req;
wire [25:1] ref_adr, dut_adr;
wire [31:0] ref_dat_w, dut_dat_w;
wire [3:0] ref_dqm, dut_dqm;
`define INPUTS .clk(clk), .rst(rst), .cache_en(cache_en), .clk28_en(clk28_en), .cpu_cache_ctrl(cpu_cache_ctrl), .cache_inhibit(cache_inhibit), .cacheline_clr(cacheline_clr), .cpu_cs(cpu_cs), .cpu_adr({{(26-ADDR_BITS){1'b0}},cpu_adr}), .cpu_bs(cpu_bs), .cpu_32bit(cpu_32bit), .cpu_we(cpu_we), .cpu_ir(cpu_ir), .cpu_dr(cpu_dr), .cpu_dat_w(cpu_dat_w), .sdr_dat_r(sdr_dat_r), .sdr_read_ack(sdr_read_ack), .sdr_write_ack(sdr_write_ack), .snoop_act(snoop_act), .snoop_adr(snoop_adr), .snoop_dat_w(snoop_dat_w), .snoop_bs(snoop_bs)
cpu_cache_reference refcache (`INPUTS, .cpu_dat_r(ref_dat), .cpu_ack(ref_ack), .sdr_read_req(ref_read_req), .sdr_write_req(ref_write_req), .sdr_adr(ref_adr), .sdr_dat_w(ref_dat_w), .sdr_dqm_w(ref_dqm));
cpu_cache_new #(.addr_max_bits(ADDR_BITS)) dut (`INPUTS, .sdr_read_pre(1'b1), .cpu_dat_r(dut_dat), .cpu_ack(dut_ack), .sdr_read_req(dut_read_req), .sdr_write_req(dut_write_req), .sdr_adr(dut_adr), .sdr_dat_w(dut_dat_w), .sdr_dqm_w(dut_dqm));
reg [15:0] memory [0:32767];
integer burst=0, start_word=0, delay_ctr=0, k, j, cycles=0, transactions=0;
integer reads=0, writes=0, l1hits=0, way_hits[0:3], fills[0:7], masks[0:3];
integer seed=12345, randval, choice, addr;
reg monitor=1;
reg [31:0] before_reset;
// SDRAM burst model, critical-word first with wrapping inside the 16-byte line.
always @(negedge clk) begin
  if (rst) begin
    burst=0; delay_ctr=0; sdr_read_ack=0; sdr_write_ack=0;
  end else begin
    sdr_read_ack=0;
    if (burst>0) begin
      sdr_read_ack=1;
      sdr_dat_r=memory[(start_word & ~7) | ((start_word + (8-burst)) & 7)];
      burst=burst-1;
    end else if (delay_ctr>0) begin
      delay_ctr=delay_ctr-1;
      if (delay_ctr==0) burst=8;
    end else if (ref_read_req) begin
      start_word=refcache.cpu_adr_l[15:1];
      delay_ctr=3;
      fills[start_word & 7]=fills[start_word & 7]+1;
    end
    if (sdr_write_ack != ref_write_req) begin
      j=ref_adr[15:1];
      // Odd-start writes shift the first halfword to the high half of its pair.
      if (!ref_dqm[0]) memory[j][7:0]=ref_dat_w[7:0];
      if (!ref_dqm[1]) memory[j][15:8]=ref_dat_w[15:8];
      if (!ref_dqm[2]) memory[j+1][7:0]=ref_dat_w[23:16];
      if (!ref_dqm[3]) memory[j+1][15:8]=ref_dat_w[31:24];
      sdr_write_ack=ref_write_req;
    end
  end
end
always @(posedge clk) begin
  if (!rst && dut.cpu_sm_state==6 && dut.cc_en) begin
    if(dut.itag0_match && dut.itag0_valid && dut.level1_i) way_hits[0]=way_hits[0]+1;
    else if(dut.itag1_match && dut.itag1_valid && dut.level1_i) way_hits[1]=way_hits[1]+1;
    else if(dut.dtag0_match && dut.dtag0_valid && dut.level1_d) way_hits[2]=way_hits[2]+1;
    else if(dut.dtag1_match && dut.dtag1_valid && dut.level1_d) way_hits[3]=way_hits[3]+1;
  end
  #2;
  cycles=cycles+1;
  if(monitor) begin
    if ({ref_dat,ref_ack,ref_read_req,ref_write_req,ref_adr,ref_dat_w,ref_dqm} !== {dut_dat,dut_ack,dut_read_req,dut_write_req,dut_adr,dut_dat_w,dut_dqm}) begin
      $display("OUTPUT MISMATCH cycle=%0d state=%0d addr=%h ref=%h dut=%h",cycles,dut.cpu_sm_state,cpu_adr,ref_dat,dut_dat); $fatal;
    end
    for(k=0;k<4;k=k+1) begin
      if (dut.cpu_cacheline_i[k] !== {refcache.cpu_cacheline_i_hi[2*k+1],refcache.cpu_cacheline_i_lo[2*k+1],refcache.cpu_cacheline_i_hi[2*k],refcache.cpu_cacheline_i_lo[2*k]}) begin
        $display("I LINE MISMATCH cycle=%0d state=%0d wordpair=%0d rst=%b",cycles,dut.cpu_sm_state,k,rst); $fatal;
      end
      if (dut.cpu_cacheline_d[k] !== {refcache.cpu_cacheline_d_hi[2*k+1],refcache.cpu_cacheline_d_lo[2*k+1],refcache.cpu_cacheline_d_hi[2*k],refcache.cpu_cacheline_d_lo[2*k]}) begin
        $display("D LINE MISMATCH cycle=%0d state=%0d wordpair=%0d rst=%b",cycles,dut.cpu_sm_state,k,rst); $fatal;
      end
    end
  end
end
task idle;
 input integer n;
 begin cpu_cs=0; repeat(n) begin @(negedge clk); #1; end end
endtask
task access;
 input integer a, wr, insn, mask, data;
 integer timeout;
 reg [15:0] sampled_dat;
 reg sampled_l1;
 begin
   idle(12);
   cpu_adr=a; cpu_we=wr; cpu_ir=insn; cpu_dr=!insn && !wr;
   cpu_bs=mask; cpu_dat_w=data; idle(2); cpu_cs=1; timeout=0;
   begin : wait_ack
     forever begin
       @(posedge clk);
       if(dut_ack===1) begin sampled_dat=dut_dat; sampled_l1=dut.cpu_cacheline_i_valid || dut.cpu_cacheline_d_valid; disable wait_ack; end
       #2;
       timeout=timeout+1; if(timeout>80) $fatal(1,"Timeout addr=%h state=%0d",cpu_adr,dut.cpu_sm_state);
     end
   end
   if(wr) begin writes=writes+1; masks[mask]=masks[mask]+1; end
   else begin
     reads=reads+1;
     if(sampled_l1) l1hits=l1hits+1;
     if(sampled_dat !== memory[a/2]) begin
       $display("SCOREBOARD MISMATCH addr=%h expected=%h actual=%h reference=%h state=%0d",a,memory[a/2],sampled_dat,ref_dat,dut.cpu_sm_state);
       $fatal;
     end
   end
   @(negedge clk); #1; cpu_cs=0;
   transactions=transactions+1;
 end
endtask
task longwrite;
 input integer a, m, data;
 begin
   idle(12); cpu_adr=a; cpu_we=1; cpu_ir=0; cpu_dr=0; cpu_bs=m; cpu_dat_w=data; cpu_32bit=1; idle(2); cpu_cs=1;
   @(posedge clk); #2; @(negedge clk); #1;
   cpu_cs=0; repeat(3) begin @(negedge clk); #1; end
   cpu_adr=a+2; cpu_dat_w=~data; idle(2); cpu_cs=1;
   @(posedge clk); #2; @(negedge clk); #1;
   cpu_cs=0; cpu_32bit=0; transactions=transactions+1;
 end
endtask
initial begin
 for(k=0;k<32768;k=k+1) memory[k]=(k*73)^16'ha53c;
 for(k=0;k<4;k=k+1) begin way_hits[k]=0; masks[k]=0; end
 for(k=0;k<8;k=k+1) fills[k]=0;
 idle(4); rst=0; idle(280);
 // Misses at all burst starting offsets, both I and D, plus all line hit offsets.
 for(addr=0;addr<16;addr=addr+1) begin
   access((addr+1)*16+(addr%8)*2,0,addr%2,3,0);
   for(choice=0;choice<8;choice=choice+1) access((addr+1)*16+choice*2,0,addr%2,3,0);
 end
 // Force both ways, then reload the line buffers from each way.
 for(choice=0;choice<2;choice=choice+1) begin
   access('h400,0,choice,3,0); access('h1400,0,choice,3,0);
   access('h400,0,choice,3,0); access('h1400,0,choice,3,0);
 end
 // Byte updates must preserve the other byte and the other halfword.
 access('h200,0,0,3,0); access('h200,0,1,3,0);
 for(addr=0;addr<8;addr=addr+1) for(choice=0;choice<4;choice=choice+1) begin
   access('h200+2*addr,1,0,choice,'h1234+addr*256+choice);
   access('h200+2*addr,0,0,3,0); access('h200+2*addr,0,1,3,0);
 end
 for(addr=0;addr<7;addr=addr+1) begin
   longwrite('h200+addr*2,3,'hb010+addr);
   access('h200+addr*2,0,0,3,0); access('h202+addr*2,0,1,3,0);
 end
 // Cache controls and deterministic random traffic.
 for(choice=0;choice<1000;choice=choice+1) begin
   randval=$random(seed)&32'h7fffffff;
   cache_inhibit=(choice%17==0);
   cacheline_clr=(choice%23==0);
   cpu_cache_ctrl=(choice%31==0)?0:((choice%37==0)?3:1);
   access(((randval>>5)%32)*16+((randval>>2)%8)*2,randval%5==0,(randval>>10)%2,(randval>>12)%4,randval>>8);
   cacheline_clr=0;
 end
 cache_inhibit=0; cpu_cache_ctrl=1; idle(12);
 // Exercise snoop RAM updates plus explicit front-line invalidation.
 memory['h100]=16'hbeef; memory['h101]=16'hdead; snoop_adr='h200; snoop_dat_w=32'hdeadbeef; snoop_bs=15; snoop_act=1; cacheline_clr=1;
 idle(3); snoop_act=0; cacheline_clr=0; idle(10);
 access('h200,0,0,3,0); access('h200,0,1,3,0);
 $display("PASS normal equivalence: %0d transactions, %0d cycles, reads=%0d writes=%0d l1hits=%0d",transactions,cycles,reads,writes,l1hits);
 $display("way fill cycles I0/I1/D0/D1=%0d/%0d/%0d/%0d; masks=%0d/%0d/%0d/%0d",way_hits[0],way_hits[1],way_hits[2],way_hits[3],masks[0],masks[1],masks[2],masks[3]);
 $display("burst starts 0..7=%0d %0d %0d %0d %0d %0d %0d %0d",fills[0],fills[1],fills[2],fills[3],fills[4],fills[5],fills[6],fills[7]);
 // Demonstrate the reset gating regression at an active line write.
 cacheline_clr=1; idle(3); cacheline_clr=0;
 access('h100,0,0,3,0); idle(12);
 cpu_adr='h100; cpu_we=1; cpu_ir=0; cpu_dr=0; cpu_dat_w=16'h55aa; cpu_bs=3; cpu_cs=1;
 rst=1; monitor=0; before_reset=dut.cpu_cacheline_d[0];
 @(posedge clk); #2;
 if(dut.cpu_cacheline_d[0]===before_reset) $display("RESET write blocked");
 else $display("RESET REGRESSION: line changed from %h to %h while reference kept %h",before_reset,dut.cpu_cacheline_d[0],{refcache.cpu_cacheline_d_hi[1],refcache.cpu_cacheline_d_lo[1],refcache.cpu_cacheline_d_hi[0],refcache.cpu_cacheline_d_lo[0]});
 $finish;
end
initial begin #1000000; $fatal(1,"global timeout"); end
endmodule
