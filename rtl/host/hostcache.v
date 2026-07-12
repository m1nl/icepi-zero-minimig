// Host cache
// Direct-mapped, 128 cachelines x 4 words = 512 x 32-bit data (fits one DP16KD)
// 16-bit SDRAM interface, 8-beat burst per cacheline fill
// Cache index: a[10:4] (7 bits, 128 lines), word-in-line: a[3:2], tag: a[25:4] (22 bits)
// --------------------------------------------------------------------------------------
// This implementation uses output register with tag RAM memory - address has to
// be stable BEFORE req is asserted and has to stay stable until ack is received
// --------------------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none
module hostcache
(
  input  wire        sysclk,
  input  wire        reset_n,
  input  wire [25:2] a,
  output wire [31:0] q,
  input  wire        req,
  input  wire        wr,
  output reg         ack,
  input  wire [15:0] sdram_d,
  output reg         sdram_req,
  input  wire        sdram_ack
);

// Data RAM: 512 x 32-bit, fits one DP16KD
reg [31:0] data_mem [0:511] /* synthesis syn_ramstyle="block_ram" */;
reg [31:0] data_q;
reg [31:0] data_w;
reg        data_wren;

// Tag RAM: 128 x 32-bit
// bit 31: valid, bits 21:0: tag = a[25:4]
wire [31:0] tag_w;

reg [31:0] tag_mem [0:127] /* synthesis syn_ramstyle="block_ram" */;
reg [31:0] tag_q_i;
reg [31:0] tag_q;
reg        tag_wren;
reg        tag_mark;

reg [1:0] write_offset;
reg       zinitcache;
reg [6:0] zinitctr;

localparam zINIT   = 4'd0,  zWAIT   = 4'd1,  zREAD   = 4'd2,  zPAUSE  = 4'd3;
localparam zWRITE  = 4'd4,  zFLUSH2 = 4'd5,  zFILL1  = 4'd6,  zFILL2  = 4'd7;
localparam zFILL3  = 4'd8,  zFILL4  = 4'd9,  zFILL5  = 4'd10, zFILL6  = 4'd11;
localparam zFILL7  = 4'd12, zFILL8  = 4'd13;

reg [3:0] zstate;
reg       complete;

// Combinatorial address generation
wire [8:0] data_addr = {a[10:4], data_wren ? write_offset : a[3:2]};
wire [6:0] tag_addr  = zinitcache ? zinitctr : a[10:4];

// Single-port writethrough synchronous data RAM
always @(posedge sysclk) begin
  if (data_wren) begin
    data_mem[data_addr] <= data_w;
    data_q <= data_w;

  end else begin
    data_q <= data_mem[data_addr];
  end
end

// Single-port synchronous tag RAM with output buffer
always @(posedge sysclk) begin
  if (tag_wren) tag_mem[tag_addr] <= tag_w;
  tag_q_i <= tag_mem[tag_addr];
end
always @(posedge sysclk) begin
  tag_q <= tag_q_i;
end

wire tag_valid = tag_q[31];
wire tag_match = tag_q[21:0] == a[25:4];
wire tag_hit   = tag_valid && tag_match;

assign q     = data_q;
assign tag_w = {tag_mark, 9'b0, a[25:4]};

always @(posedge sysclk) begin
  zinitcache <= 1'b0;
  data_wren  <= 1'b0;
  tag_mark   <= 1'b0;
  tag_wren   <= 1'b0;
  ack        <= 1'b0;

  if (sdram_req)       complete = 1'b0;
  else if (!sdram_ack) complete = 1'b1;

  case (zstate)

    zINIT : begin
      zinitcache <= 1'b1;
      zinitctr   <= 7'h01;
      tag_wren   <= 1'b1;
      zstate     <= zFLUSH2;
    end

    zFLUSH2 : begin
      zinitcache <= 1'b1;
      zinitctr   <= zinitctr + 1'd1;
      tag_wren   <= 1'b1;

      if (zinitctr == 7'h00)
        zstate <= zWAIT;
    end

    zWAIT : begin
      write_offset <= a[3:2];
      if (req) begin
        if (wr) begin
          if (complete) begin
            sdram_req <= 1'b1;
            zstate    <= zWRITE;
          end
        end else begin
          zstate <= zREAD;
        end
      end
    end

    zWRITE : begin
      if (tag_match) begin
        tag_wren <= 1'b1;
      end
      if (sdram_ack) begin
        sdram_req <= 1'b0;
        ack       <= 1'b1;
        zstate    <= zPAUSE;
      end
    end

    zREAD : begin
      if (tag_hit) begin
        ack    <= 1'b1;
        zstate <= zPAUSE;
      end else begin
        if (complete) begin
          sdram_req <= 1'b1;
          zstate    <= zFILL1;
        end
      end
    end

    zPAUSE : begin
      if (!req)
        zstate <= zWAIT;
    end

    zFILL1 : begin
      data_w[31:16] <= sdram_d;
      if (sdram_ack) begin
        sdram_req <= 1'b0;
        zstate    <= zFILL2;
      end
    end

    zFILL2 : begin
      tag_mark     <= 1'b1;
      tag_wren     <= 1'b1;
      data_w[15:0] <= sdram_d;
      data_wren    <= 1'b1;
      zstate       <= zFILL3;
    end

    zFILL3 : begin
      write_offset  <= write_offset + 1'd1;
      data_w[31:16] <= sdram_d;
      zstate        <= zFILL4;
    end

    zFILL4 : begin
      data_w[15:0] <= sdram_d;
      data_wren    <= 1'b1;
      zstate       <= zFILL5;
    end

    zFILL5 : begin
      write_offset  <= write_offset + 1'd1;
      data_w[31:16] <= sdram_d;
      zstate        <= zFILL6;
    end

    zFILL6 : begin
      data_w[15:0] <= sdram_d;
      data_wren    <= 1'b1;
      zstate       <= zFILL7;
    end

    zFILL7 : begin
      write_offset  <= write_offset + 1'd1;
      data_w[31:16] <= sdram_d;
      zstate        <= zFILL8;
    end

    zFILL8 : begin
      data_w[15:0] <= sdram_d;
      data_wren    <= 1'b1;
      zstate       <= zWAIT;
    end

    default:
      zstate <= zWAIT;
  endcase

  if (!reset_n)
    zstate <= zINIT;
end

endmodule
// vim:ts=2 sw=2 tw=120 et
