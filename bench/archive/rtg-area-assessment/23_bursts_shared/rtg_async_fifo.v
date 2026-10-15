// Dual-clock video FIFO. RAM contents are never reset, allowing ECP5 EBR inference.
module rtg_fifo_control #(
    parameter ADDR_BITS = 9,
    parameter DATA_BITS = 16
) (
    input wr_clk, input rd_clk, input reset,
    input wr_en,
    input rd_en,
    output [ADDR_BITS-1:0] wr_addr, rd_addr,
    output wr_accept, rd_accept,
    output full, output empty,
    output [ADDR_BITS:0] wr_used,
    output wr_reset_busy, output rd_reset_busy
);
    reg [1:0] wr_rst = 2'b11, rd_rst = 2'b11;
    always @(posedge wr_clk or posedge reset)
        if (reset) wr_rst <= 2'b11; else wr_rst <= {wr_rst[0],1'b0};
    always @(posedge rd_clk or posedge reset)
        if (reset) rd_rst <= 2'b11; else rd_rst <= {rd_rst[0],1'b0};
    assign wr_reset_busy = wr_rst[1];
    assign rd_reset_busy = rd_rst[1];

    reg [ADDR_BITS:0] wr_bin, rd_bin, wr_gray, rd_gray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_BITS:0] rd_gray_w1, rd_gray_w2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_BITS:0] wr_gray_r1, wr_gray_r2;
    wire [ADDR_BITS:0] wr_next = wr_bin + {{ADDR_BITS{1'b0}},1'b1};
    wire [ADDR_BITS:0] rd_next = rd_bin + {{ADDR_BITS{1'b0}},1'b1};
    assign full = wr_gray == {~rd_gray_w2[ADDR_BITS:ADDR_BITS-1],rd_gray_w2[ADDR_BITS-2:0]};
    assign empty = rd_gray == wr_gray_r2;
    function [ADDR_BITS:0] gray_to_bin;
        input [ADDR_BITS:0] g;
        integer i;
        begin
            gray_to_bin[ADDR_BITS] = g[ADDR_BITS];
            for (i=ADDR_BITS-1;i>=0;i=i-1)
                gray_to_bin[i] = gray_to_bin[i+1] ^ g[i];
        end
    endfunction
    assign wr_used = wr_bin - gray_to_bin(rd_gray_w2);

    always @(posedge wr_clk or posedge reset) begin
        if (reset) begin
            wr_bin <= 0; wr_gray <= 0; rd_gray_w1 <= 0; rd_gray_w2 <= 0;
        end else if (wr_reset_busy) begin
            wr_bin <= 0; wr_gray <= 0; rd_gray_w1 <= 0; rd_gray_w2 <= 0;
        end else begin
            rd_gray_w1 <= rd_gray; rd_gray_w2 <= rd_gray_w1;
            if (wr_en && !full) begin wr_bin <= wr_next; wr_gray <= (wr_next>>1)^wr_next; end
        end
    end
    always @(posedge rd_clk or posedge reset) begin
        if (reset) begin
            rd_bin <= 0; rd_gray <= 0; wr_gray_r1 <= 0; wr_gray_r2 <= 0;
        end else if (rd_reset_busy) begin
            rd_bin <= 0; rd_gray <= 0; wr_gray_r1 <= 0; wr_gray_r2 <= 0;
        end else begin
            wr_gray_r1 <= wr_gray; wr_gray_r2 <= wr_gray_r1;
            if (rd_en && !empty) begin rd_bin <= rd_next; rd_gray <= (rd_next>>1)^rd_next; end
        end
    end
    assign wr_addr = wr_bin[ADDR_BITS-1:0];
    assign rd_addr = rd_bin[ADDR_BITS-1:0];
    assign wr_accept = !wr_reset_busy && wr_en && !full;
    assign rd_accept = !rd_reset_busy && rd_en && !empty;
endmodule
