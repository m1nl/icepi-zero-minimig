// HDMI-timed RTG scanout. Register/fetch interfaces retain the Minimig P96 layout.
// Two FIFOs allow a prepared second framebuffer to start on an exact HDMI row.

`default_nettype none
`timescale 1 ns / 1 ps
module rtg_video #(
  // clk_sys cycles available to the vblank handler
  parameter PREPARE_DELAY = 4096,
  // These describe the active HDMI raster, not the requested P96 bitmap.
  // For another raster, also update HDMI's timing/request decode, the board
  // PLL and clock constraints, and the driver's ModeRepeat/timing tables.
  // Changing these parameters alone does not change the HDMI output mode.
  parameter H_ACTIVE = 1024,
  parameter V_ACTIVE = 768
) (
  input wire clk_sys,
  input wire resetn_sys,
  input wire clk_rtg,
  input wire resetn_rtg,

  input wire rtg_active,
  output reg rtg_enable,

  input wire video_reset,
  input wire frame_start_toggle,
  input wire vblank_start_toggle,

  // Timed one-bit requests from HDMI; its lead compensates for this
  // pipeline and the edge used by the top-level RGB output register.
  // Frame request must arrive one cycle before the first pixel request.
  input wire pixel_request,
  input wire frame_request,
  input wire line_prepare,

  input wire [10:0] reg_addr,
  input wire [15:0] reg_d,
  input wire        reg_req,
  input wire        reg_wr,
  output reg [15:0] reg_q = 16'hffff,
  output reg        reg_ack,

  output wire [25:0] fetch_addr,
  output wire        fetch_req,
  output wire        fetch_pri,
  output wire        fetch_extend,
  input  wire [15:0] fetch_d,
  input  wire        fetch_ack,
  input  wire        fetch_fill,

  output reg [7:0] red,
  output reg [7:0] green,
  output reg [7:0] blue,

  output wire irq
);

// Display-active/reset and vblank cross from the selected pixel-clock domain.
(* ASYNC_REG = "TRUE" *) reg [1:0] ena_sys_sync;
(* ASYNC_REG = "TRUE" *) reg [1:0] vreset_sys_sync;
(* ASYNC_REG = "TRUE" *) reg [1:0] vblank_sys_sync;
(* ASYNC_REG = "TRUE" *) reg [1:0] frame_start_sys_sync;

wire ena_sys    = ena_sys_sync[1];
wire vreset_sys = vreset_sys_sync[1];

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    ena_sys_sync <= 0;
    vreset_sys_sync <= 0;
  end else begin
    ena_sys_sync <= {ena_sys_sync[0], rtg_active};
    vreset_sys_sync <= {vreset_sys_sync[0], video_reset};
  end
end

reg vblank_sys_seen;
reg frame_start_sys_seen;

wire vblank = (vblank_sys_seen != vblank_sys_sync[1]);
wire frame_start = (frame_start_sys_seen != frame_start_sys_sync[1]);

always @(posedge clk_sys) begin
  if (vreset_sys) begin
    vblank_sys_sync <= 0;
    vblank_sys_seen <= 0;

    frame_start_sys_sync <= 0;
    frame_start_sys_seen <= 0;

  end else begin
    vblank_sys_sync <= {vblank_sys_sync[0], vblank_start_toggle};
    if (vblank_sys_sync[1] != vblank_sys_seen) vblank_sys_seen <= vblank_sys_sync[1];

    frame_start_sys_sync <= {frame_start_sys_sync[0], frame_start_toggle};
    if (frame_start_sys_sync[1] != frame_start_sys_seen)
      frame_start_sys_seen <= frame_start_sys_sync[1];
  end
end

reg in_vblank;

always @(posedge clk_sys) begin
  if (vreset_sys)       in_vblank <= 0;
  else if (vblank)      in_vblank <= 1;
  else if (frame_start) in_vblank <= 0;
end

// TG68K qualifies reg_req for the RTG control/palette windows, including
// legacy page mirrors. Addresses outside those windows must not assert it.
wire reg_access = reg_req && !reg_served;
wire reg_write  = reg_access && reg_wr;

reg reg_served;

// $B8010c: read bit0 blank, bit1 IRQ pending, bit2 IRQ enabled,
// bit3 scan clock active. Write bit0 enable, bit1 acknowledge (W1C).
// $B8010e retains the legacy ID; control registers continue at $B80110.
wire irq_write = reg_write && reg_addr == 11'h10c;

