`timescale 1ns/1ps
// Real production cache + controller + queue. Behavioral memory checks returned
// CPU values; pin-command timing is checked separately in sdram_queued_ctrl_tb.
module sdram_readback_tb #(parameter QUEUED=1);
	reg clk=0;
	always #4.386 clk=~clk;
	reg [3:0] div=0;
	always @(posedge clk) div<=div+1'b1;
	reg reset_n=0, rtgce=0;
	reg [4:0] state=5'b00101;
	reg [25:1] address=25'h0400000;
	reg [15:0] wr=0, wr_lo=0;
	reg pair=0;
	reg [1:0] bs=3;
	wire ready, ack;
	wire [15:0] rd, rd_hi;
	wire [12:0] a;
	wire [1:0] bank, dqm;
	wire [3:0] cs;
	wire we, ras, cas;
	tri [15:0] dq;
	reg [15:0] read_data=0;
	reg read_drive=0;
	assign dq=read_drive ? read_data : 16'bz;
	sdram_ctrl #(.addr_max_bits(25), .cpu_write_queue(QUEUED)) dut (
		.sysclk(clk), .clk7_en(&div[3:2]), .clk28_en(div[1:0]==0),
		.reset_in(reset_n), .cache_rst(reset_n), .reset_out(ready),
		.cache_inhibit(1'b1), .cacheline_clr(1'b0), .cpu_cache_ctrl(4'd0),
		.sdaddr(a), .sd_cs(cs), .ba(bank), .sd_we(we), .sd_ras(ras), .sd_cas(cas), .dqm(dqm), .sdata(dq),
		.hostWR(32'd0), .hostAddr(24'd0), .hostce(1'b0), .hostwe(1'b0), .hostinterrupt(1'b0),
		.hostbytesel(4'd0), .hostRD(), .hostena(),
		.chipAddr(23'd0), .chipL(1'b0), .chipU(1'b0), .chipL2(1'b0), .chipU2(1'b0),
		.chipRW(1'b1), .chip_dma(1'b1), .chipWR(16'd0), .chipWR2(16'd0), .chipRD(), .chip48(),
		.rtgAddr(26'h0800000), .rtgce(rtgce), .rtgpri(rtgce), .rtg_extend_ok(1'b0),
		.rtgack(), .rtgfill(), .rtgRd(), .audAddr(23'd0), .audce(1'b0), .audack(), .audfill(), .audRd(),
		.cpuAddr(address), .cpustate(state), .cpuL(!bs[0]), .cpuU(!bs[1]),
		.cpu_long_cand(pair), .cpuWR_lo(wr_lo), .cpuRD_hi(rd_hi), .cpuWR(wr), .cpuRD(rd),
		.enaWRreg(), .ena7RDreg(), .ena7WRreg(), .cpuena(ack)
	);
	reg [15:0] memory [0:511];
	integer delay_left=0, beats_left=0, column=0, first_column=0, n, writes=0, cpu_reads=0;
	always @(negedge clk) if(ready) begin
		if(beats_left!=0) begin
			read_data <= #1 memory[(first_column & ~7) | (column & 7)];
			read_drive <= #1 1;
			column=column+1; beats_left=beats_left-1;
		end else read_drive <= #1 0;
		if(delay_left!=0) begin
			delay_left=delay_left-1;
			if(delay_left==0) begin
				read_data <= #1 memory[first_column]; read_drive <= #1 1;
				column=first_column+1; beats_left=7;
			end
		end
		if(!cs[0] && {ras,cas,we}==3'b100) begin
			if(bank!=1) $fatal(1,"unexpected write bank");
			if(!dqm[0]) memory[a[8:0]][7:0]=dq[7:0];
			if(!dqm[1]) memory[a[8:0]][15:8]=dq[15:8];
			writes=writes+1;
		end
		if(!cs[0] && {ras,cas,we}==3'b101) begin
			first_column=a[8:0]; delay_left=3;
			if(dut.slot1_type==2 || dut.slot2_type==2) begin
				if(QUEUED && dut.cpu_writes_busy) $fatal(1,"read bypassed pending writes");
				cpu_reads=cpu_reads+1;
			end
		end
	end
	task tick;
		begin @(posedge clk); #2; end
	endtask
	task access_cpu(input integer offset, input integer writing, input integer paired,
	                input [15:0] hi, input [15:0] lo, input [1:0] selects);
		integer timeout;
		begin
			@(negedge clk); #0.1;
			state=writing ? 5'b01111 : 5'b01110;
			address=(26'h0800000+offset)>>1; wr=hi; wr_lo=lo; pair=paired; bs=selects;
			repeat(3) tick;
			@(negedge clk); #0.1; state[2]=0;
			timeout=0; tick;
			while(!ack) begin tick; timeout=timeout+1; if(timeout>1024) $fatal(1,"CPU timeout"); end
			if(!writing) begin
				if(paired && (rd_hi!==hi || rd!==lo)) $fatal(1,"stale paired read got=%h/%h expected=%h/%h",rd_hi,rd,hi,lo);
				if(!paired && rd!==hi) $fatal(1,"stale narrow read got=%h expected=%h",rd,hi);
			end
			@(negedge clk); #0.1; state[2]=1;
			repeat(3) tick;
		end
	endtask
	initial begin
		for(n=0;n<512;n=n+1) memory[n]=0;
		repeat(10) tick; reset_n=1;
		wait(ready); repeat(400) tick;
		if(QUEUED) begin rtgce=1; repeat(32) tick; end
		access_cpu(0,1,1,16'h3344,16'h1122,3);
		access_cpu(0,1,0,16'haa00,0,2); // Merge first word's high byte.
		access_cpu(4,1,1,16'h7788,16'h5566,3);
		access_cpu(8,1,1,16'hbbcc,16'h99aa,3);
		if(QUEUED) begin
			fork
				begin repeat(24) tick; rtgce=0; end
				access_cpu(0,0,1,16'haa44,16'h1122,3);
			join
		end else access_cpu(0,0,1,16'haa44,16'h1122,3);
		access_cpu(4,0,1,16'h7788,16'h5566,3);
		access_cpu(8,0,1,16'hbbcc,16'h99aa,3);
		access_cpu(2,1,0,16'h00ee,0,1);
		access_cpu(2,0,0,16'h11ee,0,3);
		if(cpu_reads<4 || writes<6) $fatal(1,"readback coverage");
		$display("PASS: production cache read-after-write queued=%0d writes=%0d physical CPU reads=%0d",QUEUED,writes,cpu_reads);
		$finish;
	end
	initial begin #2000000; $fatal(1,"readback timeout"); end
endmodule
