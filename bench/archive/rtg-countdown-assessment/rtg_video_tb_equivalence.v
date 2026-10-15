`timescale 1ns/1ps
module rtg_video_tb;
    localparam W=64,H=12,HT=96,VT=24;
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
    reg [10:0] reg_addr=0; reg reg_wr=0,reg_req=0; reg [15:0] reg_d=0;
    wire [25:0] addr; wire req,pri;
    reg [15:0] data=0; reg ack=0,fill=0;
    wire [7:0] r,g,b; wire pixel,de;
    rtg_video #(.PREPARE_DELAY(32),.H_ACTIVE(W),.V_ACTIVE(H),.H_TOTAL(HT),.V_TOTAL(VT)) dut (
        .clk_114(sys),.clk_rtg(vid),.reset_n(reset_n),.rtg_ena(ena),.video_reset(video_reset),
        .frame_start(sof),.vblank_start(vb),.pixel_x(px),.pixel_y(py),
        .reg_addr(reg_addr),.reg_wr(reg_wr),.reg_req(reg_req),.reg_d(reg_d),.reg_ack(),.reg_q(),
        .fetch_addr(addr),.fetch_req(req),.fetch_pri(pri),.fetch_d(data),.fetch_ack(ack),.fetch_fill(fill),
        .red(r),.green(g),.blue(b),.pixel(pixel),.de(de)
    );
    wire [25:0] golden_addr;
    wire golden_req, golden_pri, golden_pixel, golden_de;
    wire [7:0] golden_r, golden_g, golden_b;
    rtg_video_before #(.PREPARE_DELAY(32),.H_ACTIVE(W),.V_ACTIVE(H),.H_TOTAL(HT),.V_TOTAL(VT)) golden (
        .clk_114(sys),.clk_rtg(vid),.reset_n(reset_n),.rtg_ena(ena),.video_reset(video_reset),
        .frame_start(sof),.vblank_start(vb),.pixel_x(px),.pixel_y(py),
        .reg_addr(reg_addr),.reg_wr(reg_wr),.reg_req(reg_req),.reg_d(reg_d),.reg_ack(),.reg_q(),
        .fetch_addr(golden_addr),.fetch_req(golden_req),.fetch_pri(golden_pri),.fetch_d(data),.fetch_ack(ack),.fetch_fill(fill),
        .red(golden_r),.green(golden_g),.blue(golden_b),.pixel(golden_pixel),.de(golden_de)
    );
    always @(negedge sys) if(reset_n) begin
        #1;
        if({req,pri,addr} !== {golden_req,golden_pri,golden_addr})
            $fatal(1,"countdown/golden SDRAM interface differs: %b/%b %h vs %b/%b %h", req,pri,addr,golden_req,golden_pri,golden_addr);
    end
    always @(negedge vid) if(reset_n) begin
        #1;
        if({de,pixel,r,g,b} !== {golden_de,golden_pixel,golden_r,golden_g,golden_b})
            $fatal(1,"countdown/golden pixel interface differs");
    end
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
    integer phase=0, wordno=0, stalls=0;
    reg [25:0] burst_addr;
    reg starve=0;
    always @(negedge sys) begin
        ack=0; fill=0;
        if(phase==0) begin
            if(req && !starve && stalls%3!=0) begin burst_addr=addr;ack=1;phase=1;end
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
    integer checks=0, expected_checks=0;
    reg checking=0;
    reg [25:0] expected_addr;
    reg [15:0] expected_word;
    reg [7:0] expected_idx;
    reg [23:0] expected_rgb;
    // RGB sampled before the edge must correspond to this HDMI coordinate.
    always @(posedge vid) if(checking && !video_reset) begin
        if(cx<W && cy<H) begin
            expected_addr=(cy<split ? 26'h10000 : 26'h20000)+
                ((cy<split ? cy : cy-split)*W+cx)/(mode==2?2:1)*2;
            expected_word=memory(expected_addr);
            expected_idx=cx[0]?expected_word[7:0]:expected_word[15:8];
            expected_rgb=mode==2?palette(expected_idx):colour(expected_word,mode);
            if(!de || {r,g,b}!==expected_rgb)
                $fatal(1,"pixel %0d,%0d mode %0d split %0d: got %h de=%b expected %h state=%d used=%d/%d fault=%b",cx,cy,mode,split,{r,g,b},de,expected_rgb,dut.state,dut.used_top,dut.used_bottom,dut.frame_fault);
            checks=checks+1;
        end else if(de) $fatal(1,"FIFO consumption/output during blank at %0d,%0d",cx,cy);
    end
    task check_frame;
        input integer m; input integer sp;
        begin
            checking=0; mode=m;split=sp;
            write_reg(4,m==2?16'h8000:0);write_reg(6,m==1?0:1);
            write_reg(20,sp==H?11'h7ff:sp);
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
    integer i;
    initial begin
        #50;reset_n=1;
        write_reg(0,1);write_reg(2,0);write_reg(8,2);write_reg(10,0);
        for(i=0;i<256;i=i+1) begin
            write_reg(11'h400+i*4,i);write_reg(11'h402+i*4,{i[7:0]^8'h55,~i[7:0]});
        end
        @(negedge vid);ena=1;video_reset=0;
        check_frame(0,H);check_frame(1,1);check_frame(2,6);check_frame(0,H-1);
        check_frame(2,H);
        // An out-of-range split must behave as one framebuffer.
        write_reg(20,0);
        check_frame(0,H);
        // Starve a running frame: fault must stick until next frame preparation.
        wait(sof);@(negedge vid);starve=1;
        wait(dut.frame_fault);repeat(10) @(negedge vid);
        if(de || {r,g,b}!=0) $fatal(1,"underflow not black");
        starve=0;check_frame(0,H);
        // Disable with a transaction in progress; no new reads or fetches.
        wait(fill);@(negedge vid);ena=0;video_reset=1;
        repeat(50) @(negedge sys);
        if(req || pri || dut.pop_top || dut.pop_bottom) $fatal(1,"disabled RTG still active");
        @(negedge vid);ena=1;video_reset=0;check_frame(0,H);
        $display("PASS: RTG formats, pixel alignment, split rows, frame restart, starvation and disable");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
