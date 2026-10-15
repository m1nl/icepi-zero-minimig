`timescale 1ns/1ps
module hdmi_reset_tb;
    parameter LEAD=2;
    reg clk = 0, reset = 1, rtg = 0;
    reg pal = 1, long_frame = 1, interlace = 0;
    reg [1:0] screen = 0;
    always #5 clk = ~clk;
    wire [10:0] x = dut.cx;
    wire [9:0] y = dut.cy;
    wire frame_start = x==0 && y==0 && !reset;
    wire vblank_start = x==0 && y==768 && !reset;
    wire frame_toggle,blank_toggle,scan_pixel,scan_frame,scan_line,osd_pixel,osd_frame;
    hdmi #(.DVI_OUTPUT(1), .AUDIO_BIT_WIDTH(16),.RTG_REQUEST_LEAD(LEAD)) dut (
        .clk_pixel(clk), .clk_pixel_x5(clk), .reset(reset), .rtg_en(rtg),
        .pal_mode(pal), .long_frame(long_frame), .interlace(interlace),
        .screen_mode(screen), .offset_x(8'd0), .offset_y(7'd0),
        .hsync_in(1'b1), .vsync_in(1'b1), .rgb(24'd0),
        .audio_sample_word_0(16'd0), .audio_sample_word_1(16'd0),
        .audio_sample_en(), .tmds(), .tmds_clock(),
        .frame_start_toggle(frame_toggle), .vblank_start_toggle(blank_toggle),
        .rtg_pixel_request(scan_pixel),.rtg_frame_request(scan_frame),.rtg_line_prepare(scan_line),
        .osd_pixel_request(osd_pixel),.osd_frame_request(osd_frame)
    );
    integer cycles, blanks, expected_x, expected_y;
    integer expected_request_x, expected_request_y;
    initial begin
        repeat (3) @(negedge clk);
        if (x !== 0 || y !== 0 || dut.screen_width !== 720 || dut.screen_height !== 576)
            $fatal(1, "Native reset configuration incorrect");
        // Input-dependent reset values change only on a pixel clock edge.
        #1 rtg = 1;
        #1;
        if (dut.screen_width !== 720 || dut.screen_height !== 576)
            $fatal(1, "Timing registers changed asynchronously");
        @(negedge clk);
        if (x !== 0 || y !== 0 || dut.screen_width !== 1024 || dut.screen_height !== 768 ||
            dut.frame_width !== 1344 || dut.frame_height !== 806 || dut.video_id_code !== 0)
            $fatal(1, "RTG reset configuration incorrect");
        reset = 0;
        blanks = 0;
        for (cycles = 1; cycles <= 1344*806; cycles = cycles + 1) begin
            @(negedge clk);
            expected_x = cycles % 1344;
            expected_y = (cycles / 1344) % 806;
            if (x !== expected_x || y !== expected_y)
                $fatal(1, "RTG coordinates %0d,%0d expected %0d,%0d", x, y, expected_x, expected_y);
            // Toggles describe the coordinate before the edge; the first
            // frame edge toggles SOF, and the first blank edge toggles vblank.
            if (frame_toggle !== 1'b1 || blank_toggle !== (cycles>1344*768))
                $fatal(1, "RTG toggle alignment at %0d,%0d", x, y);
            expected_request_x = (cycles + LEAD) % 1344;
            expected_request_y = ((cycles + LEAD) / 1344) % 806;
            if (scan_pixel !== (expected_request_x<1024 && expected_request_y<768) ||
                // Frame setup precedes the first pixel request by one cycle.
                scan_frame !== (expected_request_x==1343 && expected_request_y==805) ||
                scan_line !== (expected_request_x==1024))
                $fatal(1,"RTG event alignment at %0d,%0d",x,y);
            if (osd_pixel !== (expected_request_x>=640 && expected_request_x<896 && expected_request_y>=512 && expected_request_y<640) ||
                osd_frame !== (expected_request_x==640 && expected_request_y==512))
                $fatal(1,"OSD event alignment at %0d,%0d",x,y);
            if (vblank_start) blanks = blanks + 1;
            // Native mode changes must not disturb RTG timing.
            pal = ~pal; long_frame = ~long_frame; interlace = ~interlace; screen = screen + 1'b1;
        end
        if (!frame_start || blanks != 1) $fatal(1, "RTG frame/vblank events incorrect");
        reset = 1; rtg = 0; pal = 1; long_frame = 1; interlace = 0; screen = 0;
        repeat (3) @(negedge clk);
        if (x !== 0 || y !== 0 || dut.screen_width !== 720 || dut.screen_height !== 576 ||
            dut.frame_width !== 908 || dut.frame_height !== 626 || dut.video_id_code !== 17)
            $fatal(1, "Return to native reset configuration failed");
        reset = 0;
        repeat (5) @(negedge clk);
        if (dut.screen_width !== 720 || dut.screen_height !== 576)
            $fatal(1, "Native timing lost after reset release");
        $display("PASS: synchronous native/RTG reset, complete RTG frame and native fallback");
        $finish;
    end
endmodule
