`timescale 1ns/1ps

module hdmi_audio_stream_case #(
    parameter RTG = 0, PIXEL_HZ = 66000000,
    parameter FW = 1344, FH = 806, SW = 1024, SH = 768,
    parameter HS_START = 24, HS_SIZE = 136, VS_START = 3, VS_SIZE = 6
)(output reg done = 0);
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire sample_en;
    integer captured = 0, delivered = 0, packets = 0;
    reg [15:0] expected_left [0:8191], expected_right [0:8191];
    reg [15:0] left = 16'd1, right = 16'hace1;
    // Drive source data away from the capture/check edge.
    always @(negedge clk) begin
        left = 16'(captured * 257 + 1);
        right = 16'((captured * 769) ^ 16'hace1);
    end
    hdmi #(
        .AUDIO_BIT_WIDTH(16), .RTG_VIDEO_RATE(PIXEL_HZ),
        .RTG_FRAME_WIDTH(FW), .RTG_FRAME_HEIGHT(FH),
        .RTG_SCREEN_WIDTH(SW), .RTG_SCREEN_HEIGHT(SH),
        .RTG_HSYNC_PULSE_START(HS_START), .RTG_HSYNC_PULSE_SIZE(HS_SIZE),
        .RTG_VSYNC_PULSE_START(VS_START), .RTG_VSYNC_PULSE_SIZE(VS_SIZE)
    ) dut (
        .clk_pixel(clk), .clk_pixel_x5(clk), .reset(reset), .rtg_en(1'(RTG)),
        .pal_mode(1'b1), .long_frame(1'b1), .interlace(1'b0),
        // Native wide mode has the tightest blanking: one packet per line.
        .screen_mode(2'd2), .offset_x(8'd0), .offset_y(7'd0),
        .hsync_in(1'b1), .vsync_in(1'b1), .rgb(24'd0),
        .audio_sample_word_0(left), .audio_sample_word_1(right),
        .audio_sample_en(sample_en), .tmds(), .tmds_clock(),
        .frame_start_toggle(), .vblank_start_toggle(),
        .rtg_pixel_request(), .rtg_frame_request(), .rtg_line_prepare(),
        .osd_pixel_request(), .osd_frame_request()
    );
    wire [55:0] subs [0:3];
    assign subs[0] = dut.true_hdmi_output.sub_0;
    assign subs[1] = dut.true_hdmi_output.sub_1;
    assign subs[2] = dut.true_hdmi_output.sub_2;
    assign subs[3] = dut.true_hdmi_output.sub_3;
    integer lane;
    always @(posedge clk) begin
        if (reset) begin
            captured = 0;
            delivered = 0;
        end else begin
            if (sample_en) begin
                expected_left[captured] = left;
                expected_right[captured] = right;
                captured = captured + 1;
            end
            if (dut.true_hdmi_output.data_island_period &&
                dut.true_hdmi_output.packet_pixel_counter == 0 &&
                dut.true_hdmi_output.header[7:0] == 8'd2) begin
                if (captured - delivered < 4)
                    $fatal(1, "HDMI scheduled an incomplete audio packet");
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (subs[lane][23:0] !== {expected_left[delivered+lane], 8'd0} ||
                        subs[lane][47:24] !== {expected_right[delivered+lane], 8'd0})
                        $fatal(1, "HDMI audio lost/reordered: RTG=%0d Hz=%0d packet=%0d lane=%0d", RTG, PIXEL_HZ, packets, lane);
                end
                delivered = delivered + 4;
                packets = packets + 1;
            end
        end
    end
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (2 * (RTG ? FW*FH : 908*626)) @(negedge clk);
        if (packets < 48 || captured - delivered >= 12)
            $fatal(1, "Insufficient HDMI audio progress");
        $display("PASS: continuous HDMI audio across two frames, RTG=%0d Hz=%0d packets=%0d", RTG, RTG ? PIXEL_HZ : 28571400, packets);
        done = 1;
    end
endmodule

module hdmi_audio_stream_tb;
    wire native_done, rtg_done, hd_done;
    hdmi_audio_stream_case native_wide(native_done);
    hdmi_audio_stream_case #(.RTG(1)) rtg_1024(rtg_done);
    hdmi_audio_stream_case #(
        .RTG(1), .PIXEL_HZ(74250000), .FW(1650), .FH(750), .SW(1280), .SH(720),
        .HS_START(110), .HS_SIZE(40), .VS_START(5), .VS_SIZE(5)
    ) rtg_720p(hd_done);
    initial begin
        wait (native_done && rtg_done && hd_done);
        $finish;
    end
    initial begin
        #30000000;
        $fatal(1, "HDMI audio stream test timeout");
    end
endmodule