// $B80110: bit0 requests RTG instead of native video (read/write).
// $B80112: first row of the secondary framebuffer; $7ff disables splitting.
// $B80114: [1:0] horizontal, [3:2] vertical repetition (0=1x, 1=2x, 2=3x).
// $B80116: source stride in 16-byte bursts; zero selects the visible row size.
// Settings remain accessible while the RTG pixel clock is inactive.
reg [10:0] split_line;
reg  [3:0] prescale;
reg [11:0] stride;

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    rtg_enable <= 0;
    split_line <= 11'h7ff;
    prescale   <= 4'b0;
    stride     <= 0;

  end else if (reg_write) begin
    case (reg_addr)
      11'h110: rtg_enable <= reg_d[0];
      11'h112: split_line <= reg_d[10:0];
      11'h114: prescale   <= reg_d[3:0];
      11'h116: stride     <= reg_d[11:0];
      default: ;
    endcase
  end
end

reg irq_enabled;
reg irq_pending;

// P96 may wait for its first interrupt before requesting RTG display.
// Keep frame interrupts independent of the display switch and FIFO DMA.
assign irq = irq_enabled && irq_pending;

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    reg_ack <= 0;
    reg_served <= 0;
    reg_q <= 16'hffff;

  end else begin
    // Like rtl/soc/akiko.v, completion is a registered one-clock pulse.
    // TG68K uses ACK directly as a CPU clock enable; holding it high
    // would advance the following CPU cycle before its data is ready.
    reg_ack <= 0;

    if (!reg_req) reg_served <= 0;

    if (reg_access) begin
      reg_ack <= 1;
      reg_served <= 1;  // Do not replay a held request or its writes.
    end

    // We can set req_q regardless if we're writing or reading as
    // reading register does not clear any flag here
    case (reg_addr)
      11'h10c: reg_q <= {12'd0, ena_sys, irq_enabled, irq_pending, in_vblank};
      11'h110: reg_q <= {15'd0, rtg_enable};
      11'h112: reg_q <= {5'd0, split_line};
      11'h114: reg_q <= {12'd0, prescale};
      11'h116: reg_q <= {4'd0, stride};
      default: reg_q <= 16'h8321;
    endcase
  end
end

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    irq_enabled <= 0;
    irq_pending <= 0;

  end else begin
    if (irq_write)
      irq_enabled <= reg_d[0];

    if (!irq_enabled || (irq_write && (!reg_d[0] || reg_d[1])))
      irq_pending <= 0;

    // A new frame wins over an acknowledgement of the preceding one.
    if (!vreset_sys && vblank && irq_enabled)
      irq_pending <= 1;
  end
end

reg [25:4] rtg_base, rtg_base2;
reg [9:0] base_high, base2_high;

reg rtg_clut, rtg_16bit;

reg [15:0] clut_high;
reg [23:0] clut[0:255] /* synthesis syn_ramstyle="block_ram" */;

// RTG register write

always @(posedge clk_sys) begin
  if (reg_write && reg_addr[10] && reg_addr[1])
    clut[reg_addr[9:2]] <= {clut_high[7:0], reg_d};
end

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    rtg_base   <= 0;
    rtg_base2  <= 0;
    base_high  <= 0;
    base2_high <= 0;
    rtg_clut   <= 0;
    rtg_16bit  <= 1;
    clut_high  <= 0;

  end else if (reg_write) begin
    if (reg_addr[10]) begin
      if (!reg_addr[1]) clut_high <= reg_d;
    end else
      case (reg_addr[4:1])
        // 68K move.l writes high then low: commit the address as a pair.
        4'h0: base_high <= reg_d[9:0];
        4'h1: rtg_base <= {base_high, reg_d[15:4]};
        4'h2: rtg_clut <= reg_d[15];  // Legacy timing bits intentionally ignored.
        4'h3: rtg_16bit <= reg_d[0];
        4'h4: base2_high <= reg_d[9:0];
        4'h5: rtg_base2 <= {base2_high, reg_d[15:4]};
        default: ;
      endcase
  end
end

reg [9:0] frame_split;
reg [3:0] pixel_repeat;

