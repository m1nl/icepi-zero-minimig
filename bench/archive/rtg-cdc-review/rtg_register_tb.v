`timescale 1ns/1ps
module rtg_register_tb;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0;
    reg [10:0] addr=0;reg [15:0] d=0;reg req=0,wr=0;
    wire ack;wire [15:0] q;
    rtg_video dut (
        .clk_sys(clk),.clk_rtg(clk),.resetn_sys(reset_n),.resetn_rtg(reset_n),.rtg_ena(1'b0),.video_reset(1'b1),
        .frame_start_toggle(1'b0),.vblank_start_toggle(1'b0),.pixel_x(11'd0),.pixel_y(10'd0),
        .reg_addr(addr),.reg_wr(wr),.reg_req(req),.reg_d(d),.reg_ack(ack),.reg_q(q),
        .fetch_addr(),.fetch_req(),.fetch_pri(),.fetch_d(16'd0),.fetch_ack(1'b0),.fetch_fill(1'b0),
        .red(),.green(),.blue(),.pixel(),.de()
    );
    task access;
        input [10:0] a;input write;input [15:0] value;
        begin
            @(negedge clk);addr=a;wr=write;d=value;req=1;
            @(posedge clk);#1;
            if(!ack) $fatal(1,"RTG access did not ACK %h",a);
            repeat(4) begin
                @(posedge clk);#1;
                if(ack) $fatal(1,"RTG ACK must pulse once per request %h",a);
            end
            @(negedge clk);req=0;
            @(posedge clk);#1;if(ack) $fatal(1,"ACK did not release");
        end
    endtask
    task read_id;
        input [10:0] a;input [15:0] expected;
        begin access(a,0,0);if(q!==expected) $fatal(1,"bad legacy read %h: %h",a,q);end
    endtask
    initial begin
        #12;reset_n=1;
        access(11'h112,0,0);
        if(q!==0 || dut.display_enable!==0) $fatal(1,"reset must select native video");
        access(11'h114,0,0);
        if(q!==16'h07ff) $fatal(1,"reset must disable screen splitting");
        // MMIO works while the selected pixel clock remains native/reset.
        access(11'h112,1,16'hffff);
        access(11'h112,0,0);
        if(q!==1 || dut.display_enable!==1) $fatal(1,"RTG display enable/readback");
        access(11'h114,1,16'd384);
        access(11'h114,0,0);
        if(q!==384) $fatal(1,"RTG split row readback");
        access(11'h112,1,16'hfffe);
        if(dut.display_enable!==0) $fatal(1,"native display selection");
        // $B80100 primary base, $B80104 format, $B80108 secondary base.
        access(11'h100,1,16'h0123);
        if(dut.rtg_base!==0) $fatal(1,"partially written base became visible");
        access(11'h102,1,16'h4560);
        if({dut.rtg_base,4'd0}!==26'h1234560) $fatal(1,"primary address decode");
        access(11'h104,1,16'h8000);access(11'h106,1,0);
        if(!dut.rtg_clut || dut.rtg_16bit) $fatal(1,"format decode");
        access(11'h108,1,16'h0234);access(11'h10a,1,16'h5670);
        if({dut.rtg_base2,4'd0}!==26'h2345670) $fatal(1,"secondary address decode");
        // Held writes must not be replayed, even if bus data changes after ACK.
        @(negedge clk);addr=11'h102;wr=1;d=16'h7890;req=1;
        @(posedge clk);#1;@(negedge clk);d=16'hffff;
        repeat(5) @(posedge clk);
        #1;if(dut.rtg_base[15:4]!==12'h789) $fatal(1,"held request repeated write");
        @(negedge clk);req=0;@(posedge clk);#1;
        // $B80400 starts the two-word palette entries.
        access(11'h414,1,16'h00ab);access(11'h416,1,16'hcdef);
        if(dut.clut[5]!==24'habcdef) $fatal(1,"palette address/colour decode");
        read_id(11'h10e,16'h8321);read_id(11'h1fe,16'h8321);
        read_id(11'h100,16'h8321);read_id(11'h102,16'h8321);
        read_id(11'h700,16'h8321);read_id(11'h702,16'h8321);
        // C2P ID and conversion registers remain in Akiko; $B802xx is not an RTG register window.
        @(negedge clk);addr=11'h000;wr=0;req=1;
        @(posedge clk);#1;if(ack) $fatal(1,"C2P ID incorrectly claimed by RTG");
        @(negedge clk);addr=11'h038;wr=1;d=16'hffff;
        @(posedge clk);#1;if(ack) $fatal(1,"C2P incorrectly claimed by RTG");
        @(negedge clk);addr=11'h200;
        @(posedge clk);#1;if(ack) $fatal(1,"audio incorrectly claimed by RTG");
        @(negedge clk);req=0;
        access(11'h112,1,1);
        @(negedge clk);reset_n=0;
        @(posedge clk);#1;
        if(dut.display_enable!==0 || dut.split_line!==11'h7ff) $fatal(1,"reset must restore native defaults");
        $display("PASS: RTG display/split registers, legacy decode, ID, held transactions and C2P isolation");$finish;
    end
endmodule
