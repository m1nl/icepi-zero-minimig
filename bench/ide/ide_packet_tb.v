`timescale 1ns/1ps
module ide_packet_tb;
reg clk=0;
always #5 clk=~clk;
reg reset=1, rd=0, hwr=0, lwr=0, sel_ide=0;
reg [2:0] address_in=0, hdd_addr=0;
reg [15:0] data_in=0, hdd_data_out=0;
reg hdd_wr=0, hdd_status_wr=0, hdd_data_wr=0, hdd_data_rd=0;
wire drq, hdd_cmd_req, hdd_dat_req;
wire [1:0] irq;
reg [1:0] ack=0;
wire [15:0] hdd_data_in, data_out;
ide dut(.clk(clk),.clk_en(1'b1),.reset(reset),.drq(drq),
 .address_in(address_in),.sel_secondary(1'b0),.data_in(data_in),.data_out(data_out),
 .data_oe(),.rd(rd),.hwr(hwr),.lwr(lwr),.sel_ide(sel_ide),.intreq(irq),.intreq_ack(ack),
 .nrdy(),.hdd0_ena(2'b11),.hdd1_ena(2'b11),.fifo_rd(),.fifo_wr(),
 .hdd_cmd_req(hdd_cmd_req),.hdd_dat_req(hdd_dat_req),.hdd_addr(hdd_addr),
 .hdd_data_out(hdd_data_out),.hdd_data_in(hdd_data_in),.hdd_wr(hdd_wr),
 .hdd_status_wr(hdd_status_wr),.hdd_data_wr(hdd_data_wr),.hdd_data_rd(hdd_data_rd),.hdd_step());
task ticks; input integer n; repeat(n) @(negedge clk); endtask
task guest; input [2:0] a; input [15:0] d;
 begin address_in=a;data_in=d;sel_ide=1;hwr=1;lwr=1;ticks(2);hwr=0;lwr=0;sel_ide=0;ticks(3);end
endtask
task regwrite; input [2:0] a; input [7:0] d;
 begin hdd_addr=a;hdd_data_out=d;hdd_wr=1;ticks(2);hdd_wr=0;ticks(2);end
endtask
task status; input [7:0] d;
 begin hdd_data_out=d;hdd_status_wr=1;ticks(1);hdd_status_wr=0;ticks(3);end
endtask
task fwdata; input [15:0] d;
 begin hdd_data_out=d;hdd_data_wr=1;ticks(2);hdd_data_wr=0;ticks(3);end
endtask
task cpu_read; input [15:0] expected;
 begin address_in=0;sel_ide=1;ticks(2);rd=1;#1; if(data_out!==expected) $fatal(1,"data mismatch %h != %h",data_out,expected);
 ticks(2);rd=0;sel_ide=0;ticks(3);end
endtask
integer i;
reg [5:0] oldgen;
initial begin
 ticks(3);reset=0;ticks(3);
 guest(6,16'hb000); guest(2,16'h0100);guest(7,16'ha000);
 regwrite(2,1);status(8'h24);
 if(!drq) $fatal(1,"no command DRQ");
 for(i=0;i<6;i=i+1) guest(0,i);
 if(!hdd_dat_req) $fatal(1,"no command packet request");
 for(i=0;i<6;i=i+1) begin hdd_data_rd=1;ticks(2);hdd_data_rd=0;ticks(3);end
 status(8'h28);regwrite(2,2);regwrite(4,$test$plusargs("even") ? 4 : 3);regwrite(5,0);
 fwdata(16'h1234);fwdata(16'h5600);
 if(!drq) $fatal(1,"odd 3-byte response needs two FIFO words and DRQ");
 status(8'h90);ack=1;ticks(2);ack=0;cpu_read(16'h1234);cpu_read(16'h5600);
 if(dut.tfr[2]!==3 || !irq[0]) $fatal(1,"missing final reason/interrupt");
 if(drq || hdd_cmd_req) $fatal(1,"packet did not complete");
 /* Intermediate phases must remain data phases until firmware publishes the next. */
 guest(7,16'ha000);regwrite(2,1);status(8'h24);
 for(i=0;i<6;i=i+1) guest(0,i);
 for(i=0;i<6;i=i+1) begin hdd_data_rd=1;ticks(2);hdd_data_rd=0;ticks(3);end
 status(8'h28);regwrite(2,2);regwrite(4,2);regwrite(5,0);fwdata(16'h789a);status(8'h10);
 ack=1;ticks(2);ack=0;cpu_read(16'h789a);
 if(irq[0]) $fatal(1,"intermediate drain raised completion IRQ");
 if(dut.tfr[2]!==2) $fatal(1,"intermediate phase falsely reports command completion");
 /* Timeout must discard an unread FIFO and allow a fresh command. */
 regwrite(4,2);regwrite(5,0);fwdata(16'hdead);status(8'h10);
 status(8'hd1);
 if(drq || hdd_cmd_req || !dut.fifo_empty) $fatal(1,"abort failed to flush pending data");
 /* Repeated PACKET commands must be distinguishable after guest abort. */
 guest(7,16'ha000); hdd_addr=7;ticks(2);oldgen=hdd_data_in[15:10];
 guest(7,16'ha000);hdd_addr=7;ticks(2);
 if(hdd_data_in[15:10]==oldgen) $fatal(1,"SPI cannot detect a replaced PACKET command");
 /* Controller reset during a partial command must clear every transfer state. */
 status(8'h24);guest(0,16'hbeef);reset=1;ticks(3);reset=0;ticks(3);
 if(drq || hdd_cmd_req || hdd_dat_req) $fatal(1,"reset left a transfer active");
 /* Existing ATA data-in: one 512-byte sector, no packet count threshold. */
 guest(2,16'h0100);guest(7,16'h2000);status(8'h08);
 for(i=0;i<256;i=i+1) fwdata(i);
 if(!drq) $fatal(1,"ATA sector did not raise DRQ");
 status(8'h90);
 for(i=0;i<256;i=i+1) cpu_read(i);
 if(drq || hdd_cmd_req) $fatal(1,"ATA read did not complete");
 /* Existing ATA data-out. */
 guest(2,16'h0100);guest(7,16'h3000);status(8'h04);
 for(i=0;i<256;i=i+1) guest(0,i);
 if(!hdd_dat_req) $fatal(1,"ATA write did not fill the sector buffer");
 for(i=0;i<256;i=i+1) begin
     hdd_addr=0;ticks(2);if(hdd_data_in!==i) $fatal(1,"ATA write data mismatch");
     hdd_data_rd=1;ticks(2);hdd_data_rd=0;ticks(3);
 end
 status(8'h90);
 if(drq || hdd_cmd_req) $fatal(1,"ATA write did not complete");
 $display("PASS: packet phases, odd count, abort/reset, command generation and ATA read/write");$finish;
end
initial begin #200000; $fatal(1,"timeout");end
endmodule
