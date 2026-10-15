module serializer #(parameter int NUM_CHANNELS=3)(input logic clk_pixel,clk_pixel_x5,reset,input logic [9:0] tmds_internal [NUM_CHANNELS-1:0],output logic [2:0] tmds,output logic tmds_clock);
assign tmds=0; assign tmds_clock=clk_pixel;
endmodule
