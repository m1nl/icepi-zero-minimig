// Implementation of HDMI Spec v1.4a
// By Sameer Puri https://github.com/sameer

// The original hdmi.sv generated its own timing completely independent.
// This version synchronizes to an external sync signal which is expected to
// have exactly half the horizontal refresh rate.

module hdmi
#(
    // The IT content bit indicates that image samples are generated in an ad-hoc
    // manner (e.g. directly from values in a framebuffer, as by a PC video
    // card) and therefore aren't suitable for filtering or analog
    // reconstruction.  This is probably what you want if you treat pixels
    // as "squares".  If you generate a properly bandlimited signal or obtain
    // one from elsewhere (e.g. a camera), this can be turned off.
    //
    // This flag also tends to cause receivers to treat RGB values as full
    // range (0-255).
    parameter bit IT_CONTENT = 1'b1,

    // A true HDMI signal sends auxiliary data (i.e. audio, preambles) which prevents it from being parsed by DVI signal sinks.
    // HDMI signal sinks are fortunately backwards-compatible with DVI signals.
    // Enable this flag if the output should be a DVI signal. You might want to do this to reduce resource usage or if you're only outputting video.
    parameter bit DVI_OUTPUT = 1'b0,

    // **All parameters below matter ONLY IF you plan on sending auxiliary data (DVI_OUTPUT == 1'b0)**

    parameter int VIDEO_RATE = 28571400,

    // As specified in Section 7.3, the minimal audio requirements are met: 16-bit or more L-PCM audio at 32 kHz, 44.1 kHz, or 48 kHz.
    // See Table 7-4 or README.md for an enumeration of sampling frequencies supported by HDMI.
    // Note that sinks may not support rates above 48 kHz.
    parameter int AUDIO_RATE = 48000,

    // Defaults to 16-bit audio, the minmimum supported by HDMI sinks. Can be anywhere from 16-bit to 24-bit.
    parameter int AUDIO_BIT_WIDTH = 24,

    // Some HDMI sinks will show the source product description below to users (i.e. in a list of inputs instead of HDMI 1, HDMI 2, etc.).
    // If you care about this, change it below.
    parameter bit [8*8-1:0] VENDOR_NAME = {"Unknown", 8'd0}, // Must be 8 bytes null-padded 7-bit ASCII
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0}, // Must be 16 bytes null-padded 7-bit ASCII
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00 // See README.md or CTA-861-G for the list of valid codes
)
(
    input logic clk_pixel_x5,
    input logic clk_pixel,
    // synchronous reset back to 0,0
    input logic reset,

    input logic       pal_mode,    // 1 for pal timing
    input logic       long_frame,  // 1 if short frame has been detected
    input logic       interlace,   // 1 if interlace has been detected
    input logic [1:0] screen_mode, // 1 for overscan, 2 for wide, other default

    input [7:0] offset_x,
    input [6:0] offset_y,

    input logic vsync_in,
    input logic hsync_in,

    input logic [23:0] rgb,

    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word_0,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word_1,
    output logic                       audio_sample_en,

    // These outputs go to your HDMI port
    output logic [2:0] tmds,
    output logic tmds_clock
);

localparam int NUM_CHANNELS = 3;

logic hsync;
logic vsync;

logic [1:0] invert;

logic [7:0] cea_pal    = 8'd17; // 720x576p @ 50Hz
logic [7:0] cea_pal_i  = 8'd21; // 720(1440)x576i @ 50Hz
logic [7:0] cea_ntsc   = 8'd02; // 720x480p @ 59.94/60Hz
logic [7:0] cea_ntsc_i = 8'd06; // 720(1440)x480i @ 59.94/60Hz

logic [10:0] frame_width;
logic [10:0] screen_width;
logic [10:0] hsync_pulse_start;
logic [10:0] hsync_pulse_size;

logic [9:0] frame_height;
logic [9:0] screen_height;
logic [9:0] vsync_pulse_start;
logic [9:0] vsync_pulse_size;

logic [7:0] video_id_code;

logic [10:0] cx;
logic  [9:0] cy;

assign invert = 2'b11;

logic vsync_in_d;
logic hsync_in_d;

