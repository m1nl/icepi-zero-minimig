module tmds_timing_top(input clk_pixel, input [7:0] rgb,
 input [3:0] island, input [1:0] control, input [2:0] mode,
 output [9:0] tmds);
reg [7:0] rgb_r;
reg [3:0] island_r;
reg [1:0] control_r;
reg [2:0] mode_r;
always @(posedge clk_pixel) begin
 rgb_r <= rgb; island_r <= island; control_r <= control; mode_r <= mode;
end
tmds_channel dut(.clk_pixel(clk_pixel), .video_data(rgb_r),
 .data_island_data(island_r), .control_data(control_r), .mode(mode_r), .tmds(tmds));
endmodule
