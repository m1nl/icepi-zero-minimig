`timescale 1ns/1ps
module phase_tb;
parameter integer OFFSET_PS=0;
parameter integer PIXEL_RESET=1;
reg clk5=0, clk_pixel=0, reset=1;
always #3.5 clk5=~clk5;
initial begin #(3.5+OFFSET_PS/1000.0); clk_pixel=1; forever #17.5 clk_pixel=~clk_pixel; end
wire [9:0] words[2:0];
assign words[0]=10'h155; assign words[1]=10'h2aa; assign words[2]=10'h0cc;
wire [2:0] tmds; wire tmds_clock;
serializer #(.VIDEO_RATE(28.5714)) dut(clk_pixel,clk5,reset,words,tmds,tmds_clock);
real last_pixel=0; real last_sample=0; integer loads=0;
always @(posedge clk_pixel) last_pixel=$realtime;
always @(posedge clk5) begin
if (!dut.reset_x5 && dut.bit_cnt==4 && loads<3) begin
$display("phase_ps=%0d pixel_reset=%0d load_offset_ns=%0.3f selected_input_offset_ns=%0.3f",OFFSET_PS,PIXEL_RESET,$realtime-last_pixel,last_sample-last_pixel);
loads=loads+1;
end
last_sample=$realtime;
end
initial begin
#100;
if (PIXEL_RESET) begin @(posedge clk_pixel); reset<=0; end else reset=0;
#150; $finish;
end
endmodule
