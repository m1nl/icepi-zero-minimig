// Xilinx-style (word-based) colour table RAM with byte enables, for simulation

`timescale 1 ps / 1 ps

module denise_colortable_ram_mf (
	input [32/8-1:0] byteena_a,
	input clock,
	input [32-1:0] data,
	input enable,
	input [8-1:0] rdaddress,
	input [8-1:0] wraddress,
	input wren,
	output [32-1:0] q
);

colortable_ram colortable (
	.WrAddress(wraddress),
	.RdAddress(rdaddress),
	.Data(data),
	.ByteEn(byteena_a),
	.WE(wren),
	.RdClock(clock), 
    .RdClockEn(enable),
	.Reset(1'b0),
	.WrClock(clock),
	.WrClockEn(enable),
	.Q(q)
);

//reg [32-1:0] storage[0:2**8-1];

//reg [31:0] q_r;

//always @(posedge clock) begin
//	if(wren) begin
//		if(byteena_a[0])
//			storage[wraddress][7:0]<=data[7:0];
//		if(byteena_a[1])
//			storage[wraddress][15:8]<=data[15:8];
//		if(byteena_a[2])
//			storage[wraddress][23:16]<=data[23:16];
//		if(byteena_a[3])
//			storage[wraddress][31:24]<=data[31:24];
//	end
//	if(enable)
//		q_r<=storage[rdaddress];
//end

//assign q = q_r;

endmodule
