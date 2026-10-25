// cpu_cache_new.v
// 2015, rok.krajnc@gmail.com
// this is a 2-way set-associative cache
// seperate instruction and data caches
// write-through, look-through
// 8kB cache size, 4kB per way
// whole cache size (I+D) is 16kB
// ! requires Altera Quartus prepared memories because of the byte-selects !

// AMR - adjust for 8-word bursts.

module cpu_cache_new #(
    parameter addr_max_bits=26,
    parameter addr_prefix_bits=1,
    parameter addr_prefix=0,
    parameter last_pair_enable_i=1,
    parameter last_pair_enable_d=1,
    parameter unaligned_write_combine=1
) (
  // system
  input  wire           clk,            // clock
  input  wire           rst,            // cache reset
  input  wire           cache_en,       // cache enable
  input  wire           clk28_en,       // 28MHz enable signal
  input  wire [  4-1:0] cpu_cache_ctrl, // CPU cache control
  input  wire           cache_inhibit,  // cache inhibit
  input  wire           cacheline_clr,
  // cpu
  input  wire           cpu_cs,         // cpu activity
  input  wire           cpu_req,        // CPU request phase enable
  input  wire [  26+addr_prefix_bits-1:0] cpu_adr,        // cpu address
  input  wire [  2-1:0] cpu_bs,         // cpu byte selects
  input  wire           cpu_longword,   // legacy transfer-phase hint (optional combining)
  input  wire           cpu_long_cand,  // aligned 32-bit read/write candidate
  input  wire [15:0]    cpu_dat_w_lo,   // second word of a paired write
  output reg  [15:0]    cpu_dat_r_hi,   // first word of a paired read
  input  wire           cpu_we,         // cpu write
  input  wire           cpu_ir,         // cpu instruction read
  input  wire           cpu_dr,         // cpu data read
  input  wire [ 16-1:0] cpu_dat_w,      // cpu write data
  output reg  [ 16-1:0] cpu_dat_r,      // cpu read data
  output wire           cpu_ack,        // cpu acknowledge
  // sdram
  input  wire [ 16-1:0] sdr_dat_r,      // sdram read data
  output reg            sdr_read_req,   // sdram read request from cache
  input  wire           sdr_read_ack,   // sdram read acknowledge to cache
  input  wire           sdr_read_pre,   // sdram one cycle before it can accept a new request
  output reg  [ 26-1:1] sdr_adr,        // sdram address
  output reg  [ 32-1:0] sdr_dat_w,      // sdram write data
  output reg  [  4-1:0] sdr_dqm_w,      // sdram write byte selects (active low)
  output reg            sdr_write_req,  // sdram write request from cache
  input  wire           sdr_write_ack,  // sdram write acknowledge to cache
  // snoop
  input  wire           snoop_act,      // snoop act (write only - just update existing data in cache)
  input  wire [ 26-1:0] snoop_adr,      // chip address
  input  wire [ 32-1:0] snoop_dat_w,    // snoop write data
  input  wire [  4-1:0] snoop_bs        // snoop byte selects
);

// Protocol source for controller tests; deliberately no CPU/cache behavior.
initial begin
  sdr_adr=0; sdr_dat_w=0; sdr_dqm_w=15; sdr_write_req=0;
  sdr_read_req=0; cpu_dat_r=0; cpu_dat_r_hi=0;
end
assign cpu_ack=1'b0;
endmodule
