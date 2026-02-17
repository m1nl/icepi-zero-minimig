module frac_pulse #(
	parameter freq_in = 50,
	parameter freq_out = 12,
	parameter counterwidth=16
) (
	input clk,
	input reset_n,
	output q
);

reg [counterwidth:0] counter;

always @(posedge clk) begin

	if(counter[counterwidth])
		counter <= counter + freq_in - freq_out;
	else
		counter <= counter - freq_out;
		
	if(!reset_n)
		counter <=freq_in;
end

assign q = counter[counterwidth];

endmodule

