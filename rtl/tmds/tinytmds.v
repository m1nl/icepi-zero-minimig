// tinytmds.v
//
// Copyright (c) 2026 by Alastair M. Robinson
//
// TMDS encoder for 4 bit per channel video with hardcoded
// TMDS values.
//

module tinytmds (
	input clk,
	input reset_n,
	input hs,
	input vs,
	input blank,
	input [7:0] d,
	output reg [9:0] q
);

reg [19:0] codemux;
reg [3:0] balance;
wire dcgt = (|balance[2:0]) & ~balance[3]; // Strictly greater than zero
wire dcge = ~balance[3]; // Greater than or equal to zero

// TMDS table: Bits 19:16 and 15:12 are bit counts for the inverted
// and non-inverted versions of the codes.
// Bit 11 indicates that the code should be inverted if dcge is set
// bit 10 indicates that the code should be inverted in dcgt is set
// bits 9 to 0 are the TMDS code to be emitted (or inverted and emitted)
// (Note that bit 8 is not inverted.)

always @(*) begin
	case (d[7:4])
		4'h0 : codemux = 20'hc_5_bff; // dcge ? 16'hc_100 : 16'h5_3ff;
		4'h1 : codemux = 20'hx_0_10f;
		4'h2 : codemux = 20'hx_0_11e;
		4'h3 : codemux = 20'he_3_bee; // dcge ? 16'he_111 : 16'h3_3ee;
		4'h4 : codemux = 20'hx_0_13c;
		4'h5 : codemux = 20'hx_0_133;
		4'h6 : codemux = 20'hd_2_677; // dcgt ? 16'hd_088 : 16'h2_277;
		4'h7 : codemux = 20'hx_0_278;
		4'h8 : codemux = 20'hx_0_178;
		4'h9 : codemux = 20'hf_2_577; // dcgt ? 16'hf_388 : 16'h2_177;
		4'ha : codemux = 20'hx_0_233;
		4'hb : codemux = 20'hx_0_23c;
		4'hc : codemux = 20'he_1_8ee; // dcge ? 16'he_211 : 16'h1_0ee;
		4'hd : codemux = 20'hx_0_21e;
		4'he : codemux = 20'hx_0_20f;
		4'hf : codemux = 20'hc_3_8ff; // dcge ? 16'hc_200 : 16'h3_0ff;
		default : ;
	endcase
end

wire invert = (codemux[10] & dcgt) | (codemux[11] & dcge);
wire [3:0] dcadj = invert ? codemux[19:16] : codemux[15:12];

always @(posedge clk) begin
	if(blank) begin
		case({vs,hs})
			2'b00   : q <= 10'b1101010100;
			2'b01   : q <= 10'b0010101011;
			2'b10   : q <= 10'b0101010100;
			default : q <= 10'b1010101011;
		endcase
	end else begin
		q <= invert ? {~codemux[9],codemux[8],~codemux[7:0]} : codemux[9:0];
	end

	balance <= balance + dcadj;
	if(!reset_n)
		balance <= 4'h0;
end

endmodule
