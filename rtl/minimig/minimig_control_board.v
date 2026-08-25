module minimig_control_board (
  input clk,
  input rst,
  input [15:0] data_in,
  output reg [15:0] data_out,
  input [15:1] addr,
  input rd,
  input hwr,
  input lwr,
  input sel,
  input audio_overflow,
  output [7:0] vol1,
  output [7:0] vol2,
  output [7:0] vol3,
  output [7:0] vol4,
  output [7:0] vol5,
  output swap_channels,
  output sermidi,
  output drivesound_fdd,
  output drivesound_hdd,
  output track_vsync
);

reg swap_channels_i = 1'b0;
reg sermidi_i = 1'b1;
reg track_vsync_i =1'b0;
reg drivesound_fdd_i= 1'b0;
reg drivesound_hdd_i= 1'b0;
reg [7:0] vol1_i = 8'h80;
reg [7:0] vol2_i = 8'h80;
reg [7:0] vol3_i = 8'h80;
reg [7:0] vol4_i = 8'h80;
reg [7:0] vol5_i = 8'h80;

assign swap_channels = swap_channels_i;
assign sermidi=sermidi_i;
assign track_vsync=track_vsync_i;
assign drivesound_fdd=drivesound_fdd_i;
assign drivesound_hdd=drivesound_hdd_i;
assign vol1=vol1_i;
assign vol2=vol2_i;
assign vol3=vol3_i;
assign vol4=vol4_i;
assign vol5=vol5_i;

reg aud_overflow_latched;

always @(posedge clk) begin
	if(sel && lwr) begin
		case (addr[8:1])
			8'h00: begin
				sermidi_i <= data_in[0];
				track_vsync_i <= data_in[1];
			end
			8'h01: {drivesound_hdd_i,drivesound_fdd_i} <= data_in[1:0];
			8'h02: swap_channels_i <= data_in[0];
			8'h06: aud_overflow_latched<= 1'b0;
			8'h08: vol1_i <= data_in[7:0];
			8'h09: vol2_i <= data_in[7:0];
			8'h0a: vol3_i <= data_in[7:0];
			8'h0b: vol4_i <= data_in[7:0];
			8'h0c: vol5_i <= data_in[7:0];
			default: ;
		endcase
	end
	if(audio_overflow)
		aud_overflow_latched <= 1'b1;
end

`ifdef MINIMIG_AUX_AUDIO
wire have_16bitaudio=1'b1;
`else
wire have_16bitaudio=1'b0;
`endif

`ifdef MINIMIG_DRIVESOUNDS
wire have_drivesounds=1'b1;
`else
wire have_drivesounds=1'b0;
`endif

`ifdef MINIMIG_TOCCATA
wire have_toccata=1'b1;
`else
wire have_toccata=1'b0;
`endif

`ifdef MINIMIG_USE_MIDI_PINS
wire have_serialmidi=1'b1;
`else
wire have_serialmidi=1'b0;
`endif

`ifdef MINIMIG_SIDI128_EXPANSION
wire have_track_vsync=1'b1;
`else
wire have_track_vsync=1'b0;
`endif

wire [15:0] capabilities;
assign capabilities={have_serialmidi,have_track_vsync,9'b0,have_drivesounds,have_16bitaudio,1'b1,have_toccata,1'b1};


always @(posedge clk) begin
	if(sel && rd) begin
		case (addr[8:1])
			8'h00:   data_out <= {14'h0,track_vsync_i,sermidi_i};
			8'h01:   data_out <= {14'h0,drivesound_hdd_i,drivesound_fdd_i};
			8'h02:   data_out <= {15'h0,swap_channels_i};
			8'h06:   data_out <= {15'h0,aud_overflow_latched};
			8'h07:   data_out <= capabilities; // sermidi enable, bit mask for audio channels
			8'h08:   data_out <= {8'h00,vol1_i};
			8'h09:   data_out <= {8'h00,vol2_i};
			8'h0a:   data_out <= {8'h00,vol3_i};
			8'h0b:   data_out <= {8'h00,vol4_i};
			8'h0c:   data_out <= {8'h00,vol5_i};
			default:
				;
		endcase
	end else
		data_out <= 16'h0000;	

end

endmodule
