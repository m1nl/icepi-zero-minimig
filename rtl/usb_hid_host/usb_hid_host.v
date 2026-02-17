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

module usb_hid_host #(parameter fifodepth = 6) (
    input  usbclk,	                // 12MHz clock
    input  usbrst_n,	            // reset
    input  usbtick,
    inout  [1:0] usb_dm, usb_dp,    // USB D- and D+

    output atn,                     // High when FIFO contains data
                                    // key_*, mouse_*, game_* valid depending on typ
    output [1:0] connected,         // connection or protocol error

	output reg [15:0] q,
	input ack
);


wire [15:0] q0,q1;
wire req0,req1;

usb_hid_host_port #(
	.portid(0)
) port0 (
	.usbclk(usbclk),
	.usbrst_n(usbrst_n),
	.usbtick(usbtick),
	.usb_dm(usb_dm[0]),
	.usb_dp(usb_dp[0]),
	.q(q0),
	.req(req0),
	.connected(connected[0])
);

usb_hid_host_port #(
	.portid(1)
) port1 (
	.usbclk(usbclk),
	.usbrst_n(usbrst_n),
	.usbtick(usbtick),
	.usb_dm(usb_dm[1]),
	.usb_dp(usb_dp[1]),
	.q(q1),
	.req(req1),
	.connected(connected[1])
);


// FIFO for USB data
reg [15:0] fifo_storage [2**fifodepth];
reg [fifodepth-1:0] rdptr=0;
reg [fifodepth-1:0] wrptr=0;
reg [fifodepth-1:0] wrptr_next=1;

wire fifo_empty = rdptr==wrptr ? 1'b1 : 1'b0;
wire fifo_full = rdptr==wrptr_next ? 1'b1 : 1'b0;
reg fifo_wr;
reg [15:0] fifo_d;

reg ack0,ack1;

always @(posedge usbclk) begin
	if(ack && !fifo_empty)
		rdptr<=rdptr + 1;

	if(!fifo_full) begin	
		if(req0!=ack0) begin
			fifo_storage[wrptr] <= q0;
			wrptr <= wrptr_next;
			wrptr_next <= wrptr_next+1;
			ack0 <= req0;
		end else if (req1!=ack1) begin
			fifo_storage[wrptr] <= q1;
			wrptr <= wrptr_next;
			wrptr_next <= wrptr_next+1;
			ack1 <= req1;
		end
	end

	if(!usbrst_n) begin
		rdptr<=0;
		wrptr<=0;
		wrptr_next<=1;
		ack0 <= 1'b0;
		ack1 <= 1'b0;
	end
	
	q <= fifo_storage[rdptr];

end

assign atn = ~fifo_empty;	

endmodule

