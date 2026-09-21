// Stereo Hybrid PWM / Sigma Delta converter
//
// Uses 5-bit PWM, wrapped within a 10-bit Sigma Delta, with the intention of
// increasing the pulse width, since narrower pulses seem to equate to more noise
//
// Copyright 2012, 2020, 2021, 2024 by Alastair M. Robinson
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that they will
// be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>
//

module hybrid_pwm_sd #(
	parameter ANTI_POP = 0
) (
	input clk,
	input terminate,
	input [15:0] d_l,
	input [15:0] d_r,
	output reg q_l,
	output reg q_r
);


// PWM portion of the DAC - a 5-bit counter - restarts at 1 rather than 0
// since the input is the number of consecutive 1 bits, from 0 to 31,
// the loop is thus 31 cycles, not 32.

reg [4:0] pwmcounter=5'b11111;
reg [4:0] pwmthreshold_l = 5'd30;
reg [4:0] pwmthreshold_r = 5'd30;

always @(posedge clk) begin
	pwmcounter<=pwmcounter+5'b1;

	if(pwmcounter==pwmthreshold_l)
		q_l<=1'b0;

	if(pwmcounter==pwmthreshold_r)
		q_r<=1'b0;

	if(pwmcounter==5'b11111)
	begin
		q_l<=|pwmthreshold_l;
		q_r<=|pwmthreshold_r;
		pwmcounter<=5'b1;
	end

end


// Anti-pop - at power-on ramp smoothly from near-maximum to midpoint,
// then cut over to the core's audio output.

// After initialisation, the terminate input going high
// will prompt a ramp back up to maximum to avoid a pop
// on core-change.

reg term_ena=1'b0;
wire terminated = terminate & term_ena;

reg [13:0] initctr = 14'h3e00;
wire init = initctr[13];
reg [13:0] initctr_l = 14'h3e00;
reg dump;

always @(posedge clk) begin
	if(init && dump) begin
		initctr_l<=initctr; // Lags one step behind to avoid wrapping from max -> 0 on terminate
		if(terminate && term_ena)
			initctr <= initctr+1'd1;	// Increase the counter on termination
		else
			initctr <= initctr-1'd1;	// Decrease the counter on power-on
	end
	if(!init && terminate)
		term_ena<=1'b1;	// Termination can't start until init is complete.
	if(!init && terminate && !term_ena)
		initctr <= initctr+1'd1;	// Kick-start the termination, setting initctr[13]
end

// Periodic dumping of the accumulator to kill standing tones.
// Yes, I know, yuck.  In practice it works better than would be expected.
reg [7:0] dumpcounter;

always @(posedge clk) begin
	dump <=1'b0;
	if(pwmcounter==5'b11111)
	begin
		dumpcounter<=dumpcounter+1'd1;
		dump<=dumpcounter==0 ? 1'b1 : 1'b0;
	end
end


// The Sigma Delta portion of the DAC

// The most expensive part, the multiply-and-add (which Quartus implements
// as shift-and-add due to the fixed factor) is multiplexed between the left
// and right channels, switching between the two every time the counters are reloaded.

reg [33:0] scaledin = 34'hF0000000;
reg [15:0] sigma_l = 16'hf000;
reg [15:0] sigma_r = 16'hf000;

reg muxtoggle;

reg [15:0] mux_in;

generate
	if (ANTI_POP) begin
		always @(posedge clk)
		    mux_in <= (init | terminated) ? {initctr_l[13:0],2'b00} : ( muxtoggle ? d_r : d_l );
	end else begin
		always @(*)
		    mux_in = terminated ? 16'b0 : ( muxtoggle ? d_r : d_l );
	end
endgenerate

always @(posedge clk) begin
	if(pwmcounter==5'b11110) // Update thresholds just before PWM cycle ends
	begin
		scaledin<=33'h8000000 // (1<<(16-5))<<16     offset to keep centre aligned.
			+({1'b0,mux_in}*16'hf000); // + d_l * 30<<(16-5);

		// Pick a new PWM threshold using a Sigma Delta
		if(muxtoggle) begin
			sigma_l<=scaledin[31:16]+{5'b00000,sigma_l[10:0]};	// Will use previous iteration's scaledin value
			pwmthreshold_l<=sigma_l[15:11]; // Will lag 2 cycles behind, but shouldn't matter.
		end else begin
			sigma_r<=scaledin[31:16]+{5'b00000,sigma_r[10:0]};	// Will use previous iteration's scaledin value
			pwmthreshold_r<=sigma_r[15:11]; // Will lag 2 cycles behind, but shouldn't matter.
		end

		muxtoggle<=!muxtoggle;
	end

	if(dump)	// dump the accumulator
	begin
		sigma_l[10:0]<=11'b100_00000000;
		sigma_r[10:0]<=11'b100_00000000;
	end
end

endmodule
