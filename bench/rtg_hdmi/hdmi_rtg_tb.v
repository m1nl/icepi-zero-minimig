`timescale 1ns/1ps
module hdmi_rtg_tb;
    localparam W=1024,H=768,HT=1344,VT=806;
    reg sys=0,vid=0;
    always #4.375 sys=~sys;
    always #7.575757 vid=~vid;
    reg reset_n=0,ena=0,video_reset=1;
    // Coordinates are internal debug observations, not interface signals.
    wire [10:0] cx = encoder.cx; wire [9:0] cy = encoder.cy;
    wire sof = cx==0 && cy==0 && !video_reset;
    wire vb = cx==0 && cy==H && !video_reset;
    wire sof_toggle,vb_toggle,scan_pixel,scan_frame,scan_line;
    wire [7:0] r,g,b;
    reg [23:0] hdmi_rgb;
    // Match the falling-edge RGB output register in the IcePi top module.
    always @(negedge vid) hdmi_rgb <= {r,g,b};
    reg pal=1,lf=1,interlace=0;reg [1:0] screen=0;
    hdmi #(.DVI_OUTPUT(1),.AUDIO_BIT_WIDTH(16),.RTG_REQUEST_LEAD(2)) encoder (
        .clk_pixel(vid),.clk_pixel_x5(vid),.reset(video_reset),.rtg_en(ena),
        .frame_start_toggle(sof_toggle),.vblank_start_toggle(vb_toggle),
        .rtg_pixel_request(scan_pixel),.rtg_frame_request(scan_frame),.rtg_line_prepare(scan_line),
        .pal_mode(pal),.long_frame(lf),.interlace(interlace),.screen_mode(screen),
        .offset_x(8'd255),.offset_y(7'd127),.vsync_in(pal),.hsync_in(lf),
        .rgb(hdmi_rgb),.audio_sample_word_0(16'd0),.audio_sample_word_1(16'd0),
        .audio_sample_en(),.tmds(),.tmds_clock()
    );
    always @(negedge vid) begin pal=~pal;lf=~lf;interlace=~interlace;screen=screen+1;end
    reg [10:0] reg_addr=0; reg reg_wr=0,reg_req=0; reg [15:0] reg_d=0;
    wire [25:0] addr; wire req,pri,extend_ok;
    wire [15:0] data; wire ack,fill;
    wire pixel,de;
    rtg_video dut (
        .clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_active(ena),.video_reset(video_reset),
        .frame_start_toggle(sof_toggle),.vblank_start_toggle(vb_toggle),.pixel_request(scan_pixel),.frame_request(scan_frame),.line_prepare(scan_line),
        .reg_addr(reg_addr),.reg_wr(reg_wr),.reg_req(reg_req),.reg_d(reg_d),.reg_ack(),.reg_q(),
        .fetch_addr(addr),.fetch_req(req),.fetch_pri(pri),.fetch_extend(extend_ok),.fetch_d(data),.fetch_ack(ack),.fetch_fill(fill),
        .red(r),.green(g),.blue(b)
    );
    reg output_valid;
    always @(posedge vid)
        output_valid <= dut.valid_2 && ena && !video_reset &&
                        !dut.reset_top_r && !dut.reset_bottom_r;
    assign pixel=output_valid && dut.rtg_active && !dut.video_reset;
    assign de=output_valid && dut.rtg_active && !dut.video_reset;
    function [15:0] memory;
        input [25:0] a;
        begin memory = ((a>>1)*16'h1237) ^ 16'h9b65; end
    endfunction
    function [23:0] colour;
        input [15:0] d; input integer mode;
        begin
            if(mode==1) colour={d[14:10],d[14:12],d[9:5],d[9:7],d[4:0],d[4:2]};
            else colour={d[15:11],d[15:13],d[10:5],d[10:9],d[4:0],d[4:2]};
        end
    endfunction
    function [23:0] palette;
        input [7:0] idx;
        begin palette={idx,idx^8'h55,~idx};end
    endfunction
    // Use the actual SDRAM arbiter/burst scheduling; substitute address-derived
    // return data for the physical SDRAM pins, which this test does not model.
    wire mem_ready;
    reg [3:0] div=0;
    always @(posedge sys) div<=div+1'b1;
    sdram_ctrl memory_controller (
        .sysclk(sys),.clk7_en(&div[3:2]),.clk28_en(div[1:0]==0),
        .reset_in(reset_n),.cache_rst(reset_n),.reset_out(mem_ready),
        .cache_inhibit(1'b0),.cacheline_clr(1'b0),.cpu_cache_ctrl(4'd0),
        .sdaddr(),.sd_cs(),.ba(),.sd_we(),.sd_ras(),.sd_cas(),.dqm(),.sdata(),
        .hostWR(32'd0),.hostAddr(24'd0),.hostce(1'b0),.hostwe(1'b0),
        .hostinterrupt(1'b0),.hostbytesel(4'd0),.hostRD(),.hostena(),
        .chipAddr(23'd0),.chipL(1'b1),.chipU(1'b1),.chipL2(1'b1),.chipU2(1'b1),
        .chipRW(1'b1),.chip_dma(1'b1),.chipWR(16'd0),.chipWR2(16'd0),.chipRD(),.chip48(),
        .rtgAddr(addr),.rtgce(req),.rtgpri(pri),.rtg_extend_ok(extend_ok),.rtgack(ack),.rtgfill(fill),.rtgRd(),
        .audAddr(23'd0),.audce(1'b0),.audack(),.audfill(),.audRd(),
        .cpu_long_cand(1'b0),.cpuWR_lo(16'b0),.cpuRD_hi(),
        .cpuAddr(25'd0),.cpustate(4'b0001),.cpuL(1'b1),.cpuU(1'b1),.cpuWR(16'd0),
        .cpuRD(),.enaWRreg(),.ena7RDreg(),.ena7WRreg(),.cpuena()
    );
    reg [25:0] pending [0:15];
    integer push=0,pop=0,wordno=0;
    assign data=memory(pending[pop%16]+wordno*2);
    always @(posedge sys) begin
        if(ack) begin
            if(push-pop>=15) $fatal(1,"burst queue overflow");
            pending[push%16]<=addr;push=push+1;
        end
        if(fill) begin
            if(pop>=push) $fatal(1,"fill without accepted burst");
            if(wordno==7) begin wordno=0;pop=pop+1;end else wordno=wordno+1;
        end
        if(dut.keep_fill && fill && (dut.owner ? dut.bottom_fifo.full : dut.top_fifo.full)) $fatal(1,"FIFO overflow");
    end
    task write_reg;
        input [10:0] a; input [15:0] d;
        begin @(negedge sys);reg_addr=a[10]?a:(a|11'h100);reg_d=d;reg_wr=1;reg_req=1;@(negedge sys);reg_wr=0;reg_req=0;end
    endtask
    integer mode=0, split=H;
    integer checks=0, expected_checks=0;
    reg checking=0;
    reg [25:0] expected_addr;
    reg [15:0] expected_word;
    reg [7:0] expected_idx;
    reg [23:0] expected_rgb;
    // With a two-pixel lead the RTG output is one coordinate behind cx/cy;
    // its falling-edge output register presents that pixel to HDMI next edge.
    wire [10:0] output_x = cx==0 ? HT-1 : cx-1'b1;
    wire [9:0] output_y = cx==0 ? (cy==0 ? VT-1 : cy-1'b1) : cy;
    // Verify the scanout independently of the output-edge register.
    always @(posedge vid) if(checking && !video_reset) begin
        if(output_x<W && output_y<H) begin
            expected_addr=(output_y<split ? 26'h10000 : 26'h20000)+
                ((output_y<split ? output_y : output_y-split)*W+output_x)/(mode==2?2:1)*2;
            expected_word=memory(expected_addr);
            expected_idx=output_x[0]?expected_word[7:0]:expected_word[15:8];
            expected_rgb=mode==2?palette(expected_idx):colour(expected_word,mode);
            if(!de || {r,g,b}!==expected_rgb)
                $fatal(1,"pixel %0d,%0d mode %0d split %0d: got %h de=%b expected %h state=%d used=%d/%d fault=%b",cx,cy,mode,split,{r,g,b},de,expected_rgb,dut.state,dut.used_top,dut.used_bottom,dut.frame_fault);
            checks=checks+1;
        end else if(de) $fatal(1,"FIFO consumption/output during blank at %0d,%0d",cx,cy);
    end
    reg [10:0] check_x;reg [9:0] check_y;
    reg [23:0] check_rgb;reg check_enabled;
    always @(posedge vid) begin
        check_x=output_x;check_y=output_y;check_rgb={r,g,b};check_enabled=checking;
        #1;
        if(check_enabled) begin
            if(encoder.mode !== (check_x<W && check_y<H ? 3'd1 : 3'd0)) $fatal(1,"HDMI DE alignment");
            if(check_x<W && check_y<H && encoder.video_data!==check_rgb) $fatal(1,"HDMI RGB alignment");
        end
    end
    task check_frame;
        input integer m; input integer sp;
        begin
            checking=0; mode=m;split=sp;
            write_reg(4,m==2?16'h8000:0);write_reg(6,m==1?0:1);
            write_reg(24,0);write_reg(26,W/16);
            write_reg(28,0);write_reg(30,H/16);
            write_reg(32,W*(m==2?1:2)/16);
            write_reg(11'h116,W*(m==2?1:2)/16);
            write_reg(18,sp==H?11'h7ff:sp);
            // Let changed settings be prepared at the next blank; then wait for its origin.
            wait(vb);@(negedge vid);wait(sof);@(negedge vid);
            // Above wait can land on a frame before the context change; verify snapshot.
            if(dut.config_sys_split!=sp || dut.config_sys_indexed!=(m==2)) $fatal(1,"configuration not latched");
            wait(vb);@(negedge vid);wait(sof);
            checking=1;checks=0;
            @(negedge vid);wait(vb);@(negedge vid);checking=0;
            if(checks!=W*H) $fatal(1,"wrong frame length: %0d",checks);
            $display("Checked full HDMI frame mode=%0d split=%0d at %0t",m,sp,$time);
        end
    endtask
    integer i;
    initial begin
        #50;reset_n=1;wait(mem_ready);
        write_reg(0,1);write_reg(2,0);write_reg(8,2);write_reg(10,0);
        for(i=0;i<256;i=i+1) begin
            write_reg(11'h400+i*4,i);write_reg(11'h402+i*4,{i[7:0]^8'h55,~i[7:0]});
        end
        // HDMI loads the selected raster synchronously while reset is held.
        @(negedge vid);ena=1;
        repeat(3) @(negedge vid);
        video_reset=0;
        check_frame(0,H);check_frame(1,1);check_frame(2,6);check_frame(0,H-1);
        check_frame(2,H);
        // Stop with in-flight SDRAM data; then prepare another full frame.
        wait(fill);@(negedge vid);ena=0;video_reset=1;
        repeat(50) @(negedge sys);
        if(req || pri || dut.pop_top || dut.pop_bottom) $fatal(1,"disabled RTG still active");
        @(negedge vid);ena=1;
        repeat(3) @(negedge vid);
        video_reset=0;check_frame(0,H);
        $display("PASS: full HDMI frames with real SDRAM arbitration, all formats, split rows and restart");$finish;
    end
    initial begin #500000000;$fatal(1,"timeout");end
endmodule
