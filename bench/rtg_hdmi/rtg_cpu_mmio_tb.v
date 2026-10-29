// Exercise the real TG68K wrapper/kernel with RTG disabled, as during P96 setup.
// ROM/RAM responders are behavioral; this checks MMIO handshakes, not SDRAM timing.
`timescale 1ns/1ps
module rtg_cpu_mmio_tb #(
 parameter CHECK_MMIO=1,
 parameter CHECK_AKIKO=0,
 parameter CACHE_RAM=0,
 parameter DATA_CACHE=1,
 parameter LEGACY_WRITE_COMBINE=0,
 parameter OVERCLOCK=0,
 parameter VERBOSE=1,
 parameter TIMEOUT_NS=2000000
);
reg clk=0; always #5 clk=~clk;
reg reset_n=0;
reg [3:0] phase=0;
always @(posedge clk) phase<=phase+1'b1;
wire [31:0] addr,ramaddr;
// {longword, req_enable, ramcs_n, access_type[1:0]}
wire [4:0] cpustate;
reg cpu_ir=0, cpu_dr=0, cpu_we=0;
wire cpu_restore=cpustate[3] && cpustate[2];
// Match the registered access-type decode in sdram_ctrl.v. req_enable is
// separate from RAM CS and stays asserted while a peripheral cycle completes.
always @(posedge clk) begin
 cpu_ir <= cpustate[1:0]==0;
 cpu_dr <= cpustate[1:0]==2;
 cpu_we <= &cpustate[1:0];
end
wire [15:0] dw,toram;
wire as_n,rw,ramuds,ramlds;
wire [10:0] reg_addr;
wire [15:0] reg_d,reg_q;
wire reg_wr,reg_req,reg_ack;
reg [15:0] mem[0:4095];
wire [15:0] dr=mem[addr[12:1]];
wire [15:0] fromram, fromram_hi, toram_lo;
wire ram_long_cand;
wire ramready;
wire [3:0] cacr;
generate if(CACHE_RAM) begin: cached_ram
 reg [15:0] sdr_data=0;
 reg sdr_ack=0, write_ack=0;
 wire read_req, write_req;
 wire [25:1] write_addr;
 wire [31:0] write_data;
 wire [3:0] write_mask;
 integer beats=0, first=0, delay_count=0;
 cpu_cache_new #(.data_cache(DATA_CACHE),.unaligned_write_combine(LEGACY_WRITE_COMBINE)) cache(.clk(clk),.rstn(reset_n),.clr(1'b0),.cache_en(1'b1),.clk28_en(1'b1),
  .cpu_cache_ctrl(cacr),.cache_inhibit(1'b0),.cacheline_clr(1'b0),
  .cpu_cs(!cpustate[2]),.cpu_restore(cpu_restore),.cpu_adr({ramaddr[26:1],1'b0}),.cpu_bs({!ramuds,!ramlds}),
  .cpu_longword(cpustate[4]),.cpu_long_cand(ram_long_cand),
  .cpu_dat_w(toram),.cpu_dat_w_lo(toram_lo),.cpu_dat_r(fromram),.cpu_dat_r_hi(fromram_hi),
  .cpu_we(cpu_we),.cpu_ir(cpu_ir),.cpu_dr(cpu_dr),.cpu_ack(ramready),
  .sdr_dat_r(sdr_data),.sdr_read_req(read_req),.sdr_read_ack(sdr_ack),.sdr_read_pre(1'b1),
  .sdr_adr(write_addr),.sdr_dat_w(write_data),.sdr_dqm_w(write_mask),
  .sdr_write_req(write_req),.sdr_write_ack(write_ack),
  .snoop_act(1'b0),.snoop_adr(26'b0),.snoop_dat_w(32'b0),.snoop_bs(4'b0));
 always @(negedge clk) begin
  sdr_ack=0;
  if(beats>0) begin
   sdr_ack=1; sdr_data=mem[(first & ~7) | ((first+8-beats)&7)]; beats=beats-1;
  end else if(delay_count>0) begin
   delay_count=delay_count-1; if(delay_count==0) beats=8;
  end else if(read_req) begin
   first=ramaddr[12:1]; delay_count=4;
  end
  if(write_req!=write_ack) begin
   if(!write_mask[0]) mem[write_addr[12:1]][7:0]=write_data[7:0];
   if(!write_mask[1]) mem[write_addr[12:1]][15:8]=write_data[15:8];
   if(!write_mask[2]) mem[write_addr[12:1]+1][7:0]=write_data[23:16];
   if(!write_mask[3]) mem[write_addr[12:1]+1][15:8]=write_data[31:24];
   write_ack=write_req;
  end
 end
end else begin: narrow_ram
 reg ready=0;
 assign ramready=ready;
 // The wrapper assumes every aligned candidate is accepted, including here.
 wire pair=ram_long_cand && !ramaddr[1] && !ramuds && !ramlds;
 assign fromram=mem[ramaddr[12:1]+(pair ? 1 : 0)];
 assign fromram_hi=mem[ramaddr[12:1]];
reg served=0;
always @(posedge clk) begin
 ready<=0;
 if(cpustate[2] || ramready) served<=0;
 else if(!served) begin
  ready<=1;served<=1;
  if(cpustate[1:0]==2'b11) begin
   if(!ramuds) mem[ramaddr[12:1]][15:8]<=toram[15:8];
   if(!ramlds) mem[ramaddr[12:1]][7:0]<=toram[7:0];
   if(pair) mem[ramaddr[12:1]+1]<=toram_lo;
  end
 end
end
end endgenerate
integer wide_reads=0, wide_writes=0, wide_extensions=0;
integer legacy_writes=0;
integer akiko_reads=0, akiko_writes=0, akiko_fill_exits=0;
generate if(CACHE_RAM) begin
 always @(posedge clk) begin
  if(CHECK_AKIKO && reset_n) begin
   if(cpu.akiko_req && cpu.akiko_ack) begin
    if(cpu.akiko_wr) akiko_writes<=akiko_writes+1;
    else akiko_reads<=akiko_reads+1;
   end
   // A fill can end on the edge that completes a peripheral request. The
   // parked instruction prediction must survive that FILL2 -> IDLE handoff.
   if(cached_ram.cache.cpu_sm_state==9 && !cached_ram.sdr_ack &&
      cpu_restore && cpu.akiko_ack)
    akiko_fill_exits<=akiko_fill_exits+1;
  end
  if(cached_ram.cache.cpu_sm_state==2) legacy_writes<=legacy_writes+1;
  if(!cpustate[2] && ramready && !cpustate[0]) begin
   if(ram_long_cand && !ramaddr[1] && !ramuds && !ramlds) begin
    if({fromram_hi,fromram} !== {mem[ramaddr[12:1]],mem[ramaddr[12:1]+1]})
     $fatal(1,"CPU/cache paired read mismatch at %h: %h %h",ramaddr,fromram_hi,fromram);
   end else if(fromram !== mem[ramaddr[12:1]])
    $fatal(1,"CPU/cache read mismatch at %h: got %h expected %h",ramaddr,fromram,mem[ramaddr[12:1]]);
  end
 end
end endgenerate
always @(posedge clk) begin
 if(ram_long_cand && !cpustate[2] && ramready) begin
  if(cpustate[1:0]==3) wide_writes<=wide_writes+1;
  else begin
   wide_reads<=wide_reads+1;
   if(cpustate[1:0]==0) wide_extensions<=wide_extensions+1;
  end
 end
 if(ram_long_cand && !cpustate[2] && (reg_req || !as_n))
  $fatal(1,"Wide candidate escaped onto MMIO/chipset path");
 if(!as_n && !rw && phase==15) mem[addr[12:1]]<=dw;
 if(reg_req && !(reg_addr[10] || reg_addr[9:8]==2'b01))
  $fatal(1,"TG68K asserted an unqualified RTG request");
 // Test-only write trace in RAM at $1200 + register offset. Driver ROMs
 // inspect this trace instead of reading write-only configuration from RTG.
 if(reg_ack && reg_wr && reg_addr[10:8]==3'b001)
  mem['h900+reg_addr[7:1]]<=reg_d;
 if(!CHECK_MMIO && reg_ack && !reg_wr &&
    reg_addr!=11'h10c && reg_addr!=11'h10e && reg_addr!=11'h110)
  $fatal(1,"driver ROM read a write-only RTG register %h",reg_addr);
 if(VERBOSE && reg_ack) $display("RTG %s %h %h",reg_wr?"W":"R",reg_addr,reg_wr?reg_d:reg_q);
 if(mem['h800]==16'h600d) begin
  if(CHECK_AKIKO) begin
   if(akiko_reads!=128 || akiko_writes!=128)
    $fatal(1,"Incomplete Akiko loop: reads=%0d writes=%0d",akiko_reads,akiko_writes);
   if(DATA_CACHE && OVERCLOCK && akiko_fill_exits==0)
    $fatal(1,"Akiko ACK did not overlap a cache fill exit");
   $display("PASS: TG68K Akiko/cache loop reads=%0d writes=%0d fill-exit overlaps=%0d",
            akiko_reads,akiko_writes,akiko_fill_exits);
  end else
  if(CHECK_MMIO) begin
   if({rtg.rtg_base,4'b0}!==26'h123450 || {rtg.rtg_base2,4'b0}!==26'h567890 || rtg.clut[0]!==24'h123456 || rtg.clut[1]!==24'h654321 || rtg.split_line!==384) $fatal(1,"wrong registers");
   // The IcePi Zero board configuration enables paired data accesses;
   // instruction-extension pairing is optional in tg68k_datapath32.
   if(CACHE_RAM && (wide_reads==0 || wide_writes==0)) $fatal(1,"Wide CPU/cache paths not exercised");
   if(CACHE_RAM && LEGACY_WRITE_COMBINE && legacy_writes==0) $fatal(1,"Legacy write combining not exercised");
   $display("PASS: actual 68020 CPU RTG MMIO reads and longword writes");
  end else
   $display("PASS: driver callback ROM completed on TG68K/RTG hardware");
  $finish;
 end
 if(mem['h800]==16'hdead) $fatal(1,"CPU register read comparison failed");
end
TG68K cpu(.clk(clk),.reset(reset_n),.clkena_in(phase[1:0]==0),.IPL(3'b111),.dtack(1'b0),.freeze(1'b0),.vpa(1'b1),.ein(1'b0),
.addr(addr),.data_read(dr),.data_read2(dr),.data_write(dw),.rw(rw),.as(as_n),.ena7RDreg(phase==7),.ena7WRreg(phase==15),
.fromram_hi(fromram_hi),.toram_lo(toram_lo),.ram_long_cand(ram_long_cand),.CACR_out(cacr),.fromram(fromram),.toram(toram),.ramready(ramready),.overclock(OVERCLOCK != 0),.cpu(2'b11),.ziiram_active(1'b0),.ziiiram_active(1'b0),.ziiiram2_active(1'b0),.ziiiram3_active(1'b0),.eth_en(1'b0),.frometh(16'b0),.ethready(1'b0),.chip_config(2'b11),.slow_config(2'b00),.aga(1'b1),.turbochipram(1'b1),.turbokick(1'b1),.ramaddr(ramaddr),.cpustate(cpustate),.ramlds(ramlds),.ramuds(ramuds),
.rtg_reg_addr(reg_addr),.rtg_reg_d(reg_d),.rtg_reg_wr(reg_wr),.rtg_reg_req(reg_req),.rtg_reg_ack(reg_ack),.rtg_reg_q(reg_q),.audio_buf(1'b0),.host_addr(8'd0),.host_ack(1'b0),.host_q(16'b0));
rtg_video
rtg(.clk_sys(clk),.clk_rtg(clk),.resetn_sys(reset_n),.cpu_resetn(reset_n),.resetn_rtg(reset_n),.rtg_active(1'b0),.video_reset(1'b1),.frame_start_toggle(1'b0),.vblank_start_toggle(1'b0),.pixel_request(1'b0),.frame_request(1'b0),.line_prepare(1'b0),.reg_addr(reg_addr),.reg_wr(reg_wr),.reg_req(reg_req),.reg_d(reg_d),.reg_ack(reg_ack),.reg_q(reg_q),.fetch_d(16'd0),.fetch_ack(1'b0),.fetch_fill(1'b0));
integer i;
reg [1023:0] image_path;
initial begin
 for(i=0;i<4096;i=i+1) mem[i]=0;
 if(!$value$plusargs("image=%s",image_path)) $fatal(1,"missing +image=<ROM hex>");
 $readmemh(image_path,mem);
 #200;reset_n=1;
 #TIMEOUT_NS;
 $fatal(1,"CPU timeout addr=%h ramaddr=%h state=%b regreq=%b ack=%b",addr,ramaddr,cpustate,reg_req,reg_ack);
end
endmodule
