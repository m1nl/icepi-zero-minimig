`timescale 1ns/1ps
module rtg_osd_tb;
    reg wc=0,rc=0;
    always #17.5 wc=~wc;
    always #7.575757 rc=~rc;
    reg reset_n=0,video_reset=1,en=0,we=0;
    reg [10:0] addr=0;
    reg [7:0] d=0;
    reg request=0,start=0,expect_pixel=0;
    reg expected_enable=0;
    wire overlay,pixel;
    rtg_osd dut(.clk_write(wc),.clk_rtg(rc),.reset_n(reset_n),.video_reset(video_reset),
        .write_en(we),.write_addr(addr),.write_data(d),.enable(en),
        .pixel_request(request),.frame_request(start),.overlay(overlay),.pixel(pixel));
    function [7:0] pattern;
        input [10:0] a;
        begin pattern=a[7:0] ^ {5'd0,a[10:8]} ^ 8'h96;end
    endfunction
    reg [2:0] expected_window=0,expected_bits=0;
    integer checks=0;
    always @(posedge rc) begin
        if(!reset_n) begin
            expected_window=0;expected_bits=0;expected_enable=0;
        end else begin
            // Frame enable takes effect after the start-request edge. The
            // first requested pixel uses the previous frame's enable state.
            expected_window={expected_window[1:0],request && expected_enable};
            expected_bits={expected_bits[1:0],expect_pixel};
            if(video_reset) expected_enable=0;
            else if(start) expected_enable=en;
        end
        #1;
        if(overlay!==expected_window[2] || (overlay && pixel!==expected_bits[2]))
            $fatal(1,"OSD stream mismatch overlay=%b/%b pixel=%b/%b row=%d column=%d",overlay,expected_window[2],pixel,expected_bits[2],dut.row,dut.column);
        if(overlay) checks=checks+1;
    end
    task window_frame;
        integer x,y;
        reg [7:0] word;
        begin
            for(y=0;y<128;y=y+1) begin
                for(x=0;x<256;x=x+1) begin
                    @(negedge rc);
                    request=1;start=(x==0 && y==0);
                    word=pattern((y/16)*256+x);
                    expect_pixel=word[(y/2)%8];
                end
                @(negedge rc);request=0;start=0;
                repeat(8) @(negedge rc);
            end
        end
    endtask
    integer i;
    initial begin
        #40;reset_n=1;
        for(i=0;i<2048;i=i+1) begin
            @(negedge wc);we=1;addr=i;d=pattern(i);
        end
        @(negedge wc);we=0;
        en=1;video_reset=0;repeat(4) @(negedge rc);
        window_frame;
        if(checks!=32767) $fatal(1,"OSD frame has %0d pixels",checks);
        // Disable latches on the start edge; the first pixel still uses the old enable.
        en=0;repeat(4) @(negedge rc);window_frame;
        if(checks!=32768) $fatal(1,"OSD disable transition pixel count");
        video_reset=1;repeat(4) @(negedge rc);
        video_reset=0;en=1;repeat(4) @(negedge rc);window_frame;
        if(checks!=65535) $fatal(1,"OSD restart pixel count");
        $display("PASS: event-driven OSD RAM, 1x/2y scale, blank gaps, enable and reset restart");
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
