`timescale 1ns/1ps
// Exercise both CPU and snoop tag comparators, including unused tag-slot bits.
module cpu_cache_tags_case #(parameter ADDR_BITS=26, PREFIX_BITS=1)(output reg done=0);
  localparam TAG_BITS=ADDR_BITS-12;
  reg clk=0;
  always #5 clk=~clk;
  reg [ADDR_BITS+PREFIX_BITS-1:0] address=0;
  reg [25:0] snoop_address=0;
  reg [31:0] tags=0;
  reg [13:0] expected_tag=0;
  integer bit_index;
  cpu_cache_new #(.addr_max_bits(ADDR_BITS), .addr_prefix_bits(PREFIX_BITS), .addr_prefix(0)) dut (
    .clk(clk), .rst(1'b1), .cache_en(1'b1), .clk28_en(1'b1),
    .cpu_cache_ctrl(4'b0001), .cache_inhibit(1'b0), .cacheline_clr(1'b0),
    .cpu_cs(1'b0), .cpu_adr(address), .cpu_bs(2'b11), .cpu_32bit(1'b0),
    .cpu_we(1'b0), .cpu_ir(1'b0), .cpu_dr(1'b0), .cpu_dat_w(16'b0),
    .sdr_dat_r(16'b0), .sdr_read_ack(1'b0), .sdr_read_pre(1'b1), .sdr_write_ack(1'b0),
    .snoop_act(1'b0), .snoop_adr(snoop_address), .snoop_dat_w(32'b0), .snoop_bs(4'b0)
  );
  task check_matches;
    input way0, way1;
    begin
      #1;
      if ({dut.itag0_match,dut.dtag0_match,dut.sdr_itag0_match,dut.sdr_dtag0_match} !== {4{way0}} ||
          {dut.itag1_match,dut.dtag1_match,dut.sdr_itag1_match,dut.sdr_dtag1_match} !== {4{way1}})
        $fatal(1,"Tag compare failed: address bits=%0d prefix bits=%0d tags=%h",ADDR_BITS,PREFIX_BITS,tags);
    end
  endtask
  initial begin
    force dut.cpu_adr_l=address;
    force dut.itram_cpu_dat_r=tags;
    force dut.dtram_cpu_dat_r=tags;
    force dut.itram_sdr_dat_r=tags;
    force dut.dtram_sdr_dat_r=tags;
    // All unused slot bits are ones, all significant tag bits are initially zero.
    tags=32'hffffffff;
    tags[0 +: TAG_BITS]=0;
    tags[14 +: TAG_BITS]=0;
    snoop_address=26'h3ffffff;
    snoop_address[12 +: TAG_BITS]=0;
    check_matches(1,1);
    // Each significant bit must participate independently in each way comparison.
    for(bit_index=0;bit_index<TAG_BITS;bit_index=bit_index+1) begin
      tags[bit_index]=1;
      check_matches(0,1);
      tags[bit_index]=0;
      tags[14+bit_index]=1;
      check_matches(1,0);
      tags[14+bit_index]=0;
      address[12+bit_index]=1;
      snoop_address[12+bit_index]=1;
      check_matches(0,0);
      tags[bit_index]=1;
      tags[14+bit_index]=1;
      check_matches(1,1);
      expected_tag=14'b1<<bit_index;
      if(dut.cpu_adr_tag !== expected_tag || dut.cpu_adr_tag_l !== expected_tag)
        $fatal(1,"Incorrect zero-extended tag at address width %0d",ADDR_BITS);
      address[12+bit_index]=0;
      snoop_address[12+bit_index]=0;
      tags[bit_index]=0;
      tags[14+bit_index]=0;
    end
    // Prefix bits must be decoded separately and must never enter a tag slot.
    if(PREFIX_BITS>0) begin
      address[ADDR_BITS]=1;
      #1;
      if(dut.addr_prefix_match !== 0 || dut.cpu_adr_tag !== 0 || dut.cpu_adr_tag_l !== 0)
        $fatal(1,"Prefix leaked into tag at address width %0d",ADDR_BITS);
      address[ADDR_BITS]=0;
    end
    #1;
    if(dut.addr_prefix_match !== 1)
      $fatal(1,"Prefix match failed at address width %0d",ADDR_BITS);
    done=1;
  end
endmodule

module cpu_cache_tags_tb;
  wire [27:0] done;
  genvar width_index, prefix_index;
  generate
    for(width_index=0;width_index<14;width_index=width_index+1) begin: widths
      for(prefix_index=0;prefix_index<2;prefix_index=prefix_index+1) begin: prefixes
        cpu_cache_tags_case #(.ADDR_BITS(13+width_index), .PREFIX_BITS(prefix_index)) test_case
          (.done(done[2*width_index+prefix_index]));
      end
    end
  endgenerate
  initial begin
    wait(&done);
    $display("PASS dynamic tags: address widths 13..26, prefix widths 0/1, all CPU/snoop ways");
    $finish;
  end
  initial begin
    #1000;
    $fatal(1,"Tag test timed out");
  end
endmodule
