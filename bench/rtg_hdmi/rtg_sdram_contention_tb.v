`timescale 1ns/1ps
// Exercise the actual RTG producer, SDRAM arbiter and CPU cache together.
// Data pins are zero: this checks arbitration/progress, not SDRAM electrical timing.
module rtg_sdram_contention_tb #(parameter CPU_WRITE_QUEUE=0);
    reg sys=0,vid=0;
    always #4.375 sys=~sys;
    always #7.575757 vid=~vid;
    reg reset_n=0,ena=0,video_reset=1;
    reg [10:0] x=0;
    reg [9:0] y=0;
    always @(posedge vid) begin
        if(video_reset) begin x<=0;y<=0;end
        else if(x==1343) begin x<=0;y<=y==805?0:y+1'b1;end
        else x<=x+1'b1;
    end
    wire [10:0] px=x>=1341?x-1341:x+11'd3;
    wire [9:0] py=x>=1341?(y==805?10'd0:y+1'b1):y;
    wire sof=!video_reset && x==0 && y==0;
    wire vb=!video_reset && x==0 && y==768;
    reg sof_toggle=0,vb_toggle=0,scan_pixel=0,scan_frame=0,scan_line=0;
    wire [10:0] px4=x>=1340?{9'd0,x[1:0]}:x+11'd4;
    wire [9:0] py4=x>=1340?(y==805?10'd0:y+1'b1):y;
    always @(posedge vid) begin
        if(video_reset) begin sof_toggle<=0;vb_toggle<=0;end
        else begin
            if(sof) sof_toggle<=~sof_toggle;
            if(vb) vb_toggle<=~vb_toggle;
        end
        if(video_reset || !ena) begin scan_pixel<=0;scan_frame<=0;scan_line<=0;end
        else begin
            scan_pixel<=px4<1024 && py4<768;
            // Match HDMI: arm the frame one cycle before the first pixel.
            scan_frame<=x==1339 && y==805;
            scan_line<=px4==1024;
        end
    end
    reg [10:0] reg_addr=0;
    reg [15:0] reg_d=0;
    reg reg_req=0,reg_wr=0;
    wire [25:0] addr;
    wire req,pri,extend_ok,ack,fill;
    wire [15:0] data;
    rtg_video rtg (
        .clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_active(ena),.video_reset(video_reset),
        .frame_start_toggle(sof_toggle),.vblank_start_toggle(vb_toggle),.pixel_request(scan_pixel),.frame_request(scan_frame),.line_prepare(scan_line),
        .reg_addr(reg_addr),.reg_d(reg_d),.reg_req(reg_req),.reg_wr(reg_wr),.reg_ack(),.reg_q(),.irq(),
        .fetch_addr(addr),.fetch_req(req),.fetch_pri(pri),.fetch_extend(extend_ok),.fetch_ack(ack),.fetch_fill(fill),.fetch_d(data),
        .red(),.green(),.blue()
    );
    reg [4:0] div=0;
    always @(posedge sys) div<=div+1'b1;
    reg host_req=0;
    reg [4:0] cpu_state=5'b00101;
    reg [24:0] cpu_addr=25'h400000; // physical bank 1, shared with RTG
    wire cpu_ack,host_ack,mem_ready;
    tri [15:0] dq;
    assign dq=16'd0;
    sdram_ctrl #(.cpu_write_queue(CPU_WRITE_QUEUE)) mem (
        .sysclk(sys),.clk7_en(&div[3:2]),.clk28_en(div[1:0]==0),
        .reset_in(reset_n),.cache_rstn(reset_n),.reset_out(mem_ready),
        .cache_inhibit(1'b0),.cacheline_clr(1'b0),.cpu_cache_ctrl(4'd0),
        .sdaddr(),.sd_cs(),.ba(),.sd_we(),.sd_ras(),.sd_cas(),.dqm(),.sdata(dq),
        .hostWR(32'd0),.hostAddr(24'd0),.hostce(host_req),.hostwe(1'b0),
        .hostinterrupt(1'b1),.hostbytesel(4'hf),.hostRD(),.hostena(host_ack),
        .chipAddr(23'd0),.chipL(1'b0),.chipU(1'b0),.chipL2(1'b0),.chipU2(1'b0),
        .chipRW(1'b1),.chip_dma(div[4]),.chipWR(16'd0),.chipWR2(16'd0),.chipRD(),.chip48(),
        .rtgAddr(addr),.rtgce(req),.rtgpri(pri),.rtg_extend_ok(extend_ok),.rtgack(ack),.rtgfill(fill),.rtgRd(data),
        .audAddr(23'd0),.audce(1'b0),.audack(),.audfill(),.audRd(),
        .cpu_long_cand(1'b0),.cpuWR_lo(16'b0),.cpuRD_hi(),
        .cpuAddr(cpu_addr),.cpustate(cpu_state),.cpuL(1'b0),.cpuU(1'b0),.cpuWR(16'h1234),
        .cpuRD(),.enaWRreg(),.ena7RDreg(),.ena7WRreg(),.cpuena(cpu_ack)
    );
    integer host_count=0,cpu_count=0,burst_count=0,refresh_count=0;
    integer host_wait=0,cpu_wait=0,refresh_wait=0;
    integer host_gap=0,cpu_gap=0,max_host_wait=0,max_cpu_wait=0,max_refresh_wait=0;
    reg traffic=0;
    always @(negedge sys) if(traffic) begin
        if(host_req && host_ack) begin
            host_req=0;host_gap=32;host_count=host_count+1;host_wait=0;
        end else if(host_req) begin
            host_wait=host_wait+1;
            if(host_wait>max_host_wait) max_host_wait=host_wait;
            if(host_wait>8192) $fatal(1,"832 host starved by RTG");
        end else if(host_gap!=0) host_gap=host_gap-1;
        else host_req=1;
        if(!cpu_state[2] && cpu_ack) begin
            cpu_state=5'b00101;cpu_gap=32;cpu_count=cpu_count+1;cpu_wait=0;
            cpu_addr=cpu_addr+25'd16;
        end else if(!cpu_state[2]) begin
            cpu_wait=cpu_wait+1;
            if(cpu_wait>max_cpu_wait) max_cpu_wait=cpu_wait;
            if(cpu_wait>8192) $fatal(1,"Amiga CPU starved by RTG");
        end else if(cpu_gap!=0) cpu_gap=cpu_gap-1;
        else cpu_state=cpu_count[0]?5'b01011:5'b01010; // RAM request: alternate reads and writes
        if(mem.refresh_pending) begin
            refresh_wait=refresh_wait+1;
            if(refresh_wait>max_refresh_wait) max_refresh_wait=refresh_wait;
            if(refresh_wait>8192) $fatal(1,"SDRAM refresh starved by RTG");
        end else refresh_wait=0;
        if(mem.slot1_type==0 && mem.sdram_state==1) refresh_count=refresh_count+1;
        if(ack) burst_count=burst_count+1;
        if(rtg.keep_fill && fill && (rtg.owner?rtg.bottom_fifo.full:rtg.top_fifo.full))
            $fatal(1,"RTG FIFO overflow under contention");
    end
    task write_reg;
        input [10:0] a;input [15:0] d;
        begin
            @(negedge sys);reg_addr=a;reg_d=d;reg_wr=1;reg_req=1;
            @(negedge sys);reg_wr=0;reg_req=0;
            @(negedge sys);
        end
    endtask
    initial begin
        #50;reset_n=1;wait(mem_ready && mem.cache.cache_init_done);
        write_reg(11'h100,16'h0080);write_reg(11'h102,0); // CPU $800000 maps to SDRAM $800000
        write_reg(11'h104,0);write_reg(11'h106,1);
        write_reg(11'h118,0);write_reg(11'h11a,64);
        write_reg(11'h11c,0);write_reg(11'h11e,48);
        write_reg(11'h120,128);
        write_reg(11'h116,128);
        traffic=1;ena=1;video_reset=0;
        // Initial prefill waits for the following HDMI frame origin. Include
        // that entire first frame and active scanout in the second frame.
        repeat(2500000) @(negedge sys);
        if(host_count<100 || cpu_count<100 || burst_count<100 || refresh_count<10)
            $fatal(1,"insufficient progress host=%d cpu=%d rtg=%d refresh=%d",host_count,cpu_count,burst_count,refresh_count);
        $display("PASS: shared SDRAM progress host=%0d cpu=%0d rtg=%0d refresh=%0d; max wait cycles=%0d/%0d/%0d; RTG frame_fault=%b",
            host_count,cpu_count,burst_count,refresh_count,max_host_wait,max_cpu_wait,max_refresh_wait,rtg.frame_fault);
        $finish;
    end
    initial begin #30000000;$fatal(1,"initialization timeout");end
endmodule
