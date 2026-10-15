// HDMI-timed RTG scanout. Register/fetch interfaces retain the Minimig P96 layout.
// Two FIFOs allow a prepared second framebuffer to start on an exact HDMI row.
module rtg_video #(
    parameter PREPARE_DELAY = 4096, // clk_114 cycles available to the vblank handler
    parameter H_ACTIVE = 1024, parameter V_ACTIVE = 768,
    parameter H_TOTAL = 1344, parameter V_TOTAL = 806
) (
    input clk_114, input clk_rtg, input reset_n,
    input rtg_ena, input video_reset,
    input frame_start, input vblank_start,
    // Lookahead coordinates supplied by HDMI, three clocks before RGB capture.
    input [10:0] pixel_x, input [9:0] pixel_y,
    output reg display_enable,
    input [10:0] reg_addr, input reg_wr, input reg_req, input [15:0] reg_d,
    output reg reg_ack, output reg [15:0] reg_q,
    output [25:0] fetch_addr, output fetch_req, output fetch_pri,
    input [15:0] fetch_d, input fetch_ack, input fetch_fill,
    output reg [7:0] red, output reg [7:0] green, output reg [7:0] blue,
    output pixel, output de, output irq
);
    // Legacy rtl/akiko/akiko.vhd RTG bus decode and read behavior.
    // TG68K qualifies the $B80xxx page; control registers occupy $B801xx,
    // palette writes $B80400-$B807ff, and bit 11 is mirrored as before.
    wire reg_sel = reg_addr[10] || reg_addr[9:8] == 2'b01;
    reg reg_served;
    wire reg_access = reg_req && reg_sel && !reg_served;
    wire write_strobe = reset_n && reg_access && reg_wr;
    // $B8010c: read bit0 blank, bit1 IRQ pending, bit2 IRQ enabled,
    // bit3 scan clock active. Write bit0 enable, bit1 acknowledge (W1C).
    // $B80110: read-only HDMI vblank sequence; $B8010e retains the ID.
    wire irq_write = write_strobe && reg_addr == 11'h10c;
    // $B80112: bit0 requests RTG instead of native video (read/write).
    // $B80114: first row of the secondary framebuffer; $7ff disables splitting.
    // Both registers remain accessible while the RTG pixel clock is inactive.
    reg [10:0] split_line;
    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin display_enable <= 0; split_line <= 11'h7ff; end
        else if (write_strobe) begin
            if (reg_addr == 11'h112) display_enable <= reg_d[0];
            if (reg_addr == 11'h114) split_line <= reg_d[10:0];
        end
    end
    reg irq_enabled, irq_pending;
    reg [15:0] frame_sequence;
    reg blank_vid;
    (* ASYNC_REG = "TRUE" *) reg [1:0] blank_sys;
    wire scan_active = ena_sys[1] && !reset_sys[1];
    wire blank_event = !reset_sys[1] && vblank_sys[1] != vblank_seen;
    // P96 may wait for its first interrupt before requesting RTG display.
    // Keep frame interrupts independent of the display switch and FIFO DMA.
    assign irq = irq_enabled && irq_pending;
    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin reg_ack <= 0; reg_q <= 16'hffff; reg_served <= 0; end
        else begin
            // Like rtl/soc/akiko.v, completion is a registered one-clock pulse.
            // TG68K uses ACK directly as a CPU clock enable; holding it high
            // would advance the following CPU cycle before its data is ready.
            reg_ack <= 0;
            if (!reg_req || !reg_sel) reg_served <= 0;
            if (reg_access) begin
                reg_ack <= 1;
                reg_served <= 1; // Do not replay a held request or its writes.
                if (!reg_wr) begin
                    if (reg_addr == 11'h10c)
                        reg_q <= {12'd0,scan_active,irq_enabled,irq_pending,!reset_sys[1] && blank_sys[1]};
                    else if (reg_addr == 11'h110) reg_q <= frame_sequence;
                    else if (reg_addr == 11'h112) reg_q <= {15'd0,display_enable};
                    else if (reg_addr == 11'h114) reg_q <= {5'd0,split_line};
                    else reg_q <= 16'h8321;
                end
            end
        end
    end

    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin
            irq_enabled <= 0; irq_pending <= 0; frame_sequence <= 0;
        end else begin
            if (irq_write) irq_enabled <= reg_d[0];
            if (!irq_enabled || (irq_write && (!reg_d[0] || reg_d[1])))
                irq_pending <= 0;
            // A new frame wins over an acknowledgement of the preceding one.
            if (blank_event) begin
                frame_sequence <= frame_sequence + 1'b1;
                if (irq_write ? reg_d[0] : irq_enabled) irq_pending <= 1;
            end
        end
    end

    reg [25:4] rtg_base, rtg_base2;
    reg [9:0] base_high, base2_high;
    reg rtg_clut, rtg_16bit;
    reg [15:0] clut_high;
    reg [23:0] clut [0:255] /* synthesis syn_ramstyle="block_ram" */;
    always @(posedge clk_114) begin
        if (write_strobe && reg_addr[10] && reg_addr[1])
            clut[reg_addr[9:2]] <= {clut_high[7:0],reg_d};
    end
    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin
            rtg_base <= 0; rtg_base2 <= 0; base_high <= 0; base2_high <= 0;
            rtg_clut <= 0; rtg_16bit <= 1; clut_high <= 0;
        end else if (write_strobe) begin
            if (reg_addr[10]) begin
                if (!reg_addr[1]) clut_high <= reg_d;
            end else case (reg_addr[4:1])
                // 68K move.l writes high then low: commit the address as a pair.
                0: base_high <= reg_d[9:0];
                1: rtg_base <= {base_high,reg_d[15:4]};
                2: rtg_clut <= reg_d[15]; // Legacy timing bits intentionally ignored.
                3: rtg_16bit <= reg_d[0];
                4: base2_high <= reg_d[9:0];
                5: rtg_base2 <= {base2_high,reg_d[15:4]};
                default: ;
            endcase
        end
    end

    // Display-active/reset and vblank cross from the selected pixel-clock domain.
    (* ASYNC_REG = "TRUE" *) reg [1:0] ena_sys, reset_sys;
    reg vblank_toggle;
    // HDMI events are synchronous to the selected pixel clock, including
    // native mode. Retain the event toggle across HDMI mode-switch resets
    // so resetting HDMI cannot manufacture an interrupt in clk_114.
    always @(posedge clk_rtg or negedge reset_n) begin
        if (!reset_n) begin vblank_toggle <= 0; blank_vid <= 0; end
        else if (video_reset) blank_vid <= 0;
        else begin
            if (frame_start) blank_vid <= 0;
            if (vblank_start) begin blank_vid <= 1; vblank_toggle <= ~vblank_toggle; end
        end
    end
    (* ASYNC_REG = "TRUE" *) reg [1:0] vblank_sys;
    reg vblank_seen;
    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin
            ena_sys <= 0; reset_sys <= 3; vblank_sys <= 0; blank_sys <= 0;
        end else begin
            ena_sys <= {ena_sys[0],rtg_ena}; reset_sys <= {reset_sys[0],video_reset};
            vblank_sys <= {vblank_sys[0],vblank_toggle};
            blank_sys <= {blank_sys[0],blank_vid};
        end
    end
    wire [10:0] split_row = split_line;
    reg [9:0] frame_split;
    reg frame_indexed, frame_565;
    // Raw addresses are stored in 16-byte (eight-word burst) units. Advance
    // them on ACK so the SDRAM address path needs no base+offset adder.
    reg [25:4] addr_current, addr_saved;
    localparam COUNT_BITS = $clog2(H_ACTIVE * V_ACTIVE / 8 + 1);
    reg [COUNT_BITS-1:0] remaining_top, remaining_bottom;
    reg has_bottom;
    reg [5:0] prefill_left;
    reg [8:0] top_prefill_words, bottom_prefill_words;
    wire split_valid = split_row != 11'h7ff && split_row > 0 && split_row < V_ACTIVE;
    wire [COUNT_BITS-1:0] initial_top_bursts = split_valid ?
        (rtg_clut ? (split_row*H_ACTIVE)/16 : (split_row*H_ACTIVE)/8) :
        (rtg_clut ? (V_ACTIVE*H_ACTIVE)/16 : (V_ACTIVE*H_ACTIVE)/8);
    wire [COUNT_BITS-1:0] initial_bottom_bursts = split_valid ?
        (rtg_clut ? ((V_ACTIVE-split_row)*H_ACTIVE)/16 : ((V_ACTIVE-split_row)*H_ACTIVE)/8) : 0;
    // Production rows contain at least 512 words, so prefill is 32 bursts.
    // Retain smaller-section targets for reduced-width simulations.
    wire [5:0] initial_top_prefill = initial_top_bursts < 32 ? initial_top_bursts : 6'd32;
    wire [5:0] initial_bottom_prefill = initial_bottom_bursts < 32 ? initial_bottom_bursts : 6'd32;
    reg frame_ready;
    reg fifo_reset = 1;
    reg owner;
    localparam OFF=0, DRAIN=1, RESET_FIFO=2, RELEASE_FIFO=3,
               PREFILL_BOTTOM=4, DRAIN_BOTTOM=5, RUN_TOP=6, DRAIN_TOP=7, RUN_BOTTOM=8;
    reg [3:0] state;
    reg [5:0] quiet;
    reg [3:0] reset_count;
    reg [15:0] prepare_count;
    wire [9:0] used_top, used_bottom;
    wire full_top, full_bottom, empty_top, empty_bottom;
    wire reset_top_w, reset_top_r, reset_bottom_w, reset_bottom_r;
    wire [15:0] data_top, data_bottom;
    // Compare each bank before selecting it: the request/priority path contains
    // only zero/constant tests and muxes, not a limit-minus-issued carry chain.
    wire top_has_work = remaining_top != 0;
    wire bottom_has_work = remaining_bottom != 0;
    wire top_priority = remaining_top > 4;
    wire bottom_priority = remaining_bottom > 4;
    wire selected_has_work = state == PREFILL_BOTTOM ? prefill_left != 0 :
                             owner ? bottom_has_work : top_has_work;
    wire selected_priority = state == PREFILL_BOTTOM ? prefill_left > 4 :
                             owner ? bottom_priority : top_priority;
    wire [9:0] used = owner ? used_bottom : used_top;
    wire fetching = state == PREFILL_BOTTOM || state == RUN_TOP || state == RUN_BOTTOM;
    assign fetch_req = ena_sys[1] && !reset_sys[1] && fetching && !fifo_reset &&
                       selected_has_work && used < 480;
    // Drop priority before the final bursts so SDRAM does not extend past the section.
    assign fetch_pri = fetch_req && used < 256 && selected_priority;
    wire [25:0] fetch_raw = {addr_current,4'd0};
    // Both banks update only on an ACK for the current owner. Share these
    // adders; their carry chains terminate at RTG registers, not the arbiter.
    wire [21:0] next_addr = addr_current + 1'b1;
    wire [COUNT_BITS-1:0] next_remaining = (owner ? remaining_bottom : remaining_top) - 1'b1;
    assign fetch_addr = {fetch_raw[25:24],fetch_raw[23]^(fetch_raw[22]|fetch_raw[21]),fetch_raw[22:0]};
    wire keep_fill = !fifo_reset && state != OFF && state != DRAIN &&
                     ena_sys[1] && !reset_sys[1];

    always @(posedge clk_114 or negedge reset_n) begin
        if (!reset_n) begin
            state <= OFF; fifo_reset <= 1; frame_ready <= 0; owner <= 0;
            quiet <= 0; reset_count <= 0; vblank_seen <= 0; prepare_count <= 0;
            frame_split <= V_ACTIVE; frame_indexed <= 0; frame_565 <= 1;
            addr_current <= 0; addr_saved <= 0;
            remaining_top <= 0; remaining_bottom <= 0; has_bottom <= 0;
            prefill_left <= 0; top_prefill_words <= 0; bottom_prefill_words <= 0;
        end else begin
            vblank_seen <= vblank_sys[1];
            if (!ena_sys[1] || reset_sys[1]) begin
                state <= OFF; fifo_reset <= 1; frame_ready <= 0; quiet <= 0; prepare_count <= 0;
            end else if (vblank_sys[1] != vblank_seen) begin
                state <= DRAIN; frame_ready <= 0; quiet <= 0; prepare_count <= 0;
            end else begin
                if (state == DRAIN && prepare_count < PREPARE_DELAY)
                    prepare_count <= prepare_count + 1'b1;
                if (fetch_ack && !fifo_reset) begin
                    // ACK accepts one eight-word burst; data returns later.
                    // Saturation prevents late ACKs from wrapping a finished
                    // section into a new request. Ownership changes after drain.
                    addr_current <= next_addr;
                    if (owner) begin
                        if (remaining_bottom != 0) remaining_bottom <= next_remaining;
                        if (prefill_left != 0) prefill_left <= prefill_left - 1'b1;
                    end else begin
                        if (remaining_top != 0) remaining_top <= next_remaining;
                    end
                end
                if (fetch_ack || fetch_fill) quiet <= 0;
                else if (quiet != 32) quiet <= quiet + 1'b1;
                if (!frame_ready && (state == RUN_TOP || state == DRAIN_TOP || state == RUN_BOTTOM) &&
                    used_top >= top_prefill_words && (!has_bottom || used_bottom >= bottom_prefill_words)) frame_ready <= 1;
                case (state)
                    OFF: begin state <= DRAIN; quiet <= 0; prepare_count <= 0; end
                    DRAIN: if (prepare_count >= PREPARE_DELAY && quiet == 32 && !fetch_ack && !fetch_fill) begin
                        fifo_reset <= 1; reset_count <= 0; state <= RESET_FIFO;
                    end
                    RESET_FIFO: begin
                        reset_count <= reset_count + 1'b1;
                        if (reset_count == 0) begin
                            addr_current <= owner ? rtg_base2 : rtg_base;
                            addr_saved <= owner ? rtg_base : rtg_base2;
                            frame_indexed <= rtg_clut; frame_565 <= rtg_16bit;
                            remaining_top <= initial_top_bursts;
                            remaining_bottom <= initial_bottom_bursts;
                            has_bottom <= split_valid;
                            frame_split <= split_valid ? split_row[9:0] : V_ACTIVE;
                            prefill_left <= H_ACTIVE >= 512 ? 6'd32 : initial_bottom_prefill;
                            top_prefill_words <= H_ACTIVE >= 512 ? 9'd256 : {initial_top_prefill,3'd0};
                            bottom_prefill_words <= H_ACTIVE >= 512 ? 9'd256 : {initial_bottom_prefill,3'd0};
                        end
                        if (reset_count == 7) begin
                            fifo_reset <= 0; reset_count <= 0; state <= RELEASE_FIFO;
                        end
                    end
                    RELEASE_FIFO: begin
                        reset_count <= reset_count + 1'b1;
                        if (reset_count == 7) begin
                            if (owner != has_bottom) begin
                                addr_current <= addr_saved; addr_saved <= addr_current;
                            end
                            owner <= has_bottom;
                            state <= has_bottom ? PREFILL_BOTTOM : RUN_TOP;
                        end
                    end
                    PREFILL_BOTTOM: if (prefill_left == 0) begin
                        state <= DRAIN_BOTTOM; quiet <= 0;
                    end
                    DRAIN_BOTTOM: if (quiet == 32 && !fetch_ack && !fetch_fill) begin
                        addr_current <= addr_saved; addr_saved <= addr_current;
                        owner <= 0; state <= RUN_TOP;
                    end
                    RUN_TOP: begin
                        if (remaining_top == 0) begin state <= DRAIN_TOP; quiet <= 0; end
                    end
                    DRAIN_TOP: if (quiet == 32 && !fetch_ack && !fetch_fill && has_bottom) begin
                        addr_current <= addr_saved; addr_saved <= addr_current;
                        owner <= 1; state <= RUN_BOTTOM;
                    end
                    RUN_BOTTOM: ;
                    default: state <= OFF;
                endcase
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] ready_vid;
    // Bundled data is held from FIFO reset through the entire frame. Ready crosses later.
    reg [11:0] config_meta, config_vid;
    reg frame_active, frame_fault, frame_started;
    reg [9:0] split_vid;
    reg indexed_vid, rgb565_vid;
    wire origin = pixel_x == 0 && pixel_y == 0;
    wire start_display = origin && !frame_started && ready_vid[1] && !reset_top_r && !reset_bottom_r;
    wire display_req = rtg_ena && !video_reset && !reset_top_r && !reset_bottom_r &&
                       pixel_x < H_ACTIVE && pixel_y < V_ACTIVE &&
                       (start_display || (frame_active && !frame_fault));
    wire selected_bottom = pixel_y >= (start_display ? config_vid[11:2] : split_vid);
    wire indexed_now = start_display ? config_vid[1] : indexed_vid;
    wire need_word = !indexed_now || !pixel_x[0];
    wire word_empty = selected_bottom ? empty_bottom : empty_top;
    wire valid_req = display_req && (!need_word || !word_empty);
    wire pop_top = valid_req && need_word && !selected_bottom;
    wire pop_bottom = valid_req && need_word && selected_bottom;

    rtg_async_fifo top_fifo (
        .wr_clk(clk_114),.rd_clk(clk_rtg),.reset(fifo_reset | !reset_n),
        .wr_en(keep_fill && !owner && fetch_fill),.wr_data(fetch_d),
        .rd_en(pop_top),.rd_data(data_top),.full(full_top),.empty(empty_top),.wr_used(used_top),
        .wr_reset_busy(reset_top_w),.rd_reset_busy(reset_top_r)
    );
    rtg_async_fifo bottom_fifo (
        .wr_clk(clk_114),.rd_clk(clk_rtg),.reset(fifo_reset | !reset_n),
        .wr_en(keep_fill && owner && fetch_fill),.wr_data(fetch_d),
        .rd_en(pop_bottom),.rd_data(data_bottom),.full(full_bottom),.empty(empty_bottom),.wr_used(used_bottom),
        .wr_reset_busy(reset_bottom_w),.rd_reset_busy(reset_bottom_r)
    );
    reg valid_1, valid_2, valid_3, bottom_1, low_byte_1, indexed_1, indexed_2, rgb565_1;
    reg [23:0] palette_rgb, direct_rgb;
    wire [15:0] word_1 = bottom_1 ? data_bottom : data_top;
    wire [7:0] palette_index = low_byte_1 ? word_1[7:0] : word_1[15:8];
    assign pixel = valid_3 && rtg_ena && !video_reset;
    assign de = pixel;
    // Stage 1: FIFO synchronous read. Stage 2: palette/direct decode. Stage 3: RGB.
    always @(posedge clk_rtg) begin
        palette_rgb <= clut[palette_index];
        direct_rgb <= rgb565_1 ?
            {word_1[15:11],word_1[15:13],word_1[10:5],word_1[10:9],word_1[4:0],word_1[4:2]} :
            {word_1[14:10],word_1[14:12],word_1[9:5],word_1[9:7],word_1[4:0],word_1[4:2]};
    end
    always @(posedge clk_rtg or negedge reset_n) begin
        if (!reset_n) begin
            ready_vid <= 0; config_meta <= 0; config_vid <= 0;
            frame_active <= 0; frame_fault <= 0; frame_started <= 0;
            split_vid <= V_ACTIVE; indexed_vid <= 0; rgb565_vid <= 1;
            valid_1 <= 0; valid_2 <= 0; valid_3 <= 0;
            bottom_1 <= 0; low_byte_1 <= 0; indexed_1 <= 0; indexed_2 <= 0; rgb565_1 <= 1;
            red <= 0; green <= 0; blue <= 0;
        end else begin
            ready_vid <= {ready_vid[0],frame_ready};
            config_meta <= {frame_split,frame_indexed,frame_565}; config_vid <= config_meta;
            if (!rtg_ena || video_reset || reset_top_r || reset_bottom_r) begin
                frame_active <= 0; frame_fault <= 0; frame_started <= 0;
                valid_1 <= 0; valid_2 <= 0; valid_3 <= 0;
                red <= 0; green <= 0; blue <= 0;
            end else begin
                if (start_display) begin
                    frame_active <= 1; frame_fault <= 0;
                    split_vid <= config_vid[11:2]; indexed_vid <= config_vid[1]; rgb565_vid <= config_vid[0];
                end
                if (display_req && need_word && word_empty) frame_fault <= 1;
                // Frame start is deliberately not a FIFO reset: its first pixels are already in flight.
                if (frame_start) frame_started <= 1;
                if (vblank_start) begin frame_active <= 0; frame_started <= 0; end
                valid_1 <= valid_req; valid_2 <= valid_1; valid_3 <= valid_2;
                bottom_1 <= selected_bottom; low_byte_1 <= pixel_x[0];
                indexed_1 <= indexed_now; indexed_2 <= indexed_1;
                rgb565_1 <= start_display ? config_vid[0] : rgb565_vid;
                {red,green,blue} <= valid_2 ? (indexed_2 ? palette_rgb : direct_rgb) : 24'd0;
            end
        end
    end
endmodule
