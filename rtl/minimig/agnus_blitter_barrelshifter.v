//Blitter barrel shifter
//This module can shift 0-15 positions to the right (normal mode) or to the left (descending mode).
//Multipliers are used to save logic.


module agnus_blitter_barrelshifter
(
	input	desc,			// select descending mode (shift to the left)
	input	[3:0] shift,	// shift value (0 to 15)
	input 	[15:0] new_val,		// barrel shifter data in
	input 	[15:0] old_val,		// barrel shifter data in
	output	[15:0] out		// barrel shifter data out
);

wire [31:0] shifted_new;	// shifted new data
wire [31:0] shifted_old;	// shifted old data
reg  [17:0] shift_onehot;	// one-hot shift value for multipliers

//one-hot shift value encoding
always @(desc or shift)
	case ({desc,shift[3:0]})
		5'h00 : shift_onehot = 18'h10000;
		5'h01 : shift_onehot = 18'h08000;
		5'h02 : shift_onehot = 18'h04000;
		5'h03 : shift_onehot = 18'h02000;
		5'h04 : shift_onehot = 18'h01000;
		5'h05 : shift_onehot = 18'h00800;
		5'h06 : shift_onehot = 18'h00400;
		5'h07 : shift_onehot = 18'h00200;
		5'h08 : shift_onehot = 18'h00100;
		5'h09 : shift_onehot = 18'h00080;
		5'h0A : shift_onehot = 18'h00040;
		5'h0B : shift_onehot = 18'h00020;
		5'h0C : shift_onehot = 18'h00010;
		5'h0D : shift_onehot = 18'h00008;
		5'h0E : shift_onehot = 18'h00004;
		5'h0F : shift_onehot = 18'h00002;
		5'h10 : shift_onehot = 18'h00001;
		5'h11 : shift_onehot = 18'h00002;
		5'h12 : shift_onehot = 18'h00004;
		5'h13 : shift_onehot = 18'h00008;
		5'h14 : shift_onehot = 18'h00010;
		5'h15 : shift_onehot = 18'h00020;
		5'h16 : shift_onehot = 18'h00040;
		5'h17 : shift_onehot = 18'h00080;
		5'h18 : shift_onehot = 18'h00100;
		5'h19 : shift_onehot = 18'h00200;
		5'h1A : shift_onehot = 18'h00400;
		5'h1B : shift_onehot = 18'h00800;
		5'h1C : shift_onehot = 18'h01000;
		5'h1D : shift_onehot = 18'h02000;
		5'h1E : shift_onehot = 18'h04000;
		5'h1F : shift_onehot = 18'h08000;
 	endcase

