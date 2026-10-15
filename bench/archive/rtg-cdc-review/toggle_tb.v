`timescale 1ns/1ps
module toggle_tb;
reg sys=0,vid=0,reset_n=0,video_reset=1,sof=0,vb=0;
always #4.375 sys=~sys;
always #7.575757 vid=~vid;
rtg_video dut(.clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_ena(1'b0),.video_reset(video_reset),
.frame_start_toggle(sof),.vblank_start_toggle(vb),.pixel_x(11'd1100),.pixel_y(10'd800),
.reg_addr(11'd0),.reg_wr(1'b0),.reg_req(1'b0),.reg_d(16'd0),.fetch_d(16'd0),.fetch_ack(1'b0),.fetch_fill(1'b0));
integer sys_events=0,rtg_events=0;
always @(posedge sys) if(reset_n && !video_reset && dut.frame_start) sys_events=sys_events+1;
always @(posedge vid) if(reset_n && !video_reset && dut.frame_start_rtg) rtg_events=rtg_events+1;
initial begin
#100;reset_n=1;
repeat(8) @(negedge sys);
video_reset=0;
repeat(8) @(negedge vid);
sof=1;
repeat(10) @(negedge vid);
$display("frame toggle: sys event cycles=%0d rtg event cycles=%0d rtg pulse=%b seen=%b sync=%b",sys_events,rtg_events,dut.frame_start_rtg,dut.frame_start_rtg_seen,dut.frame_start_rtg_sync);
if(sys_events!=1 || rtg_events!=1 || dut.frame_start_rtg!==0) $fatal(1,"one frame toggle must produce exactly one event per receiving domain");
$finish;
end
endmodule
