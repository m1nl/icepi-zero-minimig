// Usb_hid_host: A compact USB HID host core.
//
// nand2mario, 8/2023, based on work by hi631
// 
// This should support keyboard, mouse and gamepad input out of the box, over low-speed 
// USB (1.5Mbps). Just connect D+, D-, VBUS (5V) and GND, and two 15K resistors between 
// D+ and GND, D- and GND. Then provide a 12Mhz clock through usbclk.
//
// See https://github.com/nand2mario/usb_hid_host
// 

`default_nettype none 

module usb_hid_host_port #(parameter portid=0) (
    input  usbclk,	               // System clock
    input  usbrst_n,	           // reset
    input  usbtick,                // 12MHz tick
    inout  usb_dm, usb_dp,   // USB D- and D+
	output reg [15:0] q,
	output reg req,                // Toggle
	output connected
);

wire [1:0] portno = portid;

wire conerr;
wire data_rdy;          // data ready
reg  data_strobe_r, data_rdy_r;	// delayed data_strobe and data_rdy
wire data_strobe;       // data strobe for each byte
wire [7:0] ukpdat;		// actual data

wire save;			    // save dat[b] to output register r
wire [3:0] save_r;      // which register to save to
wire [3:0] save_b;      // dat[b]

ukp ukp(
	.usbrst_n(usbrst_n),
	.usbclk(usbclk),
	.usbtick(usbtick),
	.usb_dp(usb_dp),
	.usb_dm(usb_dm),
	.usb_oe(),
	.ukprdy(data_rdy),
	.ukpstb(data_strobe),
	.ukpdat(ukpdat),
	.save(save),
	.save_r(save_r),
	.save_b(save_b),
	.connected(connected),
	.conerr(conerr)
);

// Increase serial number whenever data_rdy drops
reg [3:0] serial;
always @(posedge usbclk) begin
	data_rdy_r <= data_rdy;
	if(data_rdy_r && !data_rdy)
		serial <= serial + 1;
	if(!usbrst_n)
		serial <= 0;
end

always @(posedge usbclk) begin
    data_strobe_r <= data_strobe;

	if(data_strobe && ~data_strobe_r) begin
		q <= {portno,2'b00,serial,ukpdat};
		req <=~req;
	end
	if(save) begin
		q  <= {portno,2'b01,serial,save_r,save_b};
		req <= ~req;
	end

	if(!usbrst_n)
		req <= 1'b0;
end

endmodule


