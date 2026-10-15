`timescale 1ns/1ps
module rtg_priority_stress_tb;
    parameter W=1024,HT=1344;
    // Driver geometries are independent of the RTL's source-width formula.
    localparam TRIPLE_SOURCE_WIDTH = W==1024 ? 320 : W==1280 ? 416 : (W/96)*32;
    localparam H=12,VT=24;
    reg sys=0,vid=0;
    always #4.375 sys=~sys;
    always #7.575757 vid=~vid;
    reg reset_n=0,ena=0,video_reset=1;
    reg [10:0] cx=0; reg [9:0] cy=0;
    wire [10:0] px = cx >= HT-3 ? cx-(HT-3) : cx+3;
    wire [9:0] py = cx >= HT-3 ? (cy==VT-1 ? 0 : cy+1) : cy;
    wire sof = cx==0 && cy==0 && !video_reset;
    wire vb = cx==0 && cy==H && !video_reset;
    always @(posedge vid) begin
        if (video_reset) begin cx<=0;cy<=0;end
        else if(cx==HT-1) begin cx<=0;cy<=cy==VT-1?0:cy+1;end
        else cx<=cx+1;
    end
    reg sof_toggle=0,vb_toggle=0;
    always @(posedge vid or posedge video_reset) begin
        if(video_reset) begin sof_toggle<=0;vb_toggle<=0;end
        else begin
            if(sof) sof_toggle<=~sof_toggle;
            if(vb) vb_toggle<=~vb_toggle;
        end
    end
    wire [10:0] px4 = cx >= HT-4 ? cx-(HT-4) : cx+4;
    wire [9:0] py4 = cx >= HT-4 ? (cy==VT-1 ? 0 : cy+1) : cy;
    reg scan_pixel=0,scan_frame=0,scan_line=0;
    always @(posedge vid) begin
        if(video_reset || !ena) begin scan_pixel<=0;scan_frame<=0;scan_line<=0;end
        else begin
            scan_pixel <= px4<W && py4<H;
            scan_frame <= px4==0 && py4==0;
            scan_line <= px4==W;
        end
    end
    reg [10:0] reg_addr=0; reg reg_wr=0,reg_req=0; reg [15:0] reg_d=0;
    wire [25:0] addr; wire req,pri;
    reg [15:0] data=0; reg ack=0,fill=0;
    wire [7:0] r,g,b; wire pixel,de;
    rtg_video #(.PREPARE_DELAY(32),.H_ACTIVE(W),.V_ACTIVE(H),.H_TOTAL(HT),.V_TOTAL(VT)) dut (
        .clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_active(ena),.rtg_enable(),.video_reset(video_reset),
        .frame_start_toggle(sof_toggle),.vblank_start_toggle(vb_toggle),.pixel_request(scan_pixel),.frame_request(scan_frame),.line_prepare(scan_line),
        .reg_addr(reg_addr),.reg_wr(reg_wr),.reg_req(reg_req),.reg_d(reg_d),.reg_ack(),.reg_q(),
        .fetch_addr(addr),.fetch_req(req),.fetch_pri(pri),.fetch_d(data),.fetch_ack(ack),.fetch_fill(fill),
        .red(r),.green(g),.blue(b)
    );
    reg output_valid;
    always @(posedge vid)
        output_valid <= dut.valid_2 && ena && !video_reset &&
                        !dut.reset_top_r && !dut.reset_bottom_r;
    assign de=output_valid && ena && !video_reset;
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
    // Delayed eight-word responder. ACK advances address before data returns.
    integer phase=0, wordno=0, stalls=0, low_wait=0;
    reg [25:0] burst_addr;
    reg starve=0;
    always @(negedge sys) begin
        ack=0; fill=0;
        if(phase==0) begin
            if(req && !starve) begin
                if(pri || cy==H-1 || low_wait>=300) begin
                    burst_addr=addr;ack=1;phase=1;low_wait=0;
                end else low_wait=low_wait+1;
            end else low_wait=0;
            stalls=stalls+1;
        end else if(phase<3) phase=phase+1;
        else begin
            fill=1;data=memory(burst_addr+wordno*2);
            if(wordno==7) begin phase=0;wordno=0;end
            else wordno=wordno+1;
        end
    end
    task write_reg;
        input [10:0] a; input [15:0] d;
        begin @(negedge sys);reg_addr=a[10]?a:(a|11'h100);reg_d=d;reg_wr=1;reg_req=1;@(negedge sys);reg_wr=0;reg_req=0;end
    endtask
    integer mode=0, split=H;
    integer horizontal=1, vertical=1, row_bytes=W*2;
    integer source_x, source_y, border, source_w;
    integer checks=0, expected_checks=0;
    reg checking=0;
    reg [25:0] expected_addr;
    reg [15:0] expected_word;
    reg [7:0] expected_idx;
    reg [23:0] expected_rgb;
    // RGB sampled before the edge must correspond to this HDMI coordinate.
    always @(posedge vid) if(checking && !video_reset) begin
        if(cx<W && cy<H) begin
            source_w=horizontal==3 ? TRIPLE_SOURCE_WIDTH : W/horizontal;
            border=(W-source_w*horizontal)/2;
            source_x=(cx-border)/horizontal;
            source_y=(cy<split ? cy : cy-split)/vertical;
            if(cx<border || cx>=W-border) begin
                if(de || {r,g,b}!==0) $fatal(1,"border not black %0d,%0d",cx,cy);
            end else begin
                expected_addr=(cy<split ? 26'h10000 : 26'h20000)+
                    source_y*row_bytes+(source_x/(mode==2?2:1))*2;
                expected_word=memory(expected_addr);
                expected_idx=source_x[0]?expected_word[7:0]:expected_word[15:8];
                expected_rgb=mode==2?palette(expected_idx):colour(expected_word,mode);
                if(!de || {r,g,b}!==expected_rgb)
                    $fatal(1,"pixel %0d,%0d mode %0d scale %0dx%0d split %0d: got %h expected %h addr %h state %d used %d/%d fault %b",cx,cy,mode,horizontal,vertical,split,{r,g,b},expected_rgb,expected_addr,dut.state,dut.used_top,dut.used_bottom,dut.frame_fault);
            end
            checks=checks+1;
        end else if(de) $fatal(1,"FIFO consumption/output during blank at %0d,%0d",cx,cy);
    end
    task check_frame;
        input integer m; input integer sp; input integer hx; input integer vy; input integer padding;
        begin
            checking=0; mode=m;split=sp;
            horizontal=hx;vertical=vy;
            source_w=hx==3 ? TRIPLE_SOURCE_WIDTH : W/hx;
            row_bytes=source_w*(m==2?1:2)+padding;
            write_reg(11'h114,(hx-1)|((vy-1)<<2));
            write_reg(11'h116,padding ? row_bytes/16 : 0);
            write_reg(4,m==2?16'h8000:0);write_reg(6,m==1?0:1);
            write_reg(18,sp==H?11'h7ff:sp);
            // Let changed settings be prepared at the next blank; then wait for its origin.
            wait(vb);@(negedge vid);wait(sof);@(negedge vid);
            // Above wait can land on a frame before the context change; verify snapshot.
            if(dut.frame_split!=sp || dut.frame_indexed!=(m==2)) $fatal(1,"configuration not latched");
            wait(vb);@(negedge vid);wait(sof);
            checking=1;checks=0;
            @(negedge vid);wait(vb);@(negedge vid);checking=0;
            if(checks!=W*H) $fatal(1,"wrong frame length: %0d",checks);
        end
    endtask
    integer i,hx,vy,fmt;
    initial begin
        #50;reset_n=1;
        write_reg(0,1);write_reg(2,0);write_reg(8,2);write_reg(10,0);
        for(i=0;i<256;i=i+1) begin
            write_reg(11'h400+i*4,i);write_reg(11'h402+i*4,{i[7:0]^8'h55,~i[7:0]});
        end
        @(negedge vid);ena=1;video_reset=0;
        check_frame(0,H,1,1,0);
        $display("PASS: native-size scanout with 300-cycle low-priority stalls during rendering rows");
        $finish;
        // An out-of-range split must behave as one framebuffer.
        write_reg(18,0);
        check_frame(0,H,1,1,0);
        // Starve a running frame: fault must stick until next frame preparation.
        wait(sof);@(negedge vid);starve=1;
        wait(dut.frame_fault);repeat(10) @(negedge vid);
        if(de || {r,g,b}!=0) $fatal(1,"underflow not black");
        starve=0;check_frame(0,H,1,1,0);
        // Disable with a transaction in progress; no new reads or fetches.
        wait(fill);@(negedge vid);ena=0;video_reset=1;
        repeat(50) @(negedge sys);
        if(req || pri || dut.pop_top || dut.pop_bottom) $fatal(1,"disabled RTG still active");
        @(negedge vid);ena=1;video_reset=0;check_frame(0,H,1,1,0);
        $display("PASS: all 1x/2x/3x axis combinations, formats, splits, stride, restart, starvation and disable");$finish;
    end
    initial begin #200000000;$fatal(1,"timeout");end
endmodule