// Match the driver's 3x source width, rounded down to 32 pixels. Rounding
// only to 16 would select 336 at 1024, exceeding the driver's 320-pixel row.
// 3x uses 320 pixels at 1024-wide output,
// leaving 32 black output pixels at each side; no partial bursts are fetched.
// With H_ACTIVE=1280 this becomes 416 source pixels and 16-pixel side borders.
// The driver must advertise this exact width, alongside 1280 and 640.
localparam H_TRIPLE = (H_ACTIVE / 96) * 32;
localparam H_BORDER = (H_ACTIVE - H_TRIPLE * 3) / 2;

function [10:0] source_width;
  input [1:0] scale;
  begin
    case (scale)
      2'd1: source_width = H_ACTIVE / 2;
      2'd2: source_width = H_TRIPLE;
      default: source_width = H_ACTIVE;
    endcase
  end
endfunction

wire [10:0] initial_width = source_width(prescale[1:0]);
wire  [7:0] initial_row_bursts = rtg_clut ? initial_width >> 4 : initial_width >> 3;
wire [11:0] initial_stride = stride != 0 ? stride : {4'd0, initial_row_bursts};

reg  [7:0] row_bursts;
reg [25:4] row_base_top;
reg [25:4] row_base_bottom;
reg  [7:0] row_left_top;
reg  [7:0] row_left_bottom;

reg  [1:0] repeat_top;
reg  [1:0] repeat_bottom;

reg [11:0] frame_stride;

// Bound the amount of prefetched data by output time rather than source size.
// 3x rounds the 256-word prefill up to eleven complete eight-word bursts.
wire [5:0] prefill_limit = prescale[1:0] == 1 ? 6'd16 :
                           prescale[1:0] == 2 ? 6'd11 : 6'd32;
reg [9:0] fetch_limit;
reg [8:0] priority_limit;

reg frame_indexed;
reg frame_565;

// Raw addresses are stored in 16-byte (eight-word burst) units. Advance
// them on ACK so the SDRAM address path needs no base+offset adder.
reg [25:4] addr_top, addr_bottom;

// Count output rows; each vertical repetition completes another DMA row.
localparam ROW_COUNT_BITS = $clog2(V_ACTIVE + 1);

reg [ROW_COUNT_BITS-1:0] rows_remaining_top;
reg [ROW_COUNT_BITS-1:0] rows_remaining_bottom;

reg has_bottom;

reg [5:0] prefill_left;
reg [8:0] top_prefill_words;
reg [8:0] bottom_prefill_words;

wire split_valid = split_line != 11'h7ff && split_line > 0 && split_line < V_ACTIVE;

reg frame_ready;
reg fifo_reset = 1;
reg owner;

// State machine

localparam OFF            = 0;
localparam DRAIN          = 1;
localparam RESET_FIFO     = 2;
localparam RELEASE_FIFO   = 3;
localparam PREFILL_BOTTOM = 4;
localparam DRAIN_BOTTOM   = 5;
localparam RUN_TOP        = 6;
localparam DRAIN_TOP      = 7;
localparam RUN_BOTTOM     = 8;

reg [3:0] state;
reg [5:0] quiet;
reg [2:0] reset_count;

localparam PREPARE_COUNT_BITS = PREPARE_DELAY > 0 ? $clog2(PREPARE_DELAY + 1) : 1;

reg [PREPARE_COUNT_BITS-1:0] prepare_count;

wire [9:0] used_top, used_bottom;

wire empty_top, empty_bottom;
wire reset_top_r, reset_bottom_r;

wire [15:0] data_top, data_bottom;

// Compare each bank before selecting it: the request/priority path contains
// only zero/constant tests and muxes, not a limit-minus-issued carry chain.
wire top_has_work    = rows_remaining_top != 0;
wire bottom_has_work = rows_remaining_bottom != 0;

// Sections contain complete rows, so row_left > 4 also means
// more than four bursts remain in the section.
wire top_priority    = row_left_top > 4;
wire bottom_priority = row_left_bottom > 4;

wire selected_has_work = state == PREFILL_BOTTOM ? prefill_left != 0 : (owner ? bottom_has_work : top_has_work);
wire selected_extend = state == PREFILL_BOTTOM ? prefill_left > 4 && row_left_bottom > 4 :
                         (owner ? bottom_priority : top_priority);

wire fetching = state == PREFILL_BOTTOM || state == RUN_TOP || state == RUN_BOTTOM;

// Register occupancy comparisons before selecting the FIFO bank. This breaks
// the Gray-decode/subtraction/comparison path into SDRAM arbitration.
// Update continuously; live request gating below handles reset and disable.
// Existing FIFO headroom accommodates the extra decision cycle.
reg top_room, bottom_room;
reg top_hungry, bottom_hungry;

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    top_room <= 0;
    bottom_room <= 0;
    top_hungry <= 0;
    bottom_hungry <= 0;

  end else begin
    top_room <= used_top < fetch_limit;
    bottom_room <= used_bottom < fetch_limit;
    top_hungry <= used_top < priority_limit;
    bottom_hungry <= used_bottom < priority_limit;
  end
end

wire selected_room = owner ? bottom_room : top_room;
wire selected_hungry = owner ? bottom_hungry : top_hungry;

assign fetch_req = ena_sys && !vreset_sys && fetching &&
                   !fifo_reset && selected_has_work && selected_room;

// FIFO urgency reserves SDRAM service even near a row/section boundary.
assign fetch_pri = fetch_req && selected_hungry;

// Independently stop read extension before the final bursts. The next row
// may rewind for vertical repetition or skip stride padding; section changes
// also need outstanding data drained before switching the FIFO owner.
assign fetch_extend = fetch_req && selected_extend;

wire [25:0] fetch_raw = {owner ? addr_bottom : addr_top, 4'd0};

// Both banks update only on an ACK for the current owner. Share these
// adders; their carry chains terminate at RTG registers, not the arbiter.
wire [21:0] linear_addr = (owner ? addr_bottom : addr_top) + 1'b1;

wire [21:0] selected_row_base = owner ? row_base_bottom : row_base_top;
wire  [7:0] selected_row_left = owner ? row_left_bottom : row_left_top;
wire  [1:0] selected_repeat   = owner ? repeat_bottom   : repeat_top;

wire repeat_row = selected_repeat != pixel_repeat[3:2];

wire [21:0] next_row_base = selected_row_base + frame_stride;
wire [21:0] next_addr     = selected_row_left != 1 ? linear_addr :
  repeat_row ? selected_row_base : next_row_base;

wire [ROW_COUNT_BITS-1:0] next_rows_remaining =
  (owner ? rows_remaining_bottom : rows_remaining_top) - 1'b1;

assign fetch_addr = {fetch_raw[25:24], fetch_raw[23] ^ (fetch_raw[22] | fetch_raw[21]), fetch_raw[22:0]};

wire keep_fill = !fifo_reset && state != OFF && state != DRAIN && ena_sys && !vreset_sys;

always @(posedge clk_sys or negedge resetn_sys) begin
  if (!resetn_sys) begin
    state <= OFF;
    fifo_reset <= 1;
    frame_ready <= 0;
    owner <= 0;
    quiet <= 0;
    reset_count <= 0;
    prepare_count <= 0;
    frame_split <= V_ACTIVE;
    frame_indexed <= 0;
    frame_565 <= 1;
    pixel_repeat <= 0;
    row_bursts <= 0;
    frame_stride <= 0;
    row_base_top <= 0;
    row_base_bottom <= 0;
    row_left_top <= 0;
    row_left_bottom <= 0;
    repeat_top <= 0;
    repeat_bottom <= 0;
    fetch_limit <= 480;
    priority_limit <= 256;
    addr_top <= 0;
    addr_bottom <= 0;
    rows_remaining_top <= 0;
    rows_remaining_bottom <= 0;
    has_bottom <= 0;
    prefill_left <= 0;
    top_prefill_words <= 0;
    bottom_prefill_words <= 0;

  end else begin
    if (!ena_sys || vreset_sys) begin
      state <= OFF;
      fifo_reset <= 1;
      frame_ready <= 0;
      quiet <= 0;
      prepare_count <= 0;

    end else if (vblank) begin
      state <= DRAIN;
      frame_ready <= 0;
      quiet <= 0;
      prepare_count <= 0;

    end else begin
      if (state == DRAIN && prepare_count < PREPARE_DELAY)
        prepare_count <= prepare_count + 1'b1;

      if (fetch_ack && !fifo_reset) begin
        // ACK accepts one eight-word burst; data returns later.
        // Saturation prevents late ACKs from wrapping a finished
        // section into a new request. Ownership changes after drain.
        if (owner) begin  // bottom
          addr_bottom <= next_addr;

          if (row_left_bottom == 1) begin
            if (rows_remaining_bottom != 0)
              rows_remaining_bottom <= next_rows_remaining;
            row_left_bottom <= row_bursts;
            if (repeat_row) begin
              repeat_bottom <= repeat_bottom + 1'b1;
            end else begin
              repeat_bottom <= 0;
              row_base_bottom <= next_row_base;
            end
          end else begin
            row_left_bottom <= row_left_bottom - 1'b1;
          end
          if (prefill_left != 0) prefill_left <= prefill_left - 1'b1;

        end else begin  // top
          addr_top <= next_addr;

          if (row_left_top == 1) begin
            if (rows_remaining_top != 0)
              rows_remaining_top <= next_rows_remaining;
            row_left_top <= row_bursts;
            if (repeat_row) begin
              repeat_top <= repeat_top + 1'b1;
            end else begin
              repeat_top <= 0;
              row_base_top <= next_row_base;
            end
          end else begin
            row_left_top <= row_left_top - 1'b1;
          end
        end
      end

      if (fetch_ack || fetch_fill) quiet <= 0;
      else if (quiet != 32) quiet <= quiet + 1'b1;

      if (!frame_ready && (state == RUN_TOP || state == DRAIN_TOP || state == RUN_BOTTOM) &&
        used_top >= top_prefill_words && (!has_bottom || used_bottom >= bottom_prefill_words))
        frame_ready <= 1;

      case (state)
        OFF: begin
          state <= DRAIN;
          quiet <= 0;
          prepare_count <= 0;
        end
        DRAIN: if (prepare_count >= PREPARE_DELAY && quiet == 32 && !fetch_ack && !fetch_fill) begin
          fifo_reset <= 1;
          reset_count <= 0;
          state <= RESET_FIFO;
        end
        RESET_FIFO: begin
          reset_count <= reset_count + 1'b1;

          if (reset_count == 0) begin
            addr_top <= rtg_base;
            addr_bottom <= rtg_base2;

            frame_indexed <= rtg_clut;
            frame_565 <= rtg_16bit;

            rows_remaining_top <= split_valid ? split_line : V_ACTIVE;
            rows_remaining_bottom <= split_valid ? V_ACTIVE - split_line : 0;

            has_bottom <= split_valid;
            frame_split <= split_valid ? split_line[9:0] : V_ACTIVE;

            // Reserved encoding 3 falls back to 1x independently per axis.
            pixel_repeat[1:0] <= prescale[1:0] == 3 ? 2'd0 : prescale[1:0];
            pixel_repeat[3:2] <= prescale[3:2] == 3 ? 2'd0 : prescale[3:2];

            row_bursts <= initial_row_bursts;
            frame_stride <= initial_stride;
            row_base_top <= rtg_base;
            row_base_bottom <= rtg_base2;
            row_left_top <= initial_row_bursts;
            row_left_bottom <= initial_row_bursts;

            repeat_top <= 0;
            repeat_bottom <= 0;

            // At production widths, even one indexed row contains at least
            // the 32/16/11-burst target. No short-section clamp is required.
            prefill_left <= prefill_limit;
            top_prefill_words <= {prefill_limit, 3'd0};
            bottom_prefill_words <= {prefill_limit, 3'd0};

            case (prescale[1:0])
              2'd1: begin
                fetch_limit <= 240;
                priority_limit <= 128;
              end
              2'd2: begin
                fetch_limit <= 160;
                priority_limit <= 88;
              end
              default: begin
                fetch_limit <= 480;
                priority_limit <= 256;
              end
            endcase
          end

          if (reset_count == 7) begin
            fifo_reset <= 0;
            reset_count <= 0;
            state <= RELEASE_FIFO;
          end
        end
        RELEASE_FIFO: begin
          reset_count <= reset_count + 1'b1;
          if (reset_count == 7) begin
            owner <= has_bottom;
            state <= has_bottom ? PREFILL_BOTTOM : RUN_TOP;
          end
        end
        PREFILL_BOTTOM: if (prefill_left == 0) begin
          state <= DRAIN_BOTTOM;
          quiet <= 0;
        end
        DRAIN_BOTTOM: if (quiet == 32 && !fetch_ack && !fetch_fill) begin
          owner <= 0;
          state <= RUN_TOP;
        end
        RUN_TOP: if (rows_remaining_top == 0) begin
          state <= DRAIN_TOP;
          quiet <= 0;
        end
        DRAIN_TOP: if (quiet == 32 && !fetch_ack && !fetch_fill && has_bottom) begin
          owner <= 1;
          state <= RUN_BOTTOM;
        end
        RUN_BOTTOM: ;
        default: state <= OFF;
      endcase
    end
  end
end

// Here we have the RTG read path clocked with clk_rtg

wire video_reset_request = video_reset || !resetn_rtg;

(* ASYNC_REG = "TRUE" *)
reg [1:0] video_reset_sync = 2'b11;

// Assert immediately, including while clk_rtg is stopped.
// Release locally so FIFO read control starts from a clk_rtg register.
always @(posedge clk_rtg or posedge video_reset_request) begin
  if (video_reset_request)
    video_reset_sync <= 2'b11;
  else
    video_reset_sync <= {video_reset_sync[0], 1'b0};
end

wire video_reset_rtg = video_reset_sync[1];

(* ASYNC_REG = "TRUE" *) reg [1:0] ready_vid;

// Bundled data is held from FIFO reset through the entire frame. Ready crosses later.
reg [13:0] config_meta;
reg [13:0] config_vid;

reg [9:0] scan_row;

reg scan_bottom;
reg byte_phase;

wire [9:0] next_scan_row = scan_row + 1'b1;
reg  [9:0] split_vid;

reg indexed_vid, rgb565_vid;
reg frame_active, frame_fault;

reg [1:0] repeat_vid;
reg [1:0] horizontal_phase;

// This counter advances only during active pixels, then resets in blank.
localparam COLUMN_BITS = H_ACTIVE > 1 ? $clog2(H_ACTIVE) : 1;

reg [COLUMN_BITS-1:0] scan_column;

wire [1:0] repeat_now = repeat_vid;

wire in_source_window = repeat_now != 2 ||
    (scan_column >= H_BORDER && scan_column < H_ACTIVE - H_BORDER);

wire source_request = display_req && in_source_window && horizontal_phase == 0;

// Frame request arrives during blanking, one cycle before the first pixel.
// Latch frame state there so FIFO reads need no first-pixel bypass muxes.
wire start_display = frame_request && ready_vid[1] && !reset_top_r && !reset_bottom_r;

wire display_req = rtg_active && !video_reset_rtg && !reset_top_r && !reset_bottom_r &&
                     pixel_request &&
                     frame_active && !frame_fault;

wire selected_bottom = scan_bottom;

wire indexed_now = indexed_vid;

wire need_word = !indexed_now || !byte_phase;

wire word_empty = selected_bottom ? empty_bottom : empty_top;

wire valid_req = display_req && in_source_window &&
                 (!source_request || !need_word || !word_empty);

// With source_request && need_word, valid_req reduces to !word_empty.
// Check each bank directly to avoid the selected-empty mux on FIFO enables.
wire pop_top = source_request && need_word &&
               !selected_bottom && !empty_top;

wire pop_bottom = source_request && need_word &&
                  selected_bottom && !empty_bottom;

// A reset of either interface clears both FIFO pointers. The FIFO
// synchronizes release independently in its write and read domains.
wire fifo_reset_request = fifo_reset | !resetn_sys | !resetn_rtg;

rtg_async_fifo top_fifo (
    .wr_clk(clk_sys),
    .rd_clk(clk_rtg),
    .reset(fifo_reset_request),
    .wr_en(keep_fill && !owner && fetch_fill),
    .wr_data(fetch_d),
    .rd_en(pop_top),
    .rd_data(data_top),
    .full(),
    .empty(empty_top),
    .wr_used(used_top),
    .wr_reset_busy(),
    .rd_reset_busy(reset_top_r)
);

rtg_async_fifo bottom_fifo (
    .wr_clk(clk_sys),
    .rd_clk(clk_rtg),
    .reset(fifo_reset_request),
    .wr_en(keep_fill && owner && fetch_fill),
    .wr_data(fetch_d),
    .rd_en(pop_bottom),
    .rd_data(data_bottom),
    .full(),
    .empty(empty_bottom),
    .wr_used(used_bottom),
    .wr_reset_busy(),
    .rd_reset_busy(reset_bottom_r)
);

reg valid_1, valid_2, bottom_1, low_byte_1, indexed_1, indexed_2, rgb565_1;
reg source_1, source_2;

reg [23:0] palette_rgb, direct_rgb;

wire [15:0] word_1 = bottom_1 ? data_bottom : data_top;
wire  [7:0] palette_index = low_byte_1 ? word_1[7:0] : word_1[15:8];

// Stage 1: FIFO synchronous read. Stage 2: palette/direct decode. Stage 3: RGB.
always @(posedge clk_rtg) begin
  palette_rgb <= clut[palette_index];
  direct_rgb  <= rgb565_1 ?
          {word_1[15:11], word_1[15:13], word_1[10:5], word_1[10:9], word_1[4:0], word_1[4:2]} :
          {word_1[14:10], word_1[14:12], word_1[ 9:5], word_1[ 9:7], word_1[4:0], word_1[4:2]};
end

always @(posedge clk_rtg or negedge resetn_rtg) begin
  if (!resetn_rtg) begin
    ready_vid <= 0;
    config_meta <= 0;
    config_vid <= 0;
    frame_active <= 0;
    frame_fault <= 0;
    scan_row <= 0;
    scan_bottom <= 0;
    byte_phase <= 0;
    split_vid <= V_ACTIVE;
    indexed_vid <= 0;
    rgb565_vid <= 1;
    repeat_vid <= 0;
    horizontal_phase <= 0;
    scan_column <= 0;
    source_1 <= 0;
    source_2 <= 0;
    valid_1 <= 0;
    valid_2 <= 0;

    bottom_1 <= 0;
    low_byte_1 <= 0;
    indexed_1 <= 0;
    indexed_2 <= 0;
    rgb565_1 <= 1;
    red <= 0;
    green <= 0;
    blue <= 0;

  end else begin
    ready_vid   <= {ready_vid[0], frame_ready};
    config_meta <= {pixel_repeat[1:0], frame_split, frame_indexed, frame_565};
    config_vid  <= config_meta;

    if (!rtg_active || video_reset_rtg || reset_top_r || reset_bottom_r) begin
      frame_active <= 0;
      frame_fault <= 0;
      scan_row <= 0;
      scan_bottom <= 0;
      byte_phase <= 0;
      horizontal_phase <= 0;
      scan_column <= 0;
      source_1 <= 0;
      source_2 <= 0;
      valid_1 <= 0;
      valid_2 <= 0;

      {red, green, blue} <= 24'd0;

    end else begin
      // Row/split decisions settle during horizontal blank, before
      // any pixel of the next line is requested.
      if (line_prepare) begin
        scan_row <= next_scan_row;
        if (next_scan_row == split_vid) scan_bottom <= 1;
        if (next_scan_row == V_ACTIVE) frame_active <= 0;
      end
      if (frame_request) begin
        scan_row <= 0;
        scan_bottom <= 0;
      end
      if (!pixel_request) begin
        byte_phase <= 0;
        horizontal_phase <= 0;
        scan_column <= 0;

      end else begin
        scan_column <= scan_column + 1'b1;

        if (display_req && in_source_window) begin
          if (horizontal_phase == repeat_now)
            horizontal_phase <= 0;
          else
            horizontal_phase <= horizontal_phase + 1'b1;
        end

        // Track source-pixel parity independently of FIFO availability.
        // Blanking resets parity; underflow blanks the rest of the frame.
        if (in_source_window && horizontal_phase == 0)
          byte_phase <= ~byte_phase;
      end
      if (start_display) begin
        frame_active <= 1;
        frame_fault <= 0;
        split_vid <= config_vid[11:2];
        indexed_vid <= config_vid[1];
        rgb565_vid <= config_vid[0];
        repeat_vid <= config_vid[13:12];
      end
      if (source_request && need_word && word_empty)
        frame_fault <= 1;

      // Frame request starts scanout without resetting prepared FIFOs.
      valid_1 <= valid_req;
      valid_2 <= valid_1;

      source_1 <= source_request && valid_req;
      source_2 <= source_1;

      bottom_1 <= selected_bottom;
      low_byte_1 <= byte_phase;
      indexed_1 <= indexed_now;
      indexed_2 <= indexed_1;
      rgb565_1 <= rgb565_vid;

      // Hold the decoded RGB through repetitions, with unchanged latency.
      if (!valid_2)
        {red, green, blue} <= 24'd0;
      else if (source_2)
        {red, green, blue} <= indexed_2 ? palette_rgb : direct_rgb;
    end
  end
end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
