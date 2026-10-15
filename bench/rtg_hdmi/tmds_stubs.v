// Timing tests stop at the HDMI encoder input; physical TMDS serialization is excluded.
module tmds_channel #(parameter CN=0)(input clk_pixel,input [7:0] video_data,
    input [3:0] data_island_data,input [1:0] control_data,input [2:0] mode,output [9:0] tmds);
assign tmds=0;
endmodule
module serializer #(parameter NUM_CHANNELS=3,parameter real VIDEO_RATE=0)
    (input clk_pixel,input clk_pixel_x5,input reset,
    input [9:0] tmds_internal [NUM_CHANNELS-1:0],output [2:0] tmds,output tmds_clock);
assign tmds=0;assign tmds_clock=clk_pixel;
endmodule
