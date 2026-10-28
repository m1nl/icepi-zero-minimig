//syscontrol handles the startup of the FGPA,
//after fpga config, it automatically does a global system reset and asserts boot.
//the boot signal puts gary in a special mode so that the bootrom
//is mapped into the system memory map.	The firmware in the bootrom
//then loads the kickstart via the diskcontroller into the kickstart ram area.
//When kickstart has been loaded, the bootrom asserts bootdone by selecting both cia's at once.
//This resets the system for a second time but it also de-asserts boot.
//Thus, the system now boots as a regular amiga.
//Subsequent resets by asserting mrst will not assert boot again.
//
// JB:
// 2008-07-11	- reset to bootloader
// 2009-03-13	- shorter reset
// 2009-08-17	- reset generator modification


module minimig_syscontrol
(
	input	clk,			// bus clock
	input	clk7_en,		// 7MHz clock enable
	input	cnt,			// pulses for counting
	input	mrstn,			// master/user reset input
	output	reset			// global synchronous system reset
);

reg [7:0] rstn_sync = 8'b0;

always @(posedge clk, negedge mrstn) begin
  if (!mrstn)
    rstn_sync <= 8'b0;
`ifdef VERILATOR
  else if (clk7_en)
`else
  else if (clk7_en && cnt)
`endif
    rstn_sync <= {rstn_sync[6:0], 1'b1};
end

wire rstn = rstn_sync[7];

// global reset output
assign reset = ~rstn;

endmodule

