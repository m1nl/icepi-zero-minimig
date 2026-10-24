// Four posted CPU writes, all in the controller's sysclk domain.
// Input request/acknowledge are toggles; output is a valid/ready handshake.
// Only the newest queued entry may merge, preserving ordering around other
// addresses. A head consumed this clock is immutable, including its byte masks.
`default_nettype none
module sdram_write_queue (
  input wire clk,
  input wire rst,             // active high: discard queue on SDRAM reset
  input wire source_reset,    // reset source handshake, retain accepted writes

  input wire req,
  output reg ack,

  input wire [25:1] addr,
  input wire [31:0] data,
  input wire  [3:0] dqm,

  output wire valid,
  input wire  ready,

  output wire [25:1] head_addr,
  output wire [31:0] head_data,
  output wire  [3:0] head_dqm
);

reg [25:1] addresses [0:3];
reg [31:0] payloads [0:3];
reg  [3:0] masks [0:3];

reg  [1:0] rd_ptr, wr_ptr;
reg  [2:0] count;

wire [1:0] tail = wr_ptr - 2'd1;

wire pop = valid && ready;
wire merge_tail = valid && addresses[tail] == addr &&
                  !(count == 1 && pop);

wire accept = !source_reset && (req != ack) &&
              (merge_tail || count != 3'd4 || pop);

wire push = accept && !merge_tail;

integer lane;

assign valid = count != 0;
assign head_addr = addresses[rd_ptr];
assign head_data = payloads[rd_ptr];
assign head_dqm = masks[rd_ptr];

always @(posedge clk) begin
  if (rst) begin
    ack <= 1'b0;
    rd_ptr <= 0;
    wr_ptr <= 0;
    count <= 0;

  end else begin
    if (source_reset) ack <= 1'b0;
    else if (accept) ack <= req;
    if (pop) rd_ptr <= rd_ptr + 2'd1;
    if (push) begin
      addresses[wr_ptr] <= addr;
      payloads[wr_ptr] <= data;
      masks[wr_ptr] <= dqm;
      wr_ptr <= wr_ptr + 1;

    end else if (accept) begin
      for (lane = 0; lane < 4; lane = lane + 1)
        if (!dqm[lane])
          payloads[tail][lane*8 +: 8] <= data[lane*8 +: 8];
      masks[tail] <= masks[tail] & dqm;
    end

    case ({push, pop})
      2'b10: count <= count + 1;
      2'b01: count <= count - 1;
      default: ;
    endcase
  end
end

endmodule
`default_nettype wire
// vim:ts=2 sw=2 tw=120 et
