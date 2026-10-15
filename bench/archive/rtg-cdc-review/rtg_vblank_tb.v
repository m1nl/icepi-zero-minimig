`timescale 1ns/1ps
module rtg_vblank_tb;
    reg sys=0,vid=0,amiga=0;
    always #4.375 sys=~sys;
    always #7.575757 vid=~vid;
    always #17.5 amiga=~amiga;
    reg reset_n=0,ena=0,video_reset=1,sof=0,vb=0;
    wire pixel_clk = ena ? vid : amiga;
    reg sof_toggle=0,vb_toggle=0;
    always @(posedge pixel_clk or posedge video_reset) begin
        if(video_reset) begin sof_toggle<=0;vb_toggle<=0;end
        else begin
            if(sof) sof_toggle<=~sof_toggle;
            if(vb) vb_toggle<=~vb_toggle;
        end
    end
    reg [10:0] addr=0;reg [15:0] d=0;reg req=0,wr=0;
    wire ack,irq;wire [15:0] q;
    rtg_video #(.PREPARE_DELAY(128)) dut (
        .clk_sys(sys),.clk_rtg(vid),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_ena(ena),.video_reset(video_reset),
        .frame_start_toggle(sof_toggle),.vblank_start_toggle(vb_toggle),.pixel_x(11'd0),.pixel_y(10'd0),
        .reg_addr(addr),.reg_wr(wr),.reg_req(req),.reg_d(d),.reg_ack(ack),.reg_q(q),.irq(irq),
        .fetch_addr(),.fetch_req(),.fetch_pri(),.fetch_d(16'd0),.fetch_ack(1'b0),.fetch_fill(1'b0),
        .red(),.green(),.blue(),.pixel(),.de()
    );
    reg [1:0] irq_28=0;reg [1:0] div=0;
    always @(posedge amiga) begin irq_28<={irq_28[0],irq};div<=div+1'b1;end
    reg native_vblank=0;
    reg [7:0] paula_addr=0;reg [15:0] paula_data=0;
    wire [2:0] ipl;
    paula_intcontroller paula (.clk(amiga),.clk7_en(div==0),.reset(!reset_n),
        .reg_address_in(paula_addr),.data_in(paula_data),.data_out(),
        .vblint(native_vblank),.int2(irq_28[1]),.int3(1'b0),.int6(1'b0),
        .rxint(1'b0),.txint(1'b0),.blckint(1'b0),.syncint(1'b0),.audint(4'd0),
        .audpen(),.rbfmirror(),._ipl(ipl));
    task access;
        input [10:0] a;input write;input [15:0] value;
        begin
            @(negedge sys);addr=a;wr=write;d=value;req=1;
            @(posedge sys);#1;if(!ack) $fatal(1,"missing ACK");
            @(negedge sys);req=0;wr=0;
            @(posedge sys);#1;
        end
    endtask
    task status;
        input [15:0] expected;
        begin access(11'h10c,0,0);if(q!==expected) $fatal(1,"status %h expected %h",q,expected);end
    endtask
    task frame_event;
        input blank;
        begin
            @(negedge pixel_clk);if(blank) vb=1;else sof=1;
            @(negedge pixel_clk);vb=0;sof=0;
            repeat(6) @(negedge sys);
        end
    endtask
    task paula_write;
        input [7:0] a;input [15:0] value;
        begin
            @(negedge amiga);paula_addr=a;paula_data=value;
            repeat(8) @(negedge amiga);
            paula_addr=0;paula_data=0;
            repeat(8) @(negedge amiga);
        end
    endtask
    initial begin
        #200;reset_n=1;repeat(6) @(negedge sys);
        status(0);access(11'h10e,0,0);if(q!==16'h8321) $fatal(1,"ID changed");
        // Reproduce P96 startup: IRQ enabled before requesting RTG display.
        video_reset=0;repeat(6) @(negedge sys);
        access(11'h10c,1,3);status(4);
        paula_write(8'h4d,16'hc028);
        frame_event(1);status(7);
        repeat(16) @(negedge amiga);
        if(!irq || ipl!==3'd5 || dut.fetch_req || !dut.fifo_reset || dut.display_enable)
            $fatal(1,"native startup must supply PORTS IRQ without RTG display/DMA");
        access(11'h110,0,0);if(q!==1) $fatal(1,"native startup frame count");
        access(11'h10c,1,3);status(5);
        if(irq) $fatal(1,"native startup IRQ acknowledgement failed");
        // Start the active-mode checks from a clean hardware reset.
        reset_n=0;video_reset=1;repeat(8) @(negedge sys);
        reset_n=1;repeat(6) @(negedge sys);
        ena=1;video_reset=0;repeat(6) @(negedge sys);
        status(8);frame_event(1);status(9);
        access(11'h100,1,1);access(11'h102,1,16'h2340);
        repeat(140) @(negedge sys);
        if({dut.addr_top,4'd0}!==26'h12340) $fatal(1,"vblank handler update missed preparation window");
        access(11'h102,1,16'h5670);
        repeat(6) @(negedge sys);
        if({dut.addr_top,4'd0}!==26'h12340) $fatal(1,"late update changed the current frame");
        access(11'h110,0,0);if(q!==1 || irq) $fatal(1,"disabled interrupt/count");
        access(11'h10c,1,3);status(13); // enable in blank does not replay old frame
        frame_event(0);status(12);
        paula_write(8'h4d,16'hc028); // enable master, PORTS and native VERTB
        frame_event(1);status(15);
        repeat(140) @(negedge sys);
        if({dut.addr_top,4'd0}!==26'h15670) $fatal(1,"late update did not enter next frame");
        repeat(16) @(negedge amiga);
        if(!irq || ipl!==3'd5 || !paula.intreq[3] || paula.intreq[5])
            $fatal(1,"RTG IRQ must use level 2 independently of native vblank");
        access(11'h110,0,0);if(q!==2) $fatal(1,"sequence did not advance once");
        status(15);if(!irq) $fatal(1,"status read acknowledged IRQ");
        frame_event(0);status(14); // pending is held after blank ends
        access(11'h10c,1,3);status(12);
        paula_write(8'h4e,16'h0008);
        if(irq || ipl!==7) $fatal(1,"acknowledged IRQ did not release");
        native_vblank=1;repeat(8) @(negedge amiga);native_vblank=0;
        repeat(8) @(negedge amiga);
        if(ipl!==3'd4 || !paula.intreq[5] || paula.intreq[3])
            $fatal(1,"native vblank must remain level 3");
        paula_write(8'h4e,16'h0020);
        frame_event(1);access(11'h10c,1,2);status(9);
        if(irq) $fatal(1,"disable did not clear pending");
        frame_event(0);frame_event(1);status(9);
        access(11'h110,0,0);if(q!==4) $fatal(1,"disabled IRQ stopped frame count");
        access(11'h10c,1,3);frame_event(0);
        // A new HDMI frame coincident with W1C must not be lost.
        @(negedge vid);vb=1;@(negedge vid);vb=0;
        wait(dut.vblank);@(negedge sys);
        addr=11'h10c;d=3;wr=1;req=1;
        @(posedge sys);#1;if(!irq) $fatal(1,"new frame lost during acknowledgement");
        @(negedge sys);req=0;wr=0;repeat(3) @(negedge sys);
        status(15);
        ena=0;repeat(6) @(negedge sys);status(7);
        if(!irq) $fatal(1,"switching to native lost a pending IRQ");
        access(11'h10c,1,3);frame_event(0);status(4);
        frame_event(1);status(7);
        access(11'h110,0,0);if(q!==6 || !irq || dut.fetch_req) $fatal(1,"native frame IRQ/count or DMA gating");
        video_reset=1;ena=1;repeat(6) @(negedge sys);status(14);
        access(11'h10c,1,3);status(12);
        frame_event(1);access(11'h110,0,0);
        if(q!==0 || irq) $fatal(1,"HDMI reset generated a spurious frame IRQ");
        video_reset=0;repeat(6) @(negedge sys);frame_event(0);status(12);
        frame_event(1);status(15);access(11'h110,0,0);if(q!==1) $fatal(1,"clock restart count");
        $display("PASS: native startup IRQ, HDMI blank/sequence, sticky/W1C IRQ, PORTS, native VERTB and clock restart");
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