logic [7:0] offset_x_r;
logic [6:0] offset_y_r;

logic sync_done;

logic [2:0] video_mode = {pal_mode, long_frame || interlace, interlace};
logic [2:0] video_mode_d;

logic [1:0] screen_mode_d;

logic video_mode_changed;

always_comb begin
    hsync <= invert[0] ^ (cx >= screen_width + hsync_pulse_start && cx < screen_width + hsync_pulse_start + hsync_pulse_size);
    // vsync pulses should begin and end at the start of hsync, so special
    // handling is required for the lines on which vsync starts and ends
    if (cy == screen_height + vsync_pulse_start - 1)
        vsync <= invert[1] ^ (cx >= screen_width + hsync_pulse_start);
    else if (cy == screen_height + vsync_pulse_start + vsync_pulse_size - 1)
        vsync <= invert[1] ^ (cx < screen_width + hsync_pulse_start);
    else
        vsync <= invert[1] ^ (cy >= screen_height + vsync_pulse_start && cy < screen_height + vsync_pulse_start + vsync_pulse_size);
end

always_comb begin
    frame_width = 11'd908;

    hsync_pulse_start = 11'd24;

    vsync_pulse_start = 10'd5;
    vsync_pulse_size = 10'd5;
end

always_ff @(posedge clk_pixel, posedge reset) begin
    if (reset)
    begin
        screen_width <= 11'd720;
        hsync_pulse_size <= 11'd72;
    end
    else if (offset_x_r == 0 && offset_y_r == 0 && !sync_done)
    begin
        case (screen_mode)
            default: begin
                screen_width <= 11'd720;
                hsync_pulse_size <= 11'd72;
            end
            2'b01: begin
                screen_width <= 11'd768;
                hsync_pulse_size <= 11'd72;
            end
            2'b10: begin
                screen_width <= 11'd832;
                hsync_pulse_size <= 11'd48;
            end
        endcase

        screen_mode_d <= screen_mode;
    end
end

always_ff @(posedge clk_pixel) begin
    hsync_in_d <= hsync_in;

    if (!hsync_in && hsync_in_d)
    begin
        vsync_in_d <= vsync_in;
    end
end

// Wrap-around pixel position counters indicating the pixel to be generated by the user in THIS clock and sent out in the NEXT clock.
always_ff @(posedge clk_pixel, posedge reset) begin
    if (reset)
    begin
        cx <= 11'd0;
        cy <= 10'd0;

        sync_done <= 0;

        offset_x_r <= 0;
        offset_y_r <= 0;

        frame_height <= 10'd626;
        screen_height <= 10'd576;
        video_id_code <= cea_pal;
    end
    else
    begin
        cx <= cx == frame_width-1'b1 ? 11'd0 : cx + 1'b1;
        cy <= cx == frame_width-1'b1 ? cy == frame_height-1'b1 ? 10'd0 : cy + 1'b1 : cy;

        offset_x_r <= offset_x_r - 1;

        if (!hsync_in && hsync_in_d)
        begin
            offset_x_r <= offset_x;
            offset_y_r <= offset_y_r - 1;

            if (!vsync_in && vsync_in_d)
            begin
                offset_y_r <= offset_y;
                sync_done <= 0;
            end
        end

        if (offset_x_r == 0 && offset_y_r == 0 && !sync_done)
        begin
            cx <= 11'd0;
            cy <= 10'd0;

            sync_done <= 1;

            // timing here is based on video_analyzer.v from MiSTle project
            casez ({pal_mode, long_frame, interlace})
                3'b110: begin
                    frame_height <= 10'd626;
                    screen_height <= 10'd576;
                    video_id_code <= cea_pal;
                end
                3'b100: begin
                    frame_height <= 10'd624;
                    screen_height <= 10'd576;
                    video_id_code <= cea_pal;
                end
                3'b1z1: begin
                    frame_height <= 10'd625;
                    screen_height <= 10'd576;
                    video_id_code <= cea_pal_i;
                end
                3'b010: begin
                    frame_height <= 10'd526;
                    screen_height <= 10'd480;
                    video_id_code <= cea_ntsc;
                end
                3'b000: begin
                    frame_height <= 10'd524;
                    screen_height <= 10'd480;
                    video_id_code <= cea_ntsc;
                end
                3'b0z1: begin
                    frame_height <= 10'd525;
                    screen_height <= 10'd480;
                    video_id_code <= cea_ntsc_i;
                end
            endcase

            video_mode_d <= {pal_mode, long_frame || interlace, interlace};
        end
    end
