`timescale 1ns/1ps

module hdmi_audio_counter_case #(
    parameter RTG_HZ = 66000000,
    parameter AUDIO_HZ = 48000
) (
    input clk, reset, rtg,
    output reg [31:0] samples = 0
);
    localparam VIDEO_HZ = 28571400;
    localparam WIDTH = $clog2((RTG_HZ > VIDEO_HZ ? RTG_HZ : VIDEO_HZ) + AUDIO_HZ + 1);
    reg [WIDTH-1:0] reference_count;
    wire [WIDTH-1:0] video_rate = rtg ? RTG_HZ : VIDEO_HZ;
    wire sample_en;

    hdmi #(.AUDIO_BIT_WIDTH(16), .AUDIO_RATE(AUDIO_HZ), .RTG_VIDEO_RATE(RTG_HZ)) dut (
        .clk_pixel(clk), .clk_pixel_x5(clk), .reset(reset), .rtg_en(rtg),
        .pal_mode(1'b1), .long_frame(1'b1), .interlace(1'b0),
        .screen_mode(2'd0), .offset_x(8'd0), .offset_y(7'd0),
        .hsync_in(1'b1), .vsync_in(1'b1), .rgb(24'd0),
        .audio_sample_word_0(16'd0), .audio_sample_word_1(16'd0),
        .audio_sample_en(sample_en), .tmds(), .tmds_clock(),
        .frame_start_toggle(), .vblank_start_toggle(),
        .rtg_pixel_request(), .rtg_frame_request(), .rtg_line_prepare(),
        .osd_pixel_request(), .osd_frame_request()
    );

    // Original recurrence checks modular wrap, threshold timing and mode changes.
    always @(posedge clk or posedge reset) begin
        if (reset)
            reference_count <= 0;
        else if (reference_count >= video_rate)
            reference_count <= reference_count + AUDIO_HZ - video_rate;
        else
            reference_count <= reference_count + AUDIO_HZ;
    end

    always @(negedge clk) begin
        if (dut.true_hdmi_output.audio_clock_counter !== reference_count ||
            sample_en !== (reference_count >= video_rate))
            $fatal(1, "Audio counter mismatch: RTG=%0d audio=%0d", RTG_HZ, AUDIO_HZ);
        if (!reset && sample_en)
            samples <= samples + 1;
    end
endmodule

module hdmi_audio_counter_tb;
    reg clk = 0, reset = 1, rtg = 0;
    reg [15:0] random_mode = 16'h1234;
    wire [31:0] samples_66, samples_74, samples_44;
    always #5 clk = ~clk;

    hdmi_audio_counter_case native_rtg (clk, reset, rtg, samples_66);
    hdmi_audio_counter_case #(.RTG_HZ(74250000)) raster_720p (clk, reset, rtg, samples_74);
    hdmi_audio_counter_case #(.AUDIO_HZ(44100)) rate_44100 (clk, reset, rtg, samples_44);

    integer cycle;
    initial begin
        repeat (3) @(negedge clk);
        #1 reset = 0;
        for (cycle = 0; cycle < 100000; cycle = cycle + 1) begin
            @(negedge clk);
            #1;
            random_mode = {random_mode[14:0], random_mode[15] ^ random_mode[13] ^
                           random_mode[12] ^ random_mode[10]};
            // Stable native/RTG intervals followed by frequent live mode changes.
            rtg = cycle < 20000 ? 1'b0 : cycle < 40000 ? 1'b1 : random_mode[0];
            reset = cycle % 8192 == 8191;
            #1;
            if (reset && (native_rtg.dut.true_hdmi_output.audio_clock_counter !== 0 ||
                          raster_720p.dut.true_hdmi_output.audio_clock_counter !== 0 ||
                          rate_44100.dut.true_hdmi_output.audio_clock_counter !== 0))
                $fatal(1, "Audio counter did not reset asynchronously");
        end
        if (samples_66 < 20 || samples_74 < 20 || samples_44 < 20)
            $fatal(1, "Insufficient audio wrap coverage");
        $display("PASS: HDMI audio counter, native/66/74.25 MHz, 44.1/48 kHz, reset and live mode changes");
        $finish;
    end
endmodule
