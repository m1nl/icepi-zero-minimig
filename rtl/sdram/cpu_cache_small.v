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
    parameter data_cache=1,
    parameter unaligned_write_combine=1
) (
  // system
  input  wire           clk,            // clock
  input  wire           rstn,           // cache reset
  input  wire           clr,            // cache clear
  input  wire           cache_en,       // cache enable
  input  wire           clk28_en,       // 28MHz enable signal
  input  wire [  4-1:0] cpu_cache_ctrl, // CPU cache control
  input  wire           cache_inhibit,  // cache inhibit
  input  wire           cacheline_clr,
  // cpu
  input  wire           cpu_cs,         // cpu activity
  input  wire           cpu_restore,    // restore cache prediction
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

wire addr_prefix_match;
generate
	if(addr_prefix_bits)
		assign addr_prefix_match = cpu_adr[26+addr_prefix_bits-1:26]==addr_prefix[addr_prefix_bits-1:0] ? 1'b1 : 1'b0;
	else
		assign addr_prefix_match = 1'b1;
endgenerate

//// internal signals ////

// cache init
reg           cache_init_done;
reg           cache_init_done_seen;
// state
reg  [ 4-1:0] cpu_sm_state;
reg  [ 2-1:0] sdr_sm_state;
// state signals
reg           cpu_acked;
reg           cpu_cache_ack;
reg  [11-1:0] cpu_sm_adr_i;
reg  [11-1:0] cpu_sm_adr_d;
wire [11-1:0] cpu_sm_adr_next_i = { cpu_sm_adr_i[10:3], cpu_sm_adr_i[2:0] + 2'b01 };
wire [11-1:0] cpu_sm_adr_next_d = { cpu_sm_adr_d[10:3], cpu_sm_adr_d[2:0] + 2'b01 };
reg           cpu_sm_itag_we;
reg           cpu_sm_dtag_we;
reg           cpu_sm_iram0_we;
reg           cpu_sm_iram1_we;
reg           cpu_sm_dram0_we;
reg           cpu_sm_dram1_we;
reg  [ 4-1:0] cpu_sm_bs;
reg  [32-1:0] cpu_sm_mem_dat_w;
reg  [32-1:0] cpu_sm_tag_dat_w;
reg           cpu_sm_id;
reg           cpu_sm_ilru;
reg           cpu_sm_dlru;
reg  [14-1:0] sdr_sm_tag_adr;
reg  [10-1:0] sdr_sm_adr;
reg           sdr_sm_itag_we;
reg           sdr_sm_dtag_we;
reg           sdr_sm_iram0_we;
reg           sdr_sm_iram1_we;
reg           sdr_sm_dram0_we;
reg           sdr_sm_dram1_we;
reg  [ 4-1:0] sdr_sm_bs;
reg  [32-1:0] sdr_sm_mem_dat_w;
reg  [32-1:0] sdr_sm_tag_dat_w;
reg           sdr_sm_id;
reg           sdr_sm_ilru;
reg           sdr_sm_dlru;
reg  [15:0]   cpu_dat_l;
reg  [1:0]    cpu_bs_l;
reg           cpu_pair;
reg           read_pair_pending;
// The kernel only offers aligned full-word pairs. Check again at this boundary.
wire          pair_cand = cpu_long_cand && (cpu_adr[1:0] == 2'b00) && (&cpu_bs);

// cpu cache control
wire          cpu_cache_enable;
wire          cpu_cache_freeze;
wire          cpu_cache_clear;
reg           cc_en;
reg           cc_fr;
// cpu address
reg  [26+addr_prefix_bits-1:0] cpu_adr_l;
reg  [ 3-1:0] cpu_adr_blk_ptr;
wire [ 3-1:0] cpu_adr_blk;
wire [ 3-1:0] cpu_adr_blk_l;
wire [ 8-1:0] cpu_adr_idx;
wire [ 8-1:0] cpu_adr_idx_l;
wire [14-1:0] cpu_adr_tag;
wire [14-1:0] cpu_adr_tag_l;

reg           level1_i;
wire          level1_d = ~level1_i;

// idram0
wire [10-1:0] idram0_cpu_adr;
wire [ 4-1:0] idram0_cpu_bs;
wire          idram0_cpu_we;
wire [32-1:0] idram0_cpu_dat_w;
wire [32-1:0] idram0_cpu_dat_r;
wire [10-1:0] idram0_sdr_adr;
wire [ 4-1:0] idram0_sdr_bs;
wire          idram0_sdr_we;
wire [32-1:0] idram0_sdr_dat_w;
wire [32-1:0] idram0_sdr_dat_r;
// idram1
wire [10-1:0] idram1_cpu_adr;
wire [ 4-1:0] idram1_cpu_bs;
wire          idram1_cpu_we;
wire [32-1:0] idram1_cpu_dat_w;
wire [32-1:0] idram1_cpu_dat_r;
wire [10-1:0] idram1_sdr_adr;
wire [ 4-1:0] idram1_sdr_bs;
wire          idram1_sdr_we;
wire [32-1:0] idram1_sdr_dat_w;
wire [32-1:0] idram1_sdr_dat_r;
// ddram0
wire [10-1:0] ddram0_cpu_adr;
wire [ 4-1:0] ddram0_cpu_bs;
wire          ddram0_cpu_we;
wire [32-1:0] ddram0_cpu_dat_w;
wire [32-1:0] ddram0_cpu_dat_r;
wire [10-1:0] ddram0_sdr_adr;
wire [ 4-1:0] ddram0_sdr_bs;
wire          ddram0_sdr_we;
wire [32-1:0] ddram0_sdr_dat_w;
wire [32-1:0] ddram0_sdr_dat_r;
// ddram1
wire [10-1:0] ddram1_cpu_adr;
wire [ 4-1:0] ddram1_cpu_bs;
wire          ddram1_cpu_we;
wire [32-1:0] ddram1_cpu_dat_w;
wire [32-1:0] ddram1_cpu_dat_r;
wire [10-1:0] ddram1_sdr_adr;
wire [ 4-1:0] ddram1_sdr_bs;
wire          ddram1_sdr_we;
wire [32-1:0] ddram1_sdr_dat_w;
wire [32-1:0] ddram1_sdr_dat_r;
// itram
wire [ 8-1:0] itram_cpu_adr;
wire          itram_cpu_we;
wire [32-1:0] itram_cpu_dat_w;
wire [32-1:0] itram_cpu_dat_r;
wire [ 8-1:0] itram_sdr_adr;
wire          itram_sdr_we;
wire [32-1:0] itram_sdr_dat_w;
wire [32-1:0] itram_sdr_dat_r;
wire          itag0_match;
wire          itag1_match;
wire          itag_hit;
wire          itag_lru;
wire          itag0_valid;
wire          itag1_valid;
wire          sdr_itag0_match;
wire          sdr_itag1_match;
wire          sdr_itag_hit;
wire          sdr_itag_lru;
wire          sdr_itag0_valid;
wire          sdr_itag1_valid;
// dtram
wire [ 8-1:0] dtram_cpu_adr;
wire          dtram_cpu_we;
wire [32-1:0] dtram_cpu_dat_w;
wire [32-1:0] dtram_cpu_dat_r;
wire [ 8-1:0] dtram_sdr_adr;
wire          dtram_sdr_we;
wire [32-1:0] dtram_sdr_dat_w;
wire [32-1:0] dtram_sdr_dat_r;
wire          dtag0_match;
wire          dtag1_match;
wire          dtag_hit;
wire          dtag_lru;
wire          dtag0_valid;
wire          dtag1_valid;
wire          sdr_dtag0_match;
wire          sdr_dtag1_match;
wire          sdr_dtag_hit;
wire          sdr_dtag_lru;
wire          sdr_dtag0_valid;
wire          sdr_dtag1_valid;

reg  [26-1:2] cacheline_adr_i;
reg           cacheline_valid_i;
reg           cacheline_ready_i;
reg           cacheline_way_i;

reg  [26-1:2] cacheline_adr_d;
reg           cacheline_valid_d;
reg           cacheline_ready_d;
reg           cacheline_way_d;

wire          cacheline_hit_i = cpu_ir && cc_en && !cache_inhibit && addr_prefix_match
                                && cacheline_ready_i && (cpu_adr[25:2] == cacheline_adr_i);
wire          cacheline_hit_d = cpu_dr && cc_en && !cache_inhibit && addr_prefix_match
                                && cacheline_ready_d && (cpu_adr[25:2] == cacheline_adr_d);

wire [11-1:0] cacheline_sm_adr_d = {cacheline_adr_d[11:2], 1'b0};
wire [11-1:0] cacheline_sm_adr_i = {cacheline_adr_i[11:2], 1'b0};

//// params ////

// cpu-side state machine
localparam [3:0]
  CPU_SM_INIT  = 4'd0,
  CPU_SM_IDLE  = 4'd1,
  CPU_SM_WAIT_LOWORD = 4'd2,
  CPU_SM_WRITE_32BIT = 4'd3,
  CPU_SM_WRITE = 4'd4,
  CPU_SM_WB    = 4'd5,
  CPU_SM_READ  = 4'd6,
  CPU_SM_WAIT  = 4'd7,
  CPU_SM_FILL1 = 4'd8,
  CPU_SM_FILL2 = 4'd9,
  CPU_SM_FILLW = 4'd10;

// sdram-side state machine
localparam [1:0]
  SDR_SM_INIT0 = 2'd0,
  SDR_SM_INIT1 = 2'd1,
  SDR_SM_IDLE  = 2'd2,
  SDR_SM_SNOOP = 2'd3;


//// cpu side ////

reg  [ 2-1:0] cc_clr_r;
reg           cc_clr_pending;

reg           cache_clear_req;
reg           cache_clear_start;

// cpu cache control
always @ (posedge clk, negedge rstn) begin
  if (!rstn) begin
    cc_clr_r <= #1 2'd0;
    cache_clear_req <= #1 1'b0;
    cache_clear_start <= #1 1'b0;

  end else begin
    // edge detector for cache clear request
    if (!cpu_cs) cc_clr_r <= #1 {cc_clr_r[0], cpu_cache_ctrl[3]};
    // mark request of cache clear request
    cache_clear_req <= #1 cc_clr_pending || cpu_cache_clear;
    // mark start of cache clear phase
    cache_clear_start <= #1 cache_clear_req && cpu_sm_state == CPU_SM_INIT;
  end
end

assign cpu_cache_enable = cpu_cache_ctrl[0];
assign cpu_cache_freeze = cpu_cache_ctrl[1];
assign cpu_cache_clear  = cc_clr_r[0] && !cc_clr_r[1];

always @ (posedge clk, negedge rstn) begin
  if (!rstn) begin
    cc_en <= #1 1'b0;
    cc_fr <= #1 1'b0;
  end else if (!cpu_cs) begin
    cc_en <= #1 cpu_cache_enable;
    cc_fr <= #1 cpu_cache_freeze;
  end
end

// slice up cpu address
assign cpu_adr_blk = cpu_adr[3:1];    // cache block address (inside cache row), 3 bits for 8x16 rows
assign cpu_adr_idx = cpu_adr[11:4];   // cache row address, 8 bits
assign cpu_adr_tag = cpu_adr[25:12];  // tag, 14 bits

// latched copies - needed for writes, since CPU can continue before the write is recorded in cache / RAM.
assign cpu_adr_blk_l = cpu_adr_l[3:1];    // cache block address (inside cache row), 3 bits for 8x16 rows
assign cpu_adr_idx_l = cpu_adr_l[11:4];   // cache row address, 8 bits
assign cpu_adr_tag_l = cpu_adr_l[25:12];  // tag, 14 bits

assign cpu_ack = cpu_cache_ack;

`ifdef COUNTWAITSTATES
reg [7:0] writewaitctr /* synthesis noprune */;
reg [23:0] writeholdoffctr /* synthesis noprune */;

reg cpu_cacheline_w_ready;

always @(posedge clk) cpu_cacheline_w_ready <= addr_prefix_match && cpu_we;

always @(posedge clk) begin
	if (cpu_cs && addr_prefix_match && cpu_we && !cpu_cacheline_w_ready)
		writewaitctr <= writewaitctr + 1'b1;
	else begin
		writewaitctr <= 8'h00;
	end
	if(writewaitctr == 8'h01)
		writeholdoffctr <= writeholdoffctr+1'b1;
end
`endif

always @(posedge clk) begin
	cpu_dat_l <= cpu_dat_w;
	cpu_bs_l <= cpu_bs;
end

// cpu side state machine
always @ (posedge clk, negedge rstn) begin
  if (!rstn) begin
    sdr_read_req      <= #1 1'b0;
    cpu_sm_state      <= #1 CPU_SM_INIT;
    cc_clr_pending    <= #1 1'b0;
    cpu_sm_itag_we    <= #1 1'b0;
    cpu_sm_dtag_we    <= #1 1'b0;
    cpu_sm_iram0_we   <= #1 1'b0;
    cpu_sm_iram1_we   <= #1 1'b0;
    cpu_sm_dram0_we   <= #1 1'b0;
    cpu_sm_dram1_we   <= #1 1'b0;
    sdr_write_req     <= #1 1'b0;
    cpu_cache_ack     <= #1 1'b0;
    cacheline_valid_i <= #1 1'b0;
    cacheline_valid_d <= #1 1'b0;
    cacheline_ready_i <= #1 1'b0;
    cacheline_ready_d <= #1 1'b0;

    cache_init_done_seen <= #1 1'b0;
  end else begin
    // default values
    sdr_read_req    <= #1 1'b0;
    cpu_sm_itag_we  <= #1 1'b0;
    cpu_sm_dtag_we  <= #1 1'b0;
    cpu_sm_iram0_we <= #1 1'b0;
    cpu_sm_iram1_we <= #1 1'b0;
    cpu_sm_dram0_we <= #1 1'b0;
    cpu_sm_dram1_we <= #1 1'b0;
    cpu_cache_ack   <= #1 1'b0;

    if (clr || cpu_cache_clear)
      cc_clr_pending <= #1 1'b1;

    // state machine
    case (cpu_sm_state)
      CPU_SM_INIT : begin
        // invalidate cachelines
        cacheline_valid_i <= #1 1'b0;
        cacheline_valid_d <= #1 1'b0;
        cacheline_ready_i <= #1 1'b0;
        cacheline_ready_d <= #1 1'b0;

        // clear pending flag
        cc_clr_pending <= #1 1'b0;

        // register that cache clear has completed
        if (cache_init_done)
          cache_init_done_seen <= #1 1'b1;

        // waiting for cache init
        if (cache_init_done_seen && !clr) begin
          cpu_sm_state <= #1 CPU_SM_IDLE;
        end
      end
      CPU_SM_IDLE : begin
        cpu_acked <= #1 1'b0;
        cpu_pair <= #1 pair_cand;
        cpu_adr_l <= cpu_adr;
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        if (cpu_restore) begin
          cpu_sm_adr_i <= #1 cacheline_sm_adr_i;
          cpu_sm_adr_d <= #1 cacheline_sm_adr_d;
        end else begin
          cpu_sm_adr_i <= #1 {cpu_adr_idx, cpu_adr_blk};
          cpu_sm_adr_d <= #1 {cpu_adr_idx, cpu_adr_blk};
        end
        level1_i <= cpu_ir;
        if (cpu_cs && addr_prefix_match) begin
          // speculatively move cacheline pointer to next word
          if (!cpu_we) begin
            if (cpu_ir) cacheline_adr_i <=
                #1 {cpu_adr[25:4], cpu_adr[3:2] + ((pair_cand || cpu_adr[1]) ? 2'd1 : 2'd0)};
            if (cpu_dr) cacheline_adr_d <=
                #1 {cpu_adr[25:4], cpu_adr[3:2] + ((pair_cand || cpu_adr[1]) ? 2'd1 : 2'd0)};
          end
          if (cpu_we) begin
            if (sdr_write_req == sdr_write_ack) begin
              cpu_cache_ack <= #1 1'b1;
              sdr_adr <= #1 cpu_adr[25:1];
              // SDRAM/cache storage puts address + 0 in the lower half.
              sdr_dqm_w <= #1 pair_cand ? 4'b0000 : {2'b11, ~cpu_bs};
              sdr_dat_w <= #1 {pair_cand ? cpu_dat_w_lo : cpu_dat_w, cpu_dat_w};
              // Optional old protocol: collect a second narrow CPU write.
              // Prefer the new complete pair, and never combine across a line.
              if (unaligned_write_combine && !pair_cand && cpu_longword && cpu_adr[3:1] != 3'b111)
                cpu_sm_state <= #1 CPU_SM_WAIT_LOWORD;
              else
                cpu_sm_state <= #1 CPU_SM_WRITE;
            end
          end else if (cacheline_hit_i) begin
            if (cacheline_way_i) begin
                cpu_dat_r <= (pair_cand || cpu_adr[1]) ? idram1_cpu_dat_r[31:16] : idram1_cpu_dat_r[15:0];
                cpu_dat_r_hi <= #1 idram1_cpu_dat_r[15:0];
            end else begin
                cpu_dat_r <= (pair_cand || cpu_adr[1]) ? idram0_cpu_dat_r[31:16] : idram0_cpu_dat_r[15:0];
                cpu_dat_r_hi <= #1 idram0_cpu_dat_r[15:0];
            end
            cpu_cache_ack <= #1 1'b1;
            cpu_sm_state <= #1 CPU_SM_WAIT;
          end else if (cacheline_hit_d && data_cache) begin
            if (cacheline_way_d) begin
                cpu_dat_r <= (pair_cand || cpu_adr[1]) ? ddram1_cpu_dat_r[31:16] : ddram1_cpu_dat_r[15:0];
                cpu_dat_r_hi <= #1 ddram1_cpu_dat_r[15:0];
            end else begin
                cpu_dat_r <= (pair_cand || cpu_adr[1]) ? ddram0_cpu_dat_r[31:16] : ddram0_cpu_dat_r[15:0];
                cpu_dat_r_hi <= #1 ddram0_cpu_dat_r[15:0];
            end
            cpu_cache_ack <= #1 1'b1;
            cpu_sm_state <= #1 CPU_SM_WAIT;
          end else begin
            cpu_sm_state <= #1 CPU_SM_READ;
          end
        end else begin
          if (cache_clear_req) begin
            cache_init_done_seen <= #1 1'b0;
            cpu_sm_state <= #1 CPU_SM_INIT;
          end
        end
      end
      CPU_SM_WAIT_LOWORD : begin
        // cache clear during combined write is anomaly
        // we don't need to handle it gracefully
        // but we don't want missing cpu_cs to block the fsm
        if (cache_clear_req) begin
          cache_init_done_seen <= #1 1'b0;
          cpu_sm_state <= #1 CPU_SM_INIT;
        end
        if (!cpu_cs) begin
          cpu_sm_state <= #1 CPU_SM_WRITE_32BIT;
        end
      end
      CPU_SM_WRITE_32BIT : begin
        // cache clear during combined write is anomaly
        // we don't need to handle it gracefully
        // but we don't want missing cpu_cs to block the fsm
        if (cache_clear_req) begin
          cache_init_done_seen <= #1 1'b0;
          cpu_sm_state <= #1 CPU_SM_INIT;
        end
        sdr_dqm_w[3:2] <= #1 ~cpu_bs;
        sdr_dat_w[31:16] <= #1 cpu_dat_w;
        if (itag0_match || itag1_match) cacheline_ready_i <= #1 0;
        if (dtag0_match || dtag1_match) cacheline_ready_d <= #1 0;
        if (cpu_cs) begin
          cpu_adr_l <= cpu_adr;
          cpu_adr_blk_ptr <= #1 cpu_adr_blk;
          // on hit update cache, on miss no update neccessary; tags don't get updated on writes
          if (!cpu_adr_blk[0]) begin
            // unaligned 32 bit write, hi word
            cpu_sm_bs <= #1 {~sdr_dqm_w[1:0], 2'b00};
            cpu_sm_mem_dat_w[31:16] <= #1 sdr_dat_w[15:0];
            cpu_sm_state <= #1 CPU_SM_WRITE;
          end else begin
            // aligned 32 bit write, do it in one step
            cpu_sm_bs <= #1 {cpu_bs, ~sdr_dqm_w[1:0]};
            cpu_sm_mem_dat_w <= #1 {cpu_dat_w, sdr_dat_w[15:0]};
            cpu_adr_blk_ptr <= #1 cpu_adr_blk;
            sdr_write_req <= !sdr_write_req;
            // ACK must be consumed before accepting another request.
            cpu_sm_state <= #1 CPU_SM_WAIT;
          end
          cpu_sm_iram0_we <= #1 itag0_match && itag0_valid /*&& !cc_fr*/;
          cpu_sm_iram1_we <= #1 itag1_match && itag1_valid /*&& !cc_fr*/;
          cpu_sm_dram0_we <= #1 dtag0_match && dtag0_valid /*&& !cc_fr*/;
          cpu_sm_dram1_we <= #1 dtag1_match && dtag1_valid /*&& !cc_fr*/;
          cpu_cache_ack <= #1 1'b1;
        end
      end
      CPU_SM_WRITE : begin
        sdr_write_req <= !sdr_write_req;
        // on hit update cache, on miss no update neccessary; tags don't get updated on writes
        if (itag0_match || itag1_match) begin
          cpu_sm_adr_i <= #1 {cpu_adr_idx_l, cpu_adr_blk_l};
          cacheline_ready_i <= #1 0;
        end else cpu_sm_adr_i <= #1 cacheline_sm_adr_i;
        if (dtag0_match || dtag1_match) begin
          cpu_sm_adr_d <= #1 {cpu_adr_idx_l, cpu_adr_blk_l};
          cacheline_ready_d <= #1 0;
        end else cpu_sm_adr_d <= #1 cacheline_sm_adr_d;
        cpu_sm_bs <= #1 cpu_pair ? 4'b1111 :
          (cpu_adr_blk_ptr[0] ? {cpu_bs_l, 2'b00} : {2'b00, cpu_bs_l});
        cpu_sm_mem_dat_w <= #1 (unaligned_write_combine && !cpu_pair) ?
          {cpu_dat_l, cpu_dat_l} : sdr_dat_w;
        cpu_sm_iram0_we <= #1 itag0_match && itag0_valid /*&& !cc_fr*/;
        cpu_sm_iram1_we <= #1 itag1_match && itag1_valid /*&& !cc_fr*/;
        cpu_sm_dram0_we <= #1 dtag0_match && dtag0_valid /*&& !cc_fr*/;
        cpu_sm_dram1_we <= #1 dtag1_match && dtag1_valid /*&& !cc_fr*/;
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        cpu_sm_state <= #1 CPU_SM_IDLE;
      end
      CPU_SM_READ : begin
        cpu_adr_l <= cpu_adr;
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        cpu_pair <= #1 pair_cand;
        if (level1_i) begin
          cacheline_valid_i <= #1 1'b1;
          cacheline_ready_i <= #1 1'b0;
          cacheline_adr_i <= #1 {cpu_adr[25:4], cpu_adr[3:2] + ((pair_cand || cpu_adr[1]) ? 2'd1 : 2'd0)};
          cpu_sm_adr_i <= #1 {cpu_adr_idx, cpu_adr_blk};
          // prepare data for tag
          cpu_sm_tag_dat_w <= #1 {!(itag0_valid && itag0_match), itram_cpu_dat_r[30:0]};
        end else cpu_sm_adr_i <= #1 cacheline_sm_adr_i;
        if (level1_d && data_cache) begin
          cacheline_valid_d <= #1 1'b1;
          cacheline_ready_d <= #1 1'b0;
          cacheline_adr_d <= #1 {cpu_adr[25:4], cpu_adr[3:2] + ((pair_cand || cpu_adr[1]) ? 2'd1 : 2'd0)};
          cpu_sm_adr_d <= #1 {cpu_adr_idx, cpu_adr_blk};
          // prepare data for tag
          cpu_sm_tag_dat_w <= #1 {!(dtag0_valid && dtag0_match), dtram_cpu_dat_r[30:0]};
        end else cpu_sm_adr_d <= #1 cacheline_sm_adr_d;
        if (cpu_cs)
           cpu_sm_state <= CPU_SM_WAIT;
        else begin
           cacheline_ready_i <= #1 cacheline_valid_i;
           cacheline_ready_d <= #1 cacheline_valid_d;
           cpu_sm_state <= CPU_SM_IDLE;
        end
        if (cc_en && level1_i && itag0_valid && itag0_match) begin
          // data is already in instruction cache way 0
          cpu_sm_itag_we <= #1 1'b1;
          cpu_dat_r <= (pair_cand || cpu_adr[1]) ? idram0_cpu_dat_r[31:16] : idram0_cpu_dat_r[15:0];
          cpu_dat_r_hi <= #1 idram0_cpu_dat_r[15:0];
          cacheline_way_i <= #1 1'b0;
          cpu_cache_ack <= #1 1'b1;

        end else if (cc_en && level1_i && itag1_valid && itag1_match) begin
          // data is already in instruction cache way 1
          cpu_sm_itag_we <= #1 1'b1;
          cpu_dat_r <= (pair_cand || cpu_adr[1]) ? idram1_cpu_dat_r[31:16] : idram1_cpu_dat_r[15:0];
          cpu_dat_r_hi <= #1 idram1_cpu_dat_r[15:0];
          cacheline_way_i <= #1 1'b1;
          cpu_cache_ack <= #1 1'b1;

        end else if (cc_en && level1_d && dtag0_valid && dtag0_match && data_cache) begin
          // data is already in data cache way 0
          cpu_sm_dtag_we <= #1 1'b1;
          cpu_dat_r <= (pair_cand || cpu_adr[1]) ? ddram0_cpu_dat_r[31:16] : ddram0_cpu_dat_r[15:0];
          cpu_dat_r_hi <= #1 ddram0_cpu_dat_r[15:0];
          cacheline_way_d <= #1 1'b0;
          cpu_cache_ack <= #1 1'b1;

        end else if (cc_en && level1_d && dtag1_valid && dtag1_match && data_cache) begin
          // data is already in data cache way 1
          cpu_sm_dtag_we <= #1 1'b1;
          cpu_dat_r <= (pair_cand || cpu_adr[1]) ? ddram1_cpu_dat_r[31:16] : ddram1_cpu_dat_r[15:0];
          cpu_dat_r_hi <= #1 ddram1_cpu_dat_r[15:0];
          cacheline_way_d <= #1 1'b1;
          cpu_cache_ack <= #1 1'b1;

        end else begin
          // stay in SM_READ until SDRAM is one cycle before it can
          // accept request; this may increase cache hit rate
          // when address decoding fails (when overclock is active)
          if (!sdr_read_ack && sdr_read_pre) begin
            sdr_read_req <= #1 1'b1;
            cpu_sm_state <= #1 CPU_SM_FILL1;
          end else begin
            cpu_sm_state <= CPU_SM_READ;
          end
        end
      end
      CPU_SM_WAIT : begin
        if (cpu_cs) begin
          cacheline_ready_i <= #1 cacheline_valid_i;
          cacheline_ready_d <= #1 cacheline_valid_d;
          cpu_sm_adr_i <= #1 cacheline_sm_adr_i;
          cpu_sm_adr_d <= #1 cacheline_sm_adr_d;
          cpu_sm_state <= #1 CPU_SM_WAIT;
        end else begin
          cpu_sm_adr_i <= #1 {cpu_adr_idx, cpu_adr_blk};
          cpu_sm_adr_d <= #1 {cpu_adr_idx, cpu_adr_blk};
          cpu_sm_state <= #1 CPU_SM_IDLE;
        end
      end
      CPU_SM_FILL1 : begin
        cpu_sm_id <= #1 cpu_ir;
        cpu_sm_ilru <= #1 itag_lru;
        cpu_sm_dlru <= #1 dtag_lru;
        cpu_sm_bs <= #1 cpu_adr_blk[0] ? 4'b1100 : 4'b0011;
        // update tag ram
        if (level1_i) begin
          cacheline_way_i <= #1 !itag_lru;
          if (itag_lru) begin
            cpu_sm_tag_dat_w <= #1 {1'b0, 1'b1, itram_cpu_dat_r[29], 1'b0, itram_cpu_dat_r[27:14], cpu_adr_tag_l}; // Removed zero bit
          end else begin
            cpu_sm_tag_dat_w <= #1 {1'b1, itram_cpu_dat_r[30], 1'b1, 1'b0, cpu_adr_tag_l, itram_cpu_dat_r[13: 0]}; // Removed zero bit
          end
        end
        if (level1_d && data_cache) begin
          cacheline_way_d <= #1 !dtag_lru;
          if (dtag_lru) begin
            cpu_sm_tag_dat_w <= #1 {1'b0, 1'b1, dtram_cpu_dat_r[29], 1'b0, dtram_cpu_dat_r[27:14], cpu_adr_tag_l}; // Removed zero bit
          end else begin
            cpu_sm_tag_dat_w <= #1 {1'b1, dtram_cpu_dat_r[30], 1'b1, 1'b0, cpu_adr_tag_l, dtram_cpu_dat_r[13: 0]}; // Removed zero bit
          end
        end
        if (!sdr_read_ack) begin
          sdr_read_req <= #1 1'b1;
        end else begin
          sdr_read_req <= #1 1'b0;
          // read data to cpu
          cpu_cache_ack <= #1 !cpu_pair;
          cpu_dat_r <= #1 sdr_dat_r;
          cpu_dat_r_hi <= #1 sdr_dat_r;
          read_pair_pending <= #1 cpu_pair;
          if (cache_inhibit || (!data_cache && level1_d)) begin
            // don't update cache if caching is inhibited
            if (level1_i) cacheline_valid_i <= #1 1'b0;
            if (level1_d) cacheline_valid_d <= #1 1'b0;
            cpu_sm_state <= #1 CPU_SM_FILLW;
          end else begin
            cpu_sm_itag_we <= #1  cpu_ir;
            cpu_sm_dtag_we <= #1 !cpu_ir;
            // cache line fill 1st word
            cpu_sm_mem_dat_w <= #1 { sdr_dat_r, sdr_dat_r };
            cpu_sm_iram0_we <= #1  itag_lru &&  cpu_ir;
            cpu_sm_iram1_we <= #1 !itag_lru &&  cpu_ir;
            cpu_sm_dram0_we <= #1  dtag_lru && !cpu_ir;
            cpu_sm_dram1_we <= #1 !dtag_lru && !cpu_ir;
            cpu_sm_state <= #1 CPU_SM_FILL2;
          end
        end
      end
      CPU_SM_FILL2 : begin
        cpu_sm_mem_dat_w <= #1 { sdr_dat_r, sdr_dat_r };
        if (sdr_read_ack) begin
          if (read_pair_pending) begin
            cpu_dat_r <= #1 sdr_dat_r;
            cpu_cache_ack <= #1 1'b1;
            read_pair_pending <= #1 1'b0;
          end
          if (!cpu_cs) cpu_acked <= #1 1'b1;
          // cache line fill 2nd...8th word
          if (level1_i) cpu_sm_adr_i[2:0] <= #1 cpu_sm_adr_next_i[2:0];
          if (level1_d) cpu_sm_adr_d[2:0] <= #1 cpu_sm_adr_next_d[2:0];
          cpu_sm_bs <= #1 ~cpu_sm_bs;
          cpu_sm_iram0_we <= #1  cpu_sm_ilru &&  cpu_sm_id;
          cpu_sm_iram1_we <= #1 !cpu_sm_ilru &&  cpu_sm_id;
          cpu_sm_dram0_we <= #1  cpu_sm_dlru && !cpu_sm_id;
          cpu_sm_dram1_we <= #1 !cpu_sm_dlru && !cpu_sm_id;
        end else if (!cpu_cs | cpu_acked) begin
          if (cpu_restore) begin
            cpu_sm_adr_i <= #1 cacheline_sm_adr_i;
            cpu_sm_adr_d <= #1 cacheline_sm_adr_d;
          end else begin
            cpu_sm_adr_i <= #1 {cpu_adr_idx, cpu_adr_blk};
            cpu_sm_adr_d <= #1 {cpu_adr_idx, cpu_adr_blk};
          end
          cpu_sm_state <= #1 CPU_SM_IDLE;
          cpu_adr_blk_ptr <= #1 cpu_adr_blk; // if CS already activated during fill
        end
      end
      CPU_SM_FILLW : begin
        // Even inhibited reads must collect both beats before accepting a pair.
        cacheline_ready_i <= cacheline_valid_i;
        cacheline_ready_d <= cacheline_valid_d;
        if (read_pair_pending && sdr_read_ack) begin
          cpu_dat_r <= #1 sdr_dat_r;
          cpu_cache_ack <= #1 1'b1;
          read_pair_pending <= #1 1'b0;
        end
        if (cpu_cs) begin
          cpu_sm_state <= #1 CPU_SM_FILLW;
        end else begin
          cpu_sm_adr_i <= #1 {cpu_adr_idx, cpu_adr_blk};
          cpu_sm_adr_d <= #1 {cpu_adr_idx, cpu_adr_blk};
          cpu_sm_state <= #1 CPU_SM_IDLE;
        end
      end
      default: cpu_sm_state <= #1 CPU_SM_INIT;
    endcase

    if (cacheline_clr) begin
      cacheline_valid_i <= #1 1'b0;
      cacheline_valid_d <= #1 1'b0;
      cacheline_ready_i <= #1 1'b0;
      cacheline_ready_d <= #1 1'b0;
    end

    // when CPU lowers its request signal, lower ack too
    if (!cpu_cs) cpu_cache_ack <= #1 1'b0;
  end
end


//// sdram side ////

// sdram side state machine
always @ (posedge clk, negedge rstn) begin
  if (!rstn) begin
    cache_init_done   <= #1 1'b0;
    sdr_sm_state      <= #1 SDR_SM_INIT0;
    sdr_sm_itag_we    <= #1 1'b0;
    sdr_sm_dtag_we    <= #1 1'b0;
    sdr_sm_iram0_we   <= #1 1'b0;
    sdr_sm_iram1_we   <= #1 1'b0;
    sdr_sm_dram0_we   <= #1 1'b0;
    sdr_sm_dram1_we   <= #1 1'b0;

  end else begin
    // default values
    sdr_sm_itag_we    <= #1 1'b0;
    sdr_sm_dtag_we    <= #1 1'b0;
    sdr_sm_iram0_we   <= #1 1'b0;
    sdr_sm_iram1_we   <= #1 1'b0;
    sdr_sm_dram0_we   <= #1 1'b0;
    sdr_sm_dram1_we   <= #1 1'b0;
    cache_init_done   <= #1 1'b0;

    // state machine
    case (sdr_sm_state)
      SDR_SM_INIT0 : begin
        // prepare to clear cache
        sdr_sm_adr <= #1 10'd0;
        sdr_sm_tag_dat_w <= #1 32'd0;
        sdr_sm_itag_we <= #1 1'b1;
        sdr_sm_dtag_we <= #1 1'b1;
        sdr_sm_state <= #1 SDR_SM_INIT1;
      end
      SDR_SM_INIT1 : begin
        // clear cache
        sdr_sm_adr <= #1 sdr_sm_adr + 10'd4;
        sdr_sm_itag_we <= #1 1'b1;
        sdr_sm_dtag_we <= #1 1'b1;
        if (&sdr_sm_adr[9:2]) begin
          cache_init_done <= #1 1'b1;
          sdr_sm_state <= #1 SDR_SM_IDLE;
        end else begin
          sdr_sm_state <= #1 SDR_SM_INIT1;
        end
      end
      SDR_SM_IDLE : begin
        // wait for action
        sdr_sm_adr <= #1 snoop_adr[11:2];
        if (cache_clear_start) begin
          sdr_sm_state <= #1 SDR_SM_INIT0;
        end
        else if (snoop_act) begin
          // chip write happening
          sdr_sm_state <= #1 SDR_SM_SNOOP;
        end
      end
      SDR_SM_SNOOP : begin
        // update if a matching address is in cache
        if (snoop_adr[1]) begin
          sdr_sm_mem_dat_w <= #1 { snoop_dat_w[15:0], snoop_dat_w[15:0] };
          sdr_sm_bs <= #1 { snoop_bs[1:0], 2'b00 };
        end else begin
          sdr_sm_mem_dat_w <= #1 snoop_dat_w;
          sdr_sm_bs <= #1 snoop_bs;
        end
        sdr_sm_iram0_we <= #1 sdr_itag0_match && sdr_itag0_valid;
        sdr_sm_iram1_we <= #1 sdr_itag1_match && sdr_itag1_valid;
        sdr_sm_dram0_we <= #1 sdr_dtag0_match && sdr_dtag0_valid;
        sdr_sm_dram1_we <= #1 sdr_dtag1_match && sdr_dtag1_valid;
        sdr_sm_state <= #1 SDR_SM_IDLE;
      end
      default: sdr_sm_state <= SDR_SM_INIT0;
    endcase
  end
end


//// instruction memories ////

localparam TAG_LENGTH = addr_max_bits - 12;

// instruction tag ram
assign itram_cpu_adr    = cpu_adr_idx;
assign itram_cpu_we     = cpu_sm_itag_we;
assign itram_cpu_dat_w  = cpu_sm_tag_dat_w;
assign itag0_match      = (cpu_adr_tag_l[0 +: TAG_LENGTH] == itram_cpu_dat_r[0 +: TAG_LENGTH]);
assign itag1_match      = (cpu_adr_tag_l[0 +: TAG_LENGTH] == itram_cpu_dat_r[14 +: TAG_LENGTH]);
assign itag_hit         = itag0_match || itag1_match;
assign itag_lru         = itram_cpu_dat_r[31];
assign itag0_valid      = itram_cpu_dat_r[30];
assign itag1_valid      = itram_cpu_dat_r[29];

assign itram_sdr_adr    = sdr_sm_adr[9:2];
assign itram_sdr_we     = sdr_sm_itag_we;
assign itram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_itag0_match  = (snoop_adr[12 +: TAG_LENGTH] == itram_sdr_dat_r[0 +: TAG_LENGTH]);
assign sdr_itag1_match  = (snoop_adr[12 +: TAG_LENGTH] == itram_sdr_dat_r[14 +: TAG_LENGTH]);
assign sdr_itag_hit     = sdr_itag0_match || sdr_itag1_match;
assign sdr_itag_lru     = itram_sdr_dat_r[31];
assign sdr_itag0_valid  = itram_sdr_dat_r[30];
assign sdr_itag1_valid  = itram_sdr_dat_r[29];

`ifdef SOC_SIM
dpram_inf_256x32
`else
dpram_256x32
`endif
itram (
  .clock      (clk              ),
  .address_a  (itram_cpu_adr    ),
  .wren_a     (itram_cpu_we     ),
  .data_a     (itram_cpu_dat_w  ),
  .q_a        (itram_cpu_dat_r  ),
  .address_b  (itram_sdr_adr    ),
  .wren_b     (itram_sdr_we     ),
  .data_b     (itram_sdr_dat_w  ),
  .q_b        (itram_sdr_dat_r  )
);

// instruction data ram 0
assign idram0_cpu_adr   = cpu_sm_adr_i[10:1];
assign idram0_cpu_bs    = cpu_sm_bs;
assign idram0_cpu_we    = cpu_sm_iram0_we;
assign idram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram0_sdr_adr   = sdr_sm_adr;
assign idram0_sdr_bs    = sdr_sm_bs;
assign idram0_sdr_we    = sdr_sm_iram0_we;
assign idram0_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
idram0 (
  .clock      (clk              ),
  .address_a  (idram0_cpu_adr   ),
  .byteena_a  (idram0_cpu_bs    ),
  .wren_a     (idram0_cpu_we    ),
  .data_a     (idram0_cpu_dat_w ),
  .q_a        (idram0_cpu_dat_r ),
  .address_b  (idram0_sdr_adr   ),
  .byteena_b  (idram0_sdr_bs    ),
  .wren_b     (idram0_sdr_we    ),
  .data_b     (idram0_sdr_dat_w ),
  .q_b        (idram0_sdr_dat_r )
);

// instruction data ram 1
assign idram1_cpu_adr   = cpu_sm_adr_i[10:1];
assign idram1_cpu_bs    = cpu_sm_bs;
assign idram1_cpu_we    = cpu_sm_iram1_we;
assign idram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram1_sdr_adr   = sdr_sm_adr;
assign idram1_sdr_bs    = sdr_sm_bs;
assign idram1_sdr_we    = sdr_sm_iram1_we;
assign idram1_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
idram1 (
  .clock      (clk              ),
  .address_a  (idram1_cpu_adr   ),
  .byteena_a  (idram1_cpu_bs    ),
  .wren_a     (idram1_cpu_we    ),
  .data_a     (idram1_cpu_dat_w ),
  .q_a        (idram1_cpu_dat_r ),
  .address_b  (idram1_sdr_adr   ),
  .byteena_b  (idram1_sdr_bs    ),
  .wren_b     (idram1_sdr_we    ),
  .data_b     (idram1_sdr_dat_w ),
  .q_b        (idram1_sdr_dat_r )
);

//// data data memories ////

// data tag ram
assign dtram_cpu_adr    = cpu_adr_idx;
assign dtram_cpu_we     = cpu_sm_dtag_we;
assign dtram_cpu_dat_w  = cpu_sm_tag_dat_w;
assign dtag0_match      = (cpu_adr_tag_l[0 +: TAG_LENGTH] == dtram_cpu_dat_r[0 +: TAG_LENGTH]);
assign dtag1_match      = (cpu_adr_tag_l[0 +: TAG_LENGTH] == dtram_cpu_dat_r[14 +: TAG_LENGTH]);
assign dtag_hit         = dtag0_match || dtag1_match;
assign dtag_lru         = dtram_cpu_dat_r[31];
assign dtag0_valid      = dtram_cpu_dat_r[30];
assign dtag1_valid      = dtram_cpu_dat_r[29];

assign dtram_sdr_adr    = sdr_sm_adr[9:2];
assign dtram_sdr_we     = sdr_sm_dtag_we;
assign dtram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_dtag0_match  = (snoop_adr[12 +: TAG_LENGTH] == dtram_sdr_dat_r[0 +: TAG_LENGTH]);
assign sdr_dtag1_match  = (snoop_adr[12 +: TAG_LENGTH] == dtram_sdr_dat_r[14 +: TAG_LENGTH]);
assign sdr_dtag_hit     = sdr_dtag0_match || sdr_dtag1_match;
assign sdr_dtag_lru     = dtram_sdr_dat_r[31];
assign sdr_dtag0_valid  = dtram_sdr_dat_r[30];
assign sdr_dtag1_valid  = dtram_sdr_dat_r[29];

`ifdef SOC_SIM
dpram_inf_256x32
`else
dpram_256x32
`endif
dtram (
  .clock      (clk              ),
  .address_a  (dtram_cpu_adr    ),
  .wren_a     (dtram_cpu_we     ),
  .data_a     (dtram_cpu_dat_w  ),
  .q_a        (dtram_cpu_dat_r  ),
  .address_b  (dtram_sdr_adr    ),
  .wren_b     (dtram_sdr_we     ),
  .data_b     (dtram_sdr_dat_w  ),
  .q_b        (dtram_sdr_dat_r  )
);

// data data ram 0
assign ddram0_cpu_adr   = cpu_sm_adr_d[10:1];
assign ddram0_cpu_bs    = cpu_sm_bs;
assign ddram0_cpu_we    = cpu_sm_dram0_we;
assign ddram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram0_sdr_adr   = sdr_sm_adr;
assign ddram0_sdr_bs    = sdr_sm_bs;
assign ddram0_sdr_we    = sdr_sm_dram0_we;
assign ddram0_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
ddram0 (
  .clock      (clk              ),
  .address_a  (ddram0_cpu_adr   ),
  .byteena_a  (ddram0_cpu_bs    ),
  .wren_a     (ddram0_cpu_we    ),
  .data_a     (ddram0_cpu_dat_w ),
  .q_a        (ddram0_cpu_dat_r ),
  .address_b  (ddram0_sdr_adr   ),
  .byteena_b  (ddram0_sdr_bs    ),
  .wren_b     (ddram0_sdr_we    ),
  .data_b     (ddram0_sdr_dat_w ),
  .q_b        (ddram0_sdr_dat_r )
);

// data data ram 1
assign ddram1_cpu_adr   = cpu_sm_adr_d[10:1];
assign ddram1_cpu_bs    = cpu_sm_bs;
assign ddram1_cpu_we    = cpu_sm_dram1_we;
assign ddram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram1_sdr_adr   = sdr_sm_adr;
assign ddram1_sdr_bs    = sdr_sm_bs;
assign ddram1_sdr_we    = sdr_sm_dram1_we;
assign ddram1_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
ddram1 (
  .clock      (clk              ),
  .address_a  (ddram1_cpu_adr   ),
  .byteena_a  (ddram1_cpu_bs    ),
  .wren_a     (ddram1_cpu_we    ),
  .data_a     (ddram1_cpu_dat_w ),
  .q_a        (ddram1_cpu_dat_r ),
  .address_b  (ddram1_sdr_adr   ),
  .byteena_b  (ddram1_sdr_bs    ),
  .wren_b     (ddram1_sdr_we    ),
  .data_b     (ddram1_sdr_dat_w ),
  .q_b        (ddram1_sdr_dat_r )
);


endmodule