`ifdef MINIMIG_ECP5_BLITTER_DSP
// Combinational DSP: preserve the existing blitter cycle timing.
// Cascade inputs, unused clocks and product bits 35:32 are unconnected.
MULT18X18D #(
    .REG_INPUTA_CLK("NONE"),
    .REG_INPUTB_CLK("NONE"),
    .REG_INPUTC_CLK("NONE"),
    .REG_PIPELINE_CLK("NONE"),
    .REG_OUTPUT_CLK("NONE"),
    .GSR("DISABLED")
) shifted_new_dsp (
    .A0(new_val[0]), .A1(new_val[1]), .A2(new_val[2]), .A3(new_val[3]),
    .A4(new_val[4]), .A5(new_val[5]), .A6(new_val[6]), .A7(new_val[7]),
    .A8(new_val[8]), .A9(new_val[9]), .A10(new_val[10]), .A11(new_val[11]),
    .A12(new_val[12]), .A13(new_val[13]), .A14(new_val[14]), .A15(new_val[15]),
    .A16(1'b0), .A17(1'b0), .B0(shift_onehot[0]), .B1(shift_onehot[1]),
    .B2(shift_onehot[2]), .B3(shift_onehot[3]), .B4(shift_onehot[4]), .B5(shift_onehot[5]),
    .B6(shift_onehot[6]), .B7(shift_onehot[7]), .B8(shift_onehot[8]), .B9(shift_onehot[9]),
    .B10(shift_onehot[10]), .B11(shift_onehot[11]), .B12(shift_onehot[12]), .B13(shift_onehot[13]),
    .B14(shift_onehot[14]), .B15(shift_onehot[15]), .B16(shift_onehot[16]), .B17(shift_onehot[17]),
    .C0(1'b0), .C1(1'b0), .C2(1'b0), .C3(1'b0),
    .C4(1'b0), .C5(1'b0), .C6(1'b0), .C7(1'b0),
    .C8(1'b0), .C9(1'b0), .C10(1'b0), .C11(1'b0),
    .C12(1'b0), .C13(1'b0), .C14(1'b0), .C15(1'b0),
    .C16(1'b0), .C17(1'b0), .P0(shifted_new[0]), .P1(shifted_new[1]),
    .P2(shifted_new[2]), .P3(shifted_new[3]), .P4(shifted_new[4]), .P5(shifted_new[5]),
    .P6(shifted_new[6]), .P7(shifted_new[7]), .P8(shifted_new[8]), .P9(shifted_new[9]),
    .P10(shifted_new[10]), .P11(shifted_new[11]), .P12(shifted_new[12]), .P13(shifted_new[13]),
    .P14(shifted_new[14]), .P15(shifted_new[15]), .P16(shifted_new[16]), .P17(shifted_new[17]),
    .P18(shifted_new[18]), .P19(shifted_new[19]), .P20(shifted_new[20]), .P21(shifted_new[21]),
    .P22(shifted_new[22]), .P23(shifted_new[23]), .P24(shifted_new[24]), .P25(shifted_new[25]),
    .P26(shifted_new[26]), .P27(shifted_new[27]), .P28(shifted_new[28]), .P29(shifted_new[29]),
    .P30(shifted_new[30]), .P31(shifted_new[31]), .SIGNEDA(1'b0), .SIGNEDB(1'b0),
    .SOURCEA(1'b0), .SOURCEB(1'b0), .CLK0(1'b0), .CE0(1'b1),
    .RST0(1'b0)
);

// Combinational DSP: preserve the existing blitter cycle timing.
// Cascade inputs, unused clocks and product bits 35:32 are unconnected.
MULT18X18D #(
    .REG_INPUTA_CLK("NONE"),
    .REG_INPUTB_CLK("NONE"),
    .REG_INPUTC_CLK("NONE"),
    .REG_PIPELINE_CLK("NONE"),
    .REG_OUTPUT_CLK("NONE"),
    .GSR("DISABLED")
) shifted_old_dsp (
    .A0(old_val[0]), .A1(old_val[1]), .A2(old_val[2]), .A3(old_val[3]),
    .A4(old_val[4]), .A5(old_val[5]), .A6(old_val[6]), .A7(old_val[7]),
    .A8(old_val[8]), .A9(old_val[9]), .A10(old_val[10]), .A11(old_val[11]),
    .A12(old_val[12]), .A13(old_val[13]), .A14(old_val[14]), .A15(old_val[15]),
    .A16(1'b0), .A17(1'b0), .B0(shift_onehot[0]), .B1(shift_onehot[1]),
    .B2(shift_onehot[2]), .B3(shift_onehot[3]), .B4(shift_onehot[4]), .B5(shift_onehot[5]),
    .B6(shift_onehot[6]), .B7(shift_onehot[7]), .B8(shift_onehot[8]), .B9(shift_onehot[9]),
    .B10(shift_onehot[10]), .B11(shift_onehot[11]), .B12(shift_onehot[12]), .B13(shift_onehot[13]),
    .B14(shift_onehot[14]), .B15(shift_onehot[15]), .B16(shift_onehot[16]), .B17(shift_onehot[17]),
    .C0(1'b0), .C1(1'b0), .C2(1'b0), .C3(1'b0),
    .C4(1'b0), .C5(1'b0), .C6(1'b0), .C7(1'b0),
    .C8(1'b0), .C9(1'b0), .C10(1'b0), .C11(1'b0),
    .C12(1'b0), .C13(1'b0), .C14(1'b0), .C15(1'b0),
    .C16(1'b0), .C17(1'b0), .P0(shifted_old[0]), .P1(shifted_old[1]),
    .P2(shifted_old[2]), .P3(shifted_old[3]), .P4(shifted_old[4]), .P5(shifted_old[5]),
    .P6(shifted_old[6]), .P7(shifted_old[7]), .P8(shifted_old[8]), .P9(shifted_old[9]),
    .P10(shifted_old[10]), .P11(shifted_old[11]), .P12(shifted_old[12]), .P13(shifted_old[13]),
    .P14(shifted_old[14]), .P15(shifted_old[15]), .P16(shifted_old[16]), .P17(shifted_old[17]),
    .P18(shifted_old[18]), .P19(shifted_old[19]), .P20(shifted_old[20]), .P21(shifted_old[21]),
    .P22(shifted_old[22]), .P23(shifted_old[23]), .P24(shifted_old[24]), .P25(shifted_old[25]),
    .P26(shifted_old[26]), .P27(shifted_old[27]), .P28(shifted_old[28]), .P29(shifted_old[29]),
    .P30(shifted_old[30]), .P31(shifted_old[31]), .SIGNEDA(1'b0), .SIGNEDB(1'b0),
    .SOURCEA(1'b0), .SOURCEB(1'b0), .CLK0(1'b0), .CE0(1'b1),
    .RST0(1'b0)
);
`else
// Portable implementation for targets without the ECP5 DSP define.
assign shifted_new = {2'b00, new_val} * shift_onehot;
assign shifted_old = {2'b00, old_val} * shift_onehot;
`endif

assign out = desc ? shifted_new[15:0] | shifted_old[31:16] : shifted_new[31:16] | shifted_old[15:0];


endmodule

