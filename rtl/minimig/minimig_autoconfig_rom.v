module minimig_autoconfig_rom
(
	input clk,
	input [3:0] d,
	input [8:0] a_read, a_write,
	input we,
	output [3:0] q
);

reg [3:0] ram[(2**9)-1:0] /* synthesis ramstyle = "auto" */;
// Set to "logic" if you don't want to use a RAM block for this.
integer j;

localparam z2base='h00;
localparam z3base='h40;
localparam z3base2='h80;
localparam z3base3='hc0;
localparam ethbase='h100;
localparam sndbase='h140;
localparam ctrlbase='h180;

initial
begin

	// Default to 1111 for any addresses not specifically set
	for(j = 0; j < 2**9; j = j+1)
		ram[j] = 4'b1111;

	// Use the upper two bits as an index
	// so 00 is ZII RAM, 01 is ZIII RAM and 10 is ETH
	// with a NULL board at 11 to terminate the chain.

	// Up to 8 meg of 24-bit Fast RAM

	ram[z2base+'h0] = 4'b1110;	// Zorro-II card, add mem, no ROM
	ram[z2base+'h2/2] = 4'b0000;	// 0110 => 2MB, 0111 => 4MB, 0000 => 8MB
	ram[z2base+'h10/2] = 4'b1110;	// Manufacturer ID: 0x139c
	ram[z2base+'h12/2] = 4'b1100;
	ram[z2base+'h14/2] = 4'b0110;
	ram[z2base+'h16/2] = 4'b0011;
	ram[z2base+'h26/2] = 4'b1110;	// Serial no: 1


	// 16 or 64 meg of 32-bit Fast RAM

	ram[z3base+'h0] = 4'b1010;	// Zorro-III card, add mem, no ROM
	ram[z3base+'h2/2] = 4'b0000;	// 8MB (extended to 16 in reg 08)
	ram[z3base+'h4/2] = 4'b1110;	// ProductID = 0x10 (only setting upper nybble)
	ram[z3base+'h8/2] = 4'b0000;	// Memory card, not silenceable, extended size (16 meg), reserved
	ram[z3base+'ha/2] = 4'b1111;	// 0000 - logical size matches physical size
	ram[z3base+'h10/2] = 4'b1110;	// Manufacturer ID: 0x139c
	ram[z3base+'h12/2] = 4'b1100;
	ram[z3base+'h14/2] = 4'b0110;
	ram[z3base+'h16/2] = 4'b0011;
	ram[z3base+'h26/2] = 4'b1101;	// Serial no: 2


	// Extra 32 meg of RAM for 64-meg platforms

	ram[z3base2+'h0] = 4'b1010;	// Zorro-III card, add mem, no ROM
	ram[z3base2+'h2/2] = 4'b0001;	// 64kb (extended to 32 meg in reg 08)
	ram[z3base2+'h4/2] = 4'b1110;	// ProductID = 0x11
	ram[z3base2+'h6/2] = 4'b1110;	// ProductID = 0x11
	ram[z3base2+'h8/2] = 4'b0000;	// Memory card, not silenceable, extended size (16 meg), reserved
	ram[z3base2+'ha/2] = 4'b1111;	// 0000 - logical size matches physical size
	ram[z3base2+'h10/2] = 4'b1110;	// Manufacturer ID: 0x1399
	ram[z3base2+'h12/2] = 4'b1100;
	ram[z3base2+'h14/2] = 4'b0110;
	ram[z3base2+'h16/2] = 4'b0110;
	ram[z3base2+'h26/2] = 4'b1011;	// Serial no: 4


	// 2 or 4 meg of 32-bit Fast RAM (unused RAM in Bank 0)

	ram[z3base3+'h0] = 4'b1010;	// Zorro-III card, add mem, no ROM
	ram[z3base3+'h2/2] = 4'b0000;	// 8MB (extended to 16 in reg 08, actual size specified in reg 0a)
	ram[z3base3+'h4/2] = 4'b1110;	// ProductID = 0x11
	ram[z3base3+'h6/2] = 4'b1110;	// ProductID = 0x11
	ram[z3base3+'h8/2] = 4'b0010;	// Memory card, not silenceable, reserved
	ram[z3base3+'ha/2] = 4'b1000;	// 0111 - 2 meg
	ram[z3base3+'h10/2] = 4'b1110;	// Manufacturer ID: 0x1399
	ram[z3base3+'h12/2] = 4'b1100;
	ram[z3base3+'h14/2] = 4'b0110;
	ram[z3base3+'h16/2] = 4'b0110;
	ram[z3base3+'h26/2] = 4'b1100;	// Serial no: 3


	// Ethernet

	ram[ethbase+'h0] = 4'b1000;	// Zorro-III card, no link, no ROM
	ram[ethbase+'h2/2] = 4'b0001;	// Next board not related, size 'h40k
	ram[ethbase+'h4/2] = 4'b1101;	// ProductID = 0x20 (only setting upper nybble)
	ram[ethbase+'h8/2] = 4'b1110;	// Not memory, silenceable, normal size, Zorro III
	ram[ethbase+'ha/2] = 4'b1101;	// logical size 'h40k
	ram[ethbase+'h10/2] = 4'b1110;	// Manufacturer ID: 0x139c
	ram[ethbase+'h12/2] = 4'b1100;
	ram[ethbase+'h14/2] = 4'b0110;
	ram[ethbase+'h16/2] = 4'b0011;
	ram[ethbase+'h26/2] = 4'b1100;	// Serial no: 3

	// Toccata sound card

	ram[sndbase+'h0] = 4'b1100;    // Zorro-II card, no link, no ROM
	ram[sndbase+'h2/2] = 4'b0001;  // Next board not related, size 'h64k
	// Inverted from here on
	ram[sndbase+'h6/2] = 4'b0011;  // Lower byte product number
	ram[sndbase+'ha/2] = 4'b1111;  // logical size matches physical size
	ram[sndbase+'h10/2] = 4'b1011; // Manufacturer ID: 0x4754
	ram[sndbase+'h12/2] = 4'b1000;
	ram[sndbase+'h14/2] = 4'b1010;
	ram[sndbase+'h16/2] = 4'b1011;

	// Minimig Control board

	ram[ctrlbase+'h0] = 4'b1100;    // Zorro-II card, no link, no ROM
	ram[ctrlbase+'h2/2] = 4'b0001;  // Next board not related, size 'h64k
	// Inverted from here on
	ram[ctrlbase+'h4/2] = 4'b1110;	// ProductID = 0x11
	ram[ctrlbase+'h6/2] = 4'b1101;	// ProductID = 0x12
	ram[ctrlbase+'ha/2] = 4'b1111;  // logical size matches physical size
	ram[ctrlbase+'h10/2] = 4'b1110;	// Manufacturer ID: 0x1399
	ram[ctrlbase+'h12/2] = 4'b1100;
	ram[ctrlbase+'h14/2] = 4'b0110;
	ram[ctrlbase+'h16/2] = 4'b0110;

end

reg [3:0] q_loc;
reg [8:0] a_loc;
always @ (posedge clk)
begin
	a_loc<=a_read;
	if (we)
		ram[a_write] <= d;
	q_loc<=ram[a_loc];
end

assign q = q_loc;

endmodule
