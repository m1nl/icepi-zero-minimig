module line_ram(input clk, input [2:0] cpu_adr_blk, input [1:0] waddr, input [31:0] din, input [3:0] we, output [15:0] dout);
// cache line cache - instruction
(* ram_style="distributed", syn_ramstyle="distributed" *) reg   [32-1:0] cpu_cacheline_i[0:3];
wire  [32-1:0] cpu_cacheline_i_out = cpu_cacheline_i[cpu_adr_blk[2:1]];
wire  [16-1:0] cpu_cacheline_i_cpu_out = cpu_adr_blk[0] ? cpu_cacheline_i_out[31:16] :
                                                          cpu_cacheline_i_out[15: 0];

reg    [2-1:0] cpu_cacheline_i_waddr;
(* ram_style="distributed", syn_ramstyle="distributed" *) reg   [32-1:0] cpu_cacheline_i_din;
reg    [4-1:0] cpu_cacheline_i_we;

always @(posedge clk) begin
  if (cpu_cacheline_i_we[0])
    cpu_cacheline_i[cpu_cacheline_i_waddr][7:0] <= cpu_cacheline_i_din[7:0];
  if (cpu_cacheline_i_we[1])
    cpu_cacheline_i[cpu_cacheline_i_waddr][15:8] <= cpu_cacheline_i_din[15:8];
  if (cpu_cacheline_i_we[2])
    cpu_cacheline_i[cpu_cacheline_i_waddr][23:16] <= cpu_cacheline_i_din[23:16];
  if (cpu_cacheline_i_we[3])
    cpu_cacheline_i[cpu_cacheline_i_waddr][31:24] <= cpu_cacheline_i_din[31:24];
end


always @* begin cpu_cacheline_i_waddr=waddr; cpu_cacheline_i_din=din; cpu_cacheline_i_we=we; end
assign dout=cpu_cacheline_i_cpu_out;
endmodule
