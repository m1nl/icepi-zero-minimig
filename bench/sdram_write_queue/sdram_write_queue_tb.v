`timescale 1ns/1ps
module sdram_write_queue_tb;
	reg clk=0;
	always #4.386 clk=~clk;
	reg rst=1, source_reset=0, req=0, ready=0;
	reg [25:1] addr=0;
	reg [31:0] data=0;
	reg [3:0] dqm=15;
	wire ack, valid;
	wire [25:1] head_addr;
	wire [31:0] head_data;
	wire [3:0] head_dqm;
	sdram_write_queue dut (.*);
	task tick;
		begin @(posedge clk); #2; end
	endtask
	task offer(input [25:1] a, input [31:0] d, input [3:0] m);
		begin
			@(negedge clk); addr=a; data=d; dqm=m; req=~req;
			tick;
			if(ack!==req) $fatal(1,"unexpected backpressure");
		end
	endtask
	task expect_head(input [25:1] a, input [31:0] d, input [3:0] m);
		begin
			if(!valid || head_addr!==a || head_data!==d || head_dqm!==m)
				$fatal(1,"head got %h/%h/%h expected %h/%h/%h",head_addr,head_data,head_dqm,a,d,m);
		end
	endtask
	integer i;
	initial begin
		tick; @(negedge clk); rst=0;
		offer(25'd16,32'h11223344,4'b0000);
		offer(25'd16,32'hffffaaff,4'b1101);
		expect_head(25'd16,32'h1122aa44,0);
		if(dut.count!=1) $fatal(1,"same-address writes did not merge");
		// Unselected bytes retain their masks until supplied by a later write.
		offer(25'd18,32'h01020304,4'b1110);
		offer(25'd18,32'h55667788,4'b0111);
		@(negedge clk); ready=1; tick;
		expect_head(25'd18,32'h55020304,4'b0110);
		// Simultaneous pop and same-address request must not mutate popped data.
		@(negedge clk); addr=18; data=32'haabbccdd; dqm=0; req=~req;
		tick; @(negedge clk); ready=0;
		expect_head(25'd18,32'haabbccdd,0);
		offer(25'd20,32'd20,0); offer(25'd22,32'd22,0); offer(25'd24,32'd24,0);
		if(dut.count!=4) $fatal(1,"queue did not fill");
		// Merging into a full queue still acknowledges.
		offer(25'd24,32'h12345678,0);
		@(negedge clk); addr=26; data=26; req=~req;
		tick; if(ack===req) $fatal(1,"full queue acknowledged distinct address");
		// Pop/push at full capacity, followed by pointer wrap.
		@(negedge clk); ready=1; tick;
		if(ack!==req || dut.count!=4) $fatal(1,"simultaneous full pop/push failed");
		expect_head(25'd20,32'd20,0);
		tick; expect_head(25'd22,32'd22,0);
		tick; expect_head(25'd24,32'h12345678,0);
		tick; expect_head(25'd26,32'd26,0);
		tick; if(valid) $fatal(1,"queue did not drain");
		@(negedge clk); ready=0;
		// A,B,A must remain three entries: do not reorder across another address.
		offer(25'd30,32'd1,0); offer(25'd32,32'd2,0); offer(25'd30,32'd3,0);
		if(dut.count!=3) $fatal(1,"merge reordered intervening address");
		@(negedge clk); source_reset=1; req=0; tick;
		if(ack!==0 || dut.count!=3) $fatal(1,"source reset lost posted writes");
		@(negedge clk); source_reset=0; ready=1;
		tick; expect_head(25'd32,32'd2,0);
		tick; expect_head(25'd30,32'd3,0); tick;
		@(negedge clk); ready=0;
		for(i=0;i<20;i=i+1) begin
			offer(i,32'h87654321+i,0);
			expect_head(i,32'h87654321+i,0);
			@(negedge clk); ready=1; tick; @(negedge clk); ready=0;
		end
		offer(25'd40,32'd4,0);
		@(negedge clk); rst=1; req=0; tick;
		if(valid || ack!==0) $fatal(1,"SDRAM reset did not clear queue");
		$display("PASS: queue merging, masks, ordering, full backpressure, wrap, simultaneous transfers and resets");
		$finish;
	end
	initial begin #100000; $fatal(1,"queue timeout"); end
endmodule