end

always_ff @(posedge clk_pixel, posedge reset) begin
    if (reset)
    begin
        video_mode_changed <= 0;
    end
    else if (offset_x_r == 0 && offset_y_r == 0 && !sync_done)
    begin
        video_mode_changed <= (video_mode != video_mode_d) || (screen_mode != screen_mode_d);
    end
end

// See Section 5.2
logic video_data_period = 0;
always_ff @(posedge clk_pixel, posedge reset)
begin
    if (reset)
        video_data_period <= 0;
    else
        video_data_period <= cx < screen_width && cy < screen_height;
end

logic [2:0] mode = 3'd1;
logic [23:0] video_data = 24'd0;
logic [5:0] control_data = 6'd0;
logic [11:0] data_island_data = 12'd0;

generate
    if (!DVI_OUTPUT)
    begin: true_hdmi_output
        logic video_guard = 1;
        logic video_preamble = 0;
        always_ff @(posedge clk_pixel, posedge reset)
        begin
            if (reset)
            begin
                video_guard <= 1;
                video_preamble <= 0;
            end
            else
            begin
                video_guard <= cx >= frame_width - 2 && cx < frame_width && (cy == frame_height - 1 || cy < screen_height - 1 /* no VG at end of last line */);
                video_preamble <= cx >= frame_width - 10 && cx < frame_width - 2 && (cy == frame_height - 1 || cy < screen_height - 1 /* no VP at end of last line */);
            end
        end

        // See Section 5.2.3.1
        int max_num_packets_alongside;
        logic [4:0] num_packets_alongside;
        always_comb
        begin
	    max_num_packets_alongside = (frame_width - screen_width  /* VD period */ - 2 /* V guard */ - 8 /* V preamble */ - 4 /* Min V control period */ - 2 /* DI trailing guard */ - 2 /* DI leading guard */ - 8 /* DI premable */ - 4 /* Min DI control period */) / 32;
            if (max_num_packets_alongside > 18)
                num_packets_alongside = 5'd18;
            else
                num_packets_alongside = 5'(max_num_packets_alongside);
        end

        logic data_island_period_instantaneous;
        assign data_island_period_instantaneous = num_packets_alongside > 0 && cx >= screen_width + 14 && cx < screen_width + 14 + num_packets_alongside * 32;
        logic packet_enable;
        assign packet_enable = data_island_period_instantaneous && 5'(cx + screen_width + 18) == 5'd0;

        logic data_island_guard = 0;
        logic data_island_preamble = 0;
        logic data_island_period = 0;
        always_ff @(posedge clk_pixel, posedge reset)
        begin
            if (reset)
            begin
                data_island_guard <= 0;
                data_island_preamble <= 0;
                data_island_period <= 0;
            end
            else
            begin
	        data_island_guard <= num_packets_alongside > 0 && (
                    (cx >= screen_width + 12 && cx < screen_width + 14) /* leading guard */ ||
                    (cx >= screen_width + 14 + num_packets_alongside * 32 && cx < screen_width + 14 + num_packets_alongside * 32 + 2) /* trailing guard */
                );
                data_island_preamble <= num_packets_alongside > 0 && cx >= screen_width + 4 && cx < screen_width + 12;
                data_island_period <= data_island_period_instantaneous;
            end
        end

        // See Section 5.2.3.4
        logic [23:0] header;
        logic [55:0] sub_0, sub_1, sub_2, sub_3;
        logic video_field_end;
        assign video_field_end = cx == screen_width - 1'b1 && cy == screen_height - 1'b1;
        logic [4:0] packet_pixel_counter;

        packet_picker #(
            .IT_CONTENT(IT_CONTENT),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME(VENDOR_NAME),
            .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
            .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
        ) packet_picker_inst (
            .clk_pixel(clk_pixel),
            .audio_sample_en(audio_sample_en),
            .reset(reset),
            .video_id_code(video_id_code),
            .video_field_end(video_field_end),
            .packet_enable(packet_enable),
            .packet_pixel_counter(packet_pixel_counter),
            .audio_sample_word_0(audio_sample_word_0),
            .audio_sample_word_1(audio_sample_word_1),
            .header(header),
            .sub_0(sub_0),
            .sub_1(sub_1),
            .sub_2(sub_2),
            .sub_3(sub_3)
        );

        logic [8:0] packet_data;
        packet_assembler packet_assembler_inst (
            .clk_pixel(clk_pixel),
            .reset(reset),
            .data_island_period(data_island_period),
            .header(header),
            .sub_0(sub_0),
            .sub_1(sub_1),
            .sub_2(sub_2),
            .sub_3(sub_3),
            .packet_data(packet_data),
            .counter(packet_pixel_counter)
        );

        always_ff @(posedge clk_pixel, posedge reset, posedge video_mode_changed)
        begin
            if (reset || video_mode_changed)
            begin
                mode <= 3'd2;
                video_data <= 24'd0;
                control_data <= 6'd0;
                data_island_data <= 12'd0;
            end
            else
            begin
                mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
                video_data <= rgb;
                control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
                data_island_data[11:4] <= packet_data[8:1];
                data_island_data[3] <= cx != 0;
                data_island_data[2] <= packet_data[0];
                data_island_data[1:0] <= {vsync, hsync};
            end
        end

        localparam integer AUDIO_CLOCK_COUNTER_WIDTH = $clog2(VIDEO_RATE + AUDIO_RATE + 1);

        reg [AUDIO_CLOCK_COUNTER_WIDTH-1:0] audio_clock_counter;

        assign audio_sample_en = audio_clock_counter >= VIDEO_RATE[AUDIO_CLOCK_COUNTER_WIDTH-1:0];

        always @(posedge clk_pixel, posedge reset) begin
            if (reset)
            begin
                audio_clock_counter <= 0;
            end
            else
            begin
                audio_clock_counter <= audio_clock_counter + AUDIO_RATE[AUDIO_CLOCK_COUNTER_WIDTH-1:0];

                if (audio_sample_en)
                    audio_clock_counter <= audio_clock_counter + AUDIO_RATE[AUDIO_CLOCK_COUNTER_WIDTH-1:0] -
                        VIDEO_RATE[AUDIO_CLOCK_COUNTER_WIDTH-1:0];
            end
        end
    end
    else // DVI_OUTPUT = 1
    begin
        always_ff @(posedge clk_pixel, posedge reset)
        begin
            if (reset)
            begin
                mode <= 3'd0;
                video_data <= 24'd0;
                control_data <= 6'd0;
            end
            else
            begin
                mode <= video_data_period ? 3'd1 : 3'd0;
                video_data <= rgb;
                control_data <= {4'b0000, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
            end
        end
    end
endgenerate

// All logic below relates to the production and output of the 10-bit TMDS code.
logic [9:0] tmds_internal [NUM_CHANNELS-1:0] /* verilator public_flat */ ;
genvar i;
generate
    // TMDS code production.
    for (i = 0; i < NUM_CHANNELS; i++)
    begin: tmds_gen
        tmds_channel #(
            .CN(i)
        ) tmds_channel (
            .clk_pixel(clk_pixel),
            .video_data(video_data[i*8+7:i*8]),
            .data_island_data(data_island_data[i*4+3:i*4]),
            .control_data(control_data[i*2+1:i*2]),
            .mode(mode),
            .tmds(tmds_internal[i])
        );
    end
endgenerate

serializer #(
    .NUM_CHANNELS(NUM_CHANNELS)
) serializer (
    .clk_pixel(clk_pixel),
    .clk_pixel_x5(clk_pixel_x5),
    .reset(reset),
    .tmds_internal(tmds_internal),
    .tmds(tmds),
    .tmds_clock(tmds_clock)
);

endmodule
// vim:ts=4 sw=4 tw=120 et
