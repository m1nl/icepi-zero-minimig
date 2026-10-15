`timescale 1ns/1ps
module dynamic_tb;
parameter integer OFFSET_PS=0;
parameter integer HALF_PS=3500;
reg clk5=0, clk_pixel=0, reset=1;
always #(HALF_PS/1000.0) clk5=~clk5;
initial begin #((HALF_PS+OFFSET_PS)/1000.0); clk_pixel=1; forever #(5.0*HALF_PS/1000.0) clk_pixel=~clk_pixel; end
reg [9:0] source[2:0]; wire [9:0] words[2:0];
assign words[0]=source[0]; assign words[1]=source[1]; assign words[2]=source[2];
integer seq=0;
always @(posedge clk_pixel) begin
seq=seq+1;
source[0]<=seq; source[1]<=seq^10'h2aa; source[2]<=seq^10'h155;
end
wire [2:0] tmds; wire tmds_clock;
serializer #(.VIDEO_RATE(28.5714)) dut(clk_pixel,clk5,reset,words,tmds,tmds_clock);
reg [9:0] expected0[0:200], expected1[0:200], expected2[0:200];
reg [9:0] received[2:0];
integer written=0,readptr=0,bit_index=-1,frames=0,last_seq=-1,cycle=0;
integer load_cycle[0:200];
reg previous_clock=0;
always @(posedge clk5) begin
cycle=cycle+1;
if (!dut.reset_x5 && dut.bit_cnt==4) begin
expected0[written]=words[0];
expected1[written]=words[1];
expected2[written]=words[2];
load_cycle[written]=cycle;
if(last_seq>=0 && words[0] !== ((last_seq+1)&1023)) $fatal(1,"Skipped/repeated pixel");
last_seq=words[0];
written=written+1;
end
end
always @(clk5) begin
#0.01;
if (!dut.reset_x5) begin
if(tmds_clock && !previous_clock) begin
bit_index=0;
if(cycle-load_cycle[readptr]!=4) $fatal(1,"Unexpected load-to-output latency %0d",cycle-load_cycle[readptr]);
end
if(bit_index>=0) begin
received[0][bit_index]=tmds[0]; received[1][bit_index]=tmds[1]; received[2][bit_index]=tmds[2];
if(bit_index==9) begin
if(received[0]!==expected0[readptr] || received[1]!==expected1[readptr] || received[2]!==expected2[readptr]) $fatal(1,"Serialized word mismatch");
frames=frames+1; readptr=readptr+1; bit_index=-1;
end else bit_index=bit_index+1;
end
end
previous_clock=tmds_clock;
end
initial begin
source[0]=0; source[1]=10'h2aa; source[2]=10'h155;
#100; @(posedge clk_pixel); reset<=0;
#1000;
if(frames<20) $fatal(1,"Missing frames");
$display("PASS dynamic words half_ps=%0d phase_ps=%0d frames=%0d latency=4 fast cycles",HALF_PS,OFFSET_PS,frames); $finish;
end
endmodule
