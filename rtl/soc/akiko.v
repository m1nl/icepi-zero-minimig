// ---------------------------------------------------------------------------
// Copyright 2026 Mateusz Nalewajski
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later
// ---------------------------------------------------------------------------
// Based on cornerturn.vhd by Alastair M. Robinson, converted to make use of
// distributed RAM with a cost of 4 cycles spend to produce a single output
// word (which is still okay assuming clk is 28MHz x 4).
// ---------------------------------------------------------------------------

module akiko (
  input             clk,
  input             reset_n,
  input       [5:0] addr,
  input             wr,
  input             req,
  output reg        ack,
  input      [15:0] d,
  output reg [15:0] q
);

reg [3:0] wrptr;
reg [3:0] rdptr;
reg [2:0] rdidx;

reg [7:0] mem0 [0:15];
reg [7:0] mem1 [0:15];

reg [15:0] shifter;
reg        done;
reg        armed;

wire [3:0] rdaddr = {rdptr[0], rdidx};

wire [7:0] mem0_out = mem0[rdaddr];
wire [7:0] mem1_out = mem1[rdaddr];

wire wrreq =  wr && req && !ack;
wire rdreq = !wr && req && !ack;

always @(posedge clk) begin
  if (!reset_n) begin
    wrptr <= 0;
    done  <= 0;
    armed <= 0;
    ack   <= 0;

  end else begin
    if (!req)
      ack <= 0;

    if (wrreq) begin
      casez (addr)
        6'b1110zz: begin
          wrptr <= wrptr + 1;
          rdptr <= 0;
          rdidx <= 0;
          done  <= 0;
          armed <= 0;

          mem0[wrptr] <= d[ 7:0];
          mem1[wrptr] <= d[15:8];

          if (wrptr == 15)
              armed <= 1;

          ack <= 1;
        end
        default:begin
            ack <= 1;
        end
      endcase

    end else if (rdreq) begin
      casez (addr)
        6'b00000z: begin
          q   <= 16'hC0CA;
          ack <= 1;
        end
        6'b00001z: begin
          q   <= 16'hCAFE;
          ack <= 1;
        end
        6'b1110zz: begin
          wrptr <= 0;
          done  <= 0;
          armed <= 1;

          if (done) begin
            q   <= shifter;
            ack <= 1;
          end
        end
        default: begin
          ack <= 1;
        end
      endcase
    end

    if (armed && !done) begin
      rdidx <= rdidx + 1;

      shifter[15:2] <= shifter[13:0];
      shifter[0]    <= mem0_out[rdptr[3:1]];
      shifter[1]    <= mem1_out[rdptr[3:1]];

      if (rdidx == 7) begin
        rdptr <= rdptr + 1;
        done  <= 1;
      end
    end
  end
end

endmodule
// vim:ts=2 sw=2 tw=120 et
