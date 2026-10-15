`timescale 1ns/1ps
module rtg_fifo_reset_tb;
    reg wr_clk = 0, rd_clk = 0;
    reg wr_running = 1, rd_running = 1;
    always #4.375 if (wr_running) wr_clk = ~wr_clk;
    always #7.575 if (rd_running) rd_clk = ~rd_clk;
    reg reset = 1, wr_en = 0, rd_en = 0;
    reg [15:0] wr_data = 0;
    wire [15:0] rd_data;
    wire full, empty, wr_busy, rd_busy;
    wire [4:0] used;
    rtg_async_fifo #(.ADDR_BITS(4)) dut (
        .wr_clk(wr_clk), .rd_clk(rd_clk), .reset(reset),
        .wr_en(wr_en), .wr_data(wr_data), .rd_en(rd_en), .rd_data(rd_data),
        .full(full), .empty(empty), .wr_used(used),
        .wr_reset_busy(wr_busy), .rd_reset_busy(rd_busy)
    );
    task write_word;
        input [15:0] value;
        begin
            @(negedge wr_clk); wr_data = value; wr_en = 1;
            @(negedge wr_clk); wr_en = 0;
        end
    endtask
    task read_word;
        input [15:0] expected;
        begin
            @(negedge rd_clk);
            if (empty || rd_busy) $fatal(1, "read before FIFO ready");
            rd_en = 1;
            @(posedge rd_clk); #1;
            if (rd_data !== expected) $fatal(1, "read %h expected %h", rd_data, expected);
            @(negedge rd_clk); rd_en = 0;
        end
    endtask
    integer i;
    initial begin
        #100; reset = 0;
        repeat (8) @(negedge rd_clk);
        for (i = 0; i < 8; i = i + 1) write_word(16'h1000 + i);
        repeat (4) @(negedge rd_clk);
        read_word(16'h1000);
        // Assert reset while both clocks are stopped. Pointer reset must
        // work without an edge, and RAM contents must not be cleared.
        @(negedge wr_clk); wr_running = 0;
        @(negedge rd_clk); rd_running = 0;
        #3; reset = 1; #1;
        if (!wr_busy || !rd_busy || dut.wr_bin !== 0 || dut.rd_bin !== 0 ||
            dut.wr_gray !== 0 || dut.rd_gray !== 0 || !empty || used !== 0)
            $fatal(1, "reset failed with stopped clocks");
        if (dut.ram[1] !== 16'h1001) $fatal(1, "reset changed RAM contents");
        #3; reset = 0; #20;
        if (!wr_busy || !rd_busy) $fatal(1, "reset released without clock edges");
        wr_running = 1;
        @(posedge wr_clk); #1;
        if (!wr_busy) $fatal(1, "write reset released before second edge");
        @(posedge wr_clk); #1;
        if (wr_busy || !rd_busy) $fatal(1, "reset releases must be independent");
        write_word(16'hbeef);
        rd_running = 1;
        @(posedge rd_clk); #1;
        if (!rd_busy) $fatal(1, "read reset released before second edge");
        @(posedge rd_clk); #1;
        if (rd_busy) $fatal(1, "read reset did not release");
        repeat (4) @(negedge rd_clk);
        read_word(16'hbeef);
        repeat (4) @(negedge wr_clk);
        if (!empty || used !== 0) $fatal(1, "stale data remained after reset");
        $display("PASS: asynchronous FIFO reset, stopped clocks, independent release and data restart");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
