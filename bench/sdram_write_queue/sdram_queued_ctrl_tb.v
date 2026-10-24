`timescale 1ns/1ps
// Actual controller/queue, synthetic cache request source. Pin-command checker
// uses the W9825G6KH-6I limits at 114 MHz; not an electrical SDRAM model.
module sdram_queued_ctrl_tb #(
	parameter QUEUED=1, parameter FAST=0, parameter SHORTCUT=0
);
	localparam real T=8.772;
	reg clk=0;
	always #(T/2) clk=~clk;
	reg [3:0] div=0;
	always @(posedge clk) div<=div+1'b1;
	reg reset_n=0, cache_reset_n=0, chip_dma=1, rtgce=0;
	reg [25:0] rtgaddr=26'h0800000;
	reg [25:1] cpuaddr=25'h0400000;
	wire init_done;
	wire [12:0] a;
	wire [1:0] bank, dqm;
	wire [3:0] cs;
	wire we, ras, cas;
	tri [15:0] dq;
	sdram_ctrl #(.addr_max_bits(25), .cpu_write_queue(QUEUED),
	             .fast_write(FAST), .shortcut(SHORTCUT)) dut (
		.sysclk(clk), .clk7_en(&div[3:2]), .clk28_en(div[1:0]==0),
		.reset_in(reset_n), .cache_rst(cache_reset_n), .reset_out(init_done),
		.cache_inhibit(1'b1), .cacheline_clr(1'b0), .cpu_cache_ctrl(4'd0),
		.sdaddr(a), .sd_cs(cs), .ba(bank), .sd_we(we), .sd_ras(ras), .sd_cas(cas),
		.dqm(dqm), .sdata(dq),
		.hostWR(32'd0), .hostAddr(24'd0), .hostce(1'b0), .hostwe(1'b0),
		.hostinterrupt(1'b0), .hostbytesel(4'd0), .hostRD(), .hostena(),
		.chipAddr(23'd0), .chipL(1'b0), .chipU(1'b0), .chipL2(1'b0), .chipU2(1'b0),
		.chipRW(1'b1), .chip_dma(chip_dma), .chipWR(16'd0), .chipWR2(16'd0),
		.chipRD(), .chip48(), .rtgAddr(rtgaddr), .rtgce(rtgce), .rtgpri(rtgce),
		.rtg_extend_ok(1'b0), .rtgack(), .rtgfill(), .rtgRd(),
		.audAddr(23'd0), .audce(1'b0), .audack(), .audfill(), .audRd(),
		.cpuAddr(cpuaddr), .cpustate(4'b0101), .cpuL(1'b0), .cpuU(1'b0),
		.cpu_long_cand(1'b0), .cpuWR_lo(16'd0), .cpuRD_hi(), .cpuWR(16'd0),
		.cpuRD(), .enaWRreg(), .ena7RDreg(), .ena7WRreg(), .cpuena()
	);
	reg [15:0] memory [0:32767];
	reg [15:0] expected [0:32767];
	reg [12:0] rows [0:3];
	reg [3:0] open_banks=0;
	real activate_at [0:3], available_at [0:3];
	real refresh_until=0, read_bus_until=0, last_activate=-1000;
	integer last_activate_bank=-1;
	integer phase=0, writes=0, reads=0, refreshes=0, extended1=0, extended2=0;
	integer read_blocked=0, k, index, lane, bank_check;
	function integer location(input [1:0] b, input [12:0] r, input [8:0] c);
		location=b*8192+r[3:0]*512+c;
	endfunction
	task compare_memory;
		integer n;
		begin
			for(n=0;n<32768;n=n+1)
				if(memory[n]!==expected[n])
					$fatal(1,"memory mismatch index=%h got=%h expected=%h",n,memory[n],expected[n]);
		end
	endtask
	always @(posedge clk) begin
		phase=dut.sdram_state;
		if(init_done && QUEUED && dut.cache_req && dut.cpu_writes_busy)
			read_blocked=read_blocked+1;
	end
	// Sample reset at the edge, then check the delayed register assignment.
	reg check_phase_reset;
	always @(posedge clk) begin
		check_phase_reset=(dut.reset_sdstate===1'b0);
		#2;
		if(check_phase_reset && dut.sdram_state!==4'd0)
			$fatal(1,"phase register not held in ph0 during early reset");
		if(check_phase_reset && dut.sd_cmd===4'b0100)
			$fatal(1,"stale write reissued while phase register is held in reset");
	end
	always @(negedge clk) if(init_done && !cs[0]) begin
		if($test$plusargs("trace")) $display("%f phase=%d cmd=%b bank=%d a=%h dq=%h mask=%b type=%d/%d queue=%b",$realtime,phase,{ras,cas,we},bank,a,dq,dqm,dut.slot1_type,dut.slot2_type,dut.queue_valid);
		if($realtime+0.01 < refresh_until) $fatal(1,"command during refresh recovery");
		case({ras,cas,we})
			3'b011: begin
				if(open_banks[bank] || $realtime+0.01 < available_at[bank])
					$fatal(1,"ACT before precharge/recovery bank=%d phase=%d now=%f ready=%f",bank,phase,$realtime,available_at[bank]);
				if($realtime-activate_at[bank]+0.01 < 60) $fatal(1,"tRC");
				if(bank!=last_activate_bank && $realtime-last_activate+0.01 < 2*T) $fatal(1,"tRRD");
				activate_at[bank]=$realtime; last_activate=$realtime; last_activate_bank=bank;
				rows[bank]=a; open_banks[bank]=1;
			end
			3'b100: begin
				if(!open_banks[bank] || $realtime-activate_at[bank]+0.01 < 18) $fatal(1,"WRITE tRCD/open row");
				if($realtime+0.01 < read_bus_until) $fatal(1,"READ/WRITE bus collision");
				if(!dut.sdata_oe) $fatal(1,"WRITE without DQ ownership");
				index=location(bank,rows[bank],a[8:0]);
				for(lane=0;lane<2;lane=lane+1) if(!dqm[lane]) begin
					if(^dq[lane*8+:8]===1'bx) $fatal(1,"undefined write data");
					memory[index][lane*8+:8]=dq[lane*8+:8];
				end
				writes=writes+1;
				if(phase==11) extended1=extended1+1;
				if(phase==3) extended2=extended2+1;
				if(a[10]) begin
					open_banks[bank]=0;
					available_at[bank]=$realtime+2*T;
					if(available_at[bank]<activate_at[bank]+42) available_at[bank]=activate_at[bank]+42;
					available_at[bank]=available_at[bank]+18;
				end
			end
			3'b101: begin
				if(!open_banks[bank] || $realtime-activate_at[bank]+0.01 < 18) $fatal(1,"READ tRCD/open row bank=%d phase=%d open=%b act=%f now=%f type=%d/%d",bank,phase,open_banks,activate_at[bank],$realtime,dut.slot1_type,dut.slot2_type);
				if(dut.sdata_oe) $fatal(1,"READ while driving DQ");
				if((phase==4 && dut.slot1_type==2) || (phase==12 && dut.slot2_type==2)) begin
					if(QUEUED && dut.cpu_writes_busy) $fatal(1,"CPU READ before posted writes drained");
					compare_memory;
					dut.cache.sdr_read_req=0;
				end
				reads=reads+1; read_bus_until=$realtime+10*T+5;
				if(a[10]) begin
					open_banks[bank]=0;
					available_at[bank]=$realtime+8*T+18;
				end
			end
			3'b001: begin
				for(bank_check=0;bank_check<4;bank_check=bank_check+1)
					if(open_banks[bank_check] || $realtime+0.01 < available_at[bank_check]) $fatal(1,"REFRESH before bank recovery");
				refreshes=refreshes+1; refresh_until=$realtime+60;
			end
			default: ;
		endcase
	end
	task tick;
		begin @(posedge clk); #2; end
	endtask
	task phase_at(input integer p);
		begin @(negedge clk); while(dut.sdram_state!=p) @(negedge clk); #0.1; end
	endtask
	task post(input [25:0] address, input [31:0] data, input [3:0] mask);
		integer timeout, n, ix;
		begin
			@(negedge clk); #0.1;
			dut.cache.sdr_adr=address[25:1]; dut.cache.sdr_dat_w=data;
			dut.cache.sdr_dqm_w=mask; dut.cache.sdr_write_req=~dut.cache.sdr_write_req;
			for(n=0;n<4;n=n+1) if(!mask[n]) begin
				ix=location(address[24:23],address[22:10],address[9:1]+(n/2));
				expected[ix][(n%2)*8+:8]=data[n*8+:8];
			end
			timeout=0; tick;
			while(dut.cache_write_req!==dut.cache_write_ack) begin
				tick; timeout=timeout+1;
				if(timeout>512) $fatal(1,"source write not acknowledged");
			end
			// Legacy cache keeps the payload through the ph2/ph10 staging edge.
			if(!QUEUED) repeat(2) tick;
		end
	endtask
	task drain;
		begin
			repeat(160) tick;
			compare_memory;
			if(QUEUED && dut.cpu_writes_busy) $fatal(1,"writes did not drain");
		end
	endtask
	initial begin
		for(k=0;k<32768;k=k+1) begin memory[k]=0; expected[k]=0; end
		for(k=0;k<4;k=k+1) begin activate_at[k]=-1000; available_at[k]=0; rows[k]=0; end
		repeat(10) tick; reset_n=1; cache_reset_n=1;
		wait(init_done); repeat(32) tick;
		if(QUEUED) begin
			// RTG reserves the CPU's bank while four transactions accumulate.
			rtgce=1; repeat(32) tick;
			post(26'h0800000,32'h11223344,0); post(26'h0800004,32'h55667788,0);
			post(26'h0800008,32'h99aabbcc,0); post(26'h080000c,32'hddeeff00,0);
			// A CPU miss must wait through the queue AND its in-flight slots.
			dut.cache.sdr_read_req=1;
			repeat(16) tick; rtgce=0; drain;
			if(extended1+extended2==0 || read_blocked==0 || dut.cache.sdr_read_req) $fatal(1,"extension/read barrier not exercised");
			phase_at(10);
			post(26'h0800018,32'h24681357,0); post(26'h080001c,32'habcd1234,0);
			drain;
			if(extended1==0) $fatal(1,"slot1 extension not exercised");
			// Enqueue after slot1's allocation so slot2 owns the first pair.
			phase_at(2);
			post(26'h0800010,32'h10203040,0); post(26'h0800014,32'h50607080,0);
			drain;
			if(extended2==0) $fatal(1,"slot2 extension not exercised");
			// Merge on the allocation edge: ph2 must capture the updated masks,
			// rather than the pre-merge byte selects observed during ph0.
			phase_at(10); post(26'h0800030,32'h000000aa,4'b1110);
			phase_at(15); post(26'h0800030,32'hbb000000,4'b0111);
			drain;
			// Byte merges while a head is held behind RTG arbitration.
			rtgce=1; repeat(32) tick;
			post(26'h0800020,32'h01020304,4'b1110);
			post(26'h0800020,32'h55667788,4'b0001);
			post(26'h0800024,32'h12345678,0);
			rtgce=0; drain;
			// Cache reset resynchronizes toggles without discarding accepted writes.
			rtgce=1; repeat(32) tick;
			post(26'h0800028,32'habcdef01,0);
			cache_reset_n=0; dut.cache.sdr_write_req=0;
			repeat(4) tick; cache_reset_n=1; rtgce=0; drain;
			// Reuse FIFO storage containing another bank's old address. An empty
			// queue can gain a head immediately before arbitration, while the
			// registered bank eligibility still describes that old address.
			rtgaddr=26'h1000000; rtgce=1; repeat(32) tick;
			post(26'h1000100,32'h11112222,0); post(26'h1000104,32'h33334444,0);
			post(26'h1000108,32'h55556666,0); post(26'h100010c,32'h77778888,0);
			rtgce=0; drain; rtgaddr=26'h0800000;
			phase_at(10); post(26'h0800050,32'h1234abcd,0);
			phase_at(6); post(26'h0800054,32'h5678ef01,0);
			drain;
		end
		// Row/bank changes, line/row end, partial words and reads in the opposite slot.
		post(26'h08003fc,32'hfacebeef,0); post(26'h0800400,32'h13572468,0);
		post(26'h1000000,32'h98765432,0); post(26'h1800000,32'habcdef98,4'b1010);
		drain;
		chip_dma=0;
		post(26'h0800040,32'haabbccdd,0); post(26'h0800044,32'heeff0011,0);
		drain; chip_dma=1;
		// Keep enough mixed traffic running to include a scheduled refresh.
		for(k=0;k<24;k=k+1) begin
			post(26'h0800080+k*4,32'h12345600+k,k%16);
			repeat(8) tick;
		end
		drain;
		if(refreshes==0) $fatal(1,"refresh not exercised");
		// Finish a slot2 pair, then reset while its write flag is still set.
		// Holding ph0 must not reissue that write, and init must restart.
		if(!SHORTCUT) begin
			phase_at(2); post(26'h0800200,32'hcafe1234,0); phase_at(3);
		end
		reset_n=0; cache_reset_n=0; dut.cache.sdr_write_req=0;
		repeat(10) tick;
		if(init_done) $fatal(1,"reset did not clear initialization");
		reset_n=1; cache_reset_n=1;
		wait(init_done); repeat(32) tick;
		post(26'h0800204,32'h5678cafe,0); drain;
		$display("PASS: controller queued=%0d fast=%0d shortcut=%0d writes=%0d extensions=%0d/%0d reads=%0d refresh=%0d",QUEUED,FAST,SHORTCUT,writes,extended1,extended2,reads,refreshes);
		$finish;
	end
	initial begin #2000000; $fatal(1,"controller timeout"); end
endmodule
