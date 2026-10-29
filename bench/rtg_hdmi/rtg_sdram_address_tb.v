`timescale 1ns/1ps
// Exercise the actual RTG producer, SDRAM arbiter and CPU cache together.
// Data pins are zero: this checks arbitration/progress, not SDRAM electrical timing.
module rtg_sdram_address_tb #(
    parameter REPEAT_CODE=10,
    parameter INDEXED=1,
    parameter TRAFFIC_GAP=0,
    parameter OLD_MAP=0
);
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
        .clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.cpu_resetn(reset_n),.resetn_rtg(reset_n),.rtg_active(ena),.video_reset(video_reset),
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
    sdram_ctrl mem (
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
    always @(posedge sys) begin
        if(rtg.fetch_req && rtg.state != rtg.PREFILL_BOTTOM) begin
            if(rtg.selected_has_work == 0)
                $fatal(1,"fetch with no remaining output rows");
        end
        if(extend_ok && rtg.selected_row_left<=4)
            $fatal(1,"extension enabled at row boundary");
    end
    integer host_count=0,cpu_count=0,burst_count=0,refresh_count=0;
    integer host_wait=0,cpu_wait=0,refresh_wait=0;
    integer host_gap=0,cpu_gap=0,max_host_wait=0,max_cpu_wait=0,max_refresh_wait=0;
    reg traffic=0;
    always @(negedge sys) if(traffic) begin
        if(host_req && host_ack) begin
            host_req=0;host_gap=TRAFFIC_GAP;host_count=host_count+1;host_wait=0;
        end else if(host_req) begin
            host_wait=host_wait+1;
            if(host_wait>max_host_wait) max_host_wait=host_wait;
            if(host_wait>8192) $fatal(1,"832 host starved by RTG");
        end else if(host_gap!=0) host_gap=host_gap-1;
        else host_req=1;
        if(!cpu_state[2] && cpu_ack) begin
            cpu_state=5'b00101;cpu_gap=TRAFFIC_GAP;cpu_count=cpu_count+1;cpu_wait=0;
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
        if(mem.slot1_type==0 && mem.sdram_state[1]) refresh_count=refresh_count+1;
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
    // Check the physical command stream as well as accepted addresses.
    // Extended RTG reads must use the SDRAM row already open in their bank.
    reg [3:0] bank_open=0;
    reg [12:0] open_row[0:3];
    reg [25:0] command_address;
    integer command_checks=0;
    always @(negedge sys) begin
        if(mem.sd_cmd==mem.CMD_ACTIVE) begin
            bank_open[mem.ba]=1;
            open_row[mem.ba]=mem.sdaddr;
        end else if(mem.sd_cmd==mem.CMD_READ || mem.sd_cmd==mem.CMD_WRITE) begin
            if(mem.sd_cmd==mem.CMD_READ &&
               ((mem.sdram_state[5] && mem.slot1_type==mem.RTG) ||
                (mem.sdram_state[13] && mem.slot2_type==mem.RTG))) begin
                command_address=mem.sdram_state[5] ? mem.slot1_addr : mem.slot2_addr;
                if(!bank_open[mem.ba] || open_row[mem.ba]!==command_address[22:10])
                    $fatal(1,"RTG read without correct open SDRAM row addr=%h bank=%d row=%h open=%b",command_address,mem.ba,open_row[mem.ba],bank_open[mem.ba]);
                command_checks=command_checks+1;
            end
            if(mem.sdaddr[10]) bank_open[mem.ba]=0;
        end else if(mem.sd_cmd==mem.CMD_PRECHARGE) begin
            if(mem.sdaddr[10]) bank_open=0;
            else bank_open[mem.ba]=0;
        end else if(mem.sd_cmd==mem.CMD_AUTO_REFRESH) bank_open=0;
    end
    integer frame_starts=0, fault_count=0, missed_frames=0;
    reg last_fault=0;
    always @(posedge vid) begin
        if(rtg.frame_fault && !last_fault) begin
            fault_count=fault_count+1;
            $fatal(1,"underrun x=%d y=%d state=%d used=%d row_left=%d ready=%b",x,y,rtg.state,rtg.used_top,rtg.row_left_top,rtg.frame_ready);
        end
        last_fault=rtg.frame_fault;
        if(scan_frame) begin
            frame_starts=frame_starts+1;
            if(!rtg.start_display) begin
                missed_frames=missed_frames+1;
                $fatal(1,"missed frame start state=%d used=%d ready=%b",rtg.state,rtg.used_top,rtg.frame_ready);
            end
        end
    end
    localparam SOURCE_WIDTH=(1024/((REPEAT_CODE%4+1)*16))*16;
    localparam ROW_BURSTS=INDEXED ? SOURCE_WIDTH/16 : SOURCE_WIDTH/8;
    localparam V_REPEAT=REPEAT_CODE/4+1;
    integer burst_column=0, repeat_row_index=0, source_row=0;
    integer address_checks=0;
    reg [25:0] expected_address;
    always @(posedge sys) begin
        if(rtg.fifo_reset) begin
            burst_column=0;
            repeat_row_index=0;
            source_row=0;
        end else if(ack && rtg.keep_fill) begin
            expected_address=26'h800000+source_row*ROW_BURSTS*16+burst_column*16;
            if((mem.sdram_state[4] ? mem.slot1_addr : mem.slot2_addr)!==expected_address)
                $fatal(1,"wrong SDRAM accepted address got=%h expected=%h state=%d burst=%d vphase=%d config_sys_repeat=%h row_bursts=%d clut=%b addr=%h left=%d repeat=%d base=%h",mem.sdram_state[4] ? mem.slot1_addr : mem.slot2_addr,expected_address,rtg.state,burst_column,repeat_row_index,rtg.config_sys_repeat,rtg.row_bursts,rtg.config_sys_indexed,addr,rtg.row_left_top,rtg.repeat_top,rtg.row_base_top);
            address_checks=address_checks+1;
            if(burst_column==ROW_BURSTS-1) begin
                burst_column=0;
                if(repeat_row_index==V_REPEAT-1) begin
                    repeat_row_index=0;
                    source_row=source_row+1;
                end else repeat_row_index=repeat_row_index+1;
            end else burst_column=burst_column+1;
        end
    end
    initial begin
        #50;reset_n=1;wait(mem_ready && mem.cache.cache_init_done);
        write_reg(11'h100,16'h0080);write_reg(11'h102,0);
        write_reg(11'h104,INDEXED?16'h8000:0);write_reg(11'h106,1);
        write_reg(11'h118,0);write_reg(11'h11a,SOURCE_WIDTH*(REPEAT_CODE%4+1)/16);
        write_reg(11'h11c,0);write_reg(11'h11e,48);
        write_reg(11'h120,SOURCE_WIDTH*(INDEXED?1:2)/16);
        write_reg(11'h116,SOURCE_WIDTH*(INDEXED?1:2)/16);
        write_reg(OLD_MAP?11'h116:11'h114,REPEAT_CODE);
        traffic=1;ena=1;video_reset=0;
        repeat(6500000) @(negedge sys);
        if(frame_starts<3 || address_checks<100 || command_checks<100)
            $fatal(1,"insufficient coverage");
        $display("PASS: repeat=%d indexed=%d frames=%d addresses=%d faults=%d missed=%d; max waits=%d/%d/%d",REPEAT_CODE,INDEXED,frame_starts,address_checks,fault_count,missed_frames,max_host_wait,max_cpu_wait,max_refresh_wait);
        $finish;
    end
    initial begin #70000000;$fatal(1,"initialization timeout");end
endmodule
