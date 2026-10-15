`timescale 1ns/1ps
// Compile against Lattice's DCSC.v model.
module video_clock_control_tb;
    reg clk = 0, native_pixel = 0, native5 = 0, rtg_pixel = 0, rtg5 = 0;
    always #10 clk = ~clk;
    always #17.5 native_pixel = ~native_pixel;
    always #3.5 native5 = ~native5;
    always #7.575758 rtg_pixel = ~rtg_pixel;
    always #1.515152 rtg5 = ~rtg5;
    reg native_locked = 0, rtg_locked = 0, request = 0;
    wire active, video_reset, pixel, serial;
    video_clock_control dut (
        .clk(clk), .clk_pixel(pixel), .native_locked(native_locked),
        .rtg_locked(rtg_locked), .rtg_request(request), .rtg_active(active),
        .video_reset(video_reset)
    );
    DCSC #(.DCSMODE("NEG")) pixel_mux (
        .CLK0(native_pixel), .CLK1(rtg_pixel), .SEL0(!active), .SEL1(active),
        .MODESEL(1'b0), .DCSOUT(pixel)
    );
    DCSC #(.DCSMODE("NEG")) serial_mux (
        .CLK0(native5), .CLK1(rtg5), .SEL0(!active), .SEL1(active),
        .MODESEL(1'b0), .DCSOUT(serial)
    );
    realtime last_pixel_rise = 0, last_serial_rise = 0;
    integer pixel_edges = 0, serial_edges = 0;
    always @(posedge pixel) begin last_pixel_rise = $realtime; pixel_edges = pixel_edges + 1; end
    always @(posedge serial) begin last_serial_rise = $realtime; serial_edges = serial_edges + 1; end
    always @(negedge pixel)
        if ($realtime > 100 && $realtime - last_pixel_rise < 7.57)
            $fatal(1, "DCSC produced a short pixel pulse");
    always @(negedge serial)
        if ($realtime > 100 && $realtime - last_serial_rise < 1.51)
            $fatal(1, "DCSC produced a short serializer pulse");
    always @(active) if ($time > 100 && !video_reset)
        $fatal(1, "Selector changed without HDMI reset");
    always @(negedge video_reset) begin
        if (!native_locked || !rtg_locked)
            $fatal(1, "HDMI released with selected PLL unlocked");
        if (pixel !== 1'b1) $fatal(1, "Reset release not on pixel clock edge");
    end
    initial begin
        #100 native_locked = 1;
        #1700;
        if (!video_reset || active) $fatal(1, "Both PLLs must lock before HDMI reset releases");
        request = 1;
        #1700;
        if (!video_reset || active) $fatal(1, "Unlocked RTG PLL selected or reset released");
        rtg_locked = 1;
        #1700;
        if (video_reset || !active) $fatal(1, "RTG switch failed");
        request = 0;
        #1700;
        if (video_reset || active) $fatal(1, "Native switch failed");
        request = 1;
        #1700;
        rtg_locked = 0;
        #0.01;
        if (!video_reset) $fatal(1, "RTG lock loss did not assert reset");
        #1700;
        if (!video_reset || active) $fatal(1, "Native fallback must hold reset until RTG PLL relocks");
        request = 0;
        rtg_locked = 1;
        #1700;
        if (video_reset || active) $fatal(1, "Native fallback did not resume after relock");
        native_locked = 0;
        #0.01;
        if (!video_reset) $fatal(1, "Native lock loss did not assert reset");
        #100 native_locked = 1;
        #1700;
        if (video_reset || active) $fatal(1, "Native restart failed");
        if (pixel_edges < 100 || serial_edges < 500) $fatal(1, "Clock outputs missing");
        $display("PASS: native boot, RTG/native switching, lock loss, reset and glitchless DCSC pulses");
        $finish;
    end
endmodule
