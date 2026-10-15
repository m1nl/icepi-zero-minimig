module hdmi_rtg_tb;
logic clk=0; always #5 clk=~clk;
logic reset=0,rtg_en=1,pal_mode=1,long_frame=1,interlace=0;
logic [1:0] screen_mode=0;
logic [7:0] offset_x=255;
logic [6:0] offset_y=127;
logic hsync_in=1,vsync_in=1;
hdmi dut(.clk_pixel(clk),.clk_pixel_x5(clk),.reset(reset),.rtg_en(rtg_en),.pal_mode(pal_mode),.long_frame(long_frame),.interlace(interlace),.screen_mode(screen_mode),.offset_x(offset_x),.offset_y(offset_y),.hsync_in(hsync_in),.vsync_in(vsync_in),.rgb(24'd0),.audio_sample_word_0(24'd0),.audio_sample_word_1(24'd0),.audio_sample_en(),.tmds(),.tmds_clock());
task tick; @(posedge clk); #1; endtask
task check_rtg;
if (dut.frame_width!=1344 || dut.screen_width!=1024 || dut.frame_height!=806 || dut.screen_height!=768 || dut.video_id_code!=0 || dut.hsync_pulse_start!=24 || dut.hsync_pulse_size!=136 || dut.vsync_pulse_start!=3 || dut.vsync_pulse_size!=6) $fatal(1,"RTG timing mismatch");
if (dut.true_hdmi_output.num_packets_alongside!=9) $fatal(1,"RTG packet budget");
if (dut.hsync !== !(dut.cx>=1048 && dut.cx<1184) || dut.vsync !== !(dut.cy>=771 && dut.cy<777)) $fatal(1,"Sync mismatch");
endtask
integer x,y,prev_x,prev_y;
initial begin
#1; reset=1; tick(); reset=0;
for (y=0;y<806;y=y+1) for (x=0;x<1344;x=x+1) begin
if (dut.cx!=x || dut.cy!=y) $fatal(1,"Counter mismatch at %0d,%0d: %0d,%0d",x,y,dut.cx,dut.cy);
check_rtg();
@(negedge clk);
{pal_mode,long_frame,interlace}=x%8; screen_mode=x%4;
hsync_in=~hsync_in; vsync_in=~vsync_in; offset_x=x; offset_y=y;
tick();
end
if (dut.cx!=0 || dut.cy!=0) $fatal(1,"Frame wrap");
// Return to legacy timing, then enter RTG without reset.
@(negedge clk); rtg_en=0; pal_mode=1; long_frame=1; interlace=0; screen_mode=0; hsync_in=1; vsync_in=1; offset_x=0; offset_y=0;
tick();
if (dut.frame_width!=908 || dut.screen_width!=720 || dut.frame_height!=626 || dut.screen_height!=576 || dut.video_id_code!=17) $fatal(1,"Legacy timing restore");
repeat(10) tick();
@(negedge clk); rtg_en=1;
tick(); check_rtg();
if (dut.cx!=0 || dut.cy!=0) $fatal(1,"RTG entry did not restart frame");
tick(); check_rtg();
if (dut.video_mode_changed) $fatal(1,"RTG mode change stuck");
$display("PASS: full RTG frame, ignored inputs, sync pulses, packet budget, and mode transitions"); $finish;
end
endmodule
