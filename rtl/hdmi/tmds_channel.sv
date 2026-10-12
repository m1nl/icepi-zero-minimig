// Implementation of HDMI Spec v1.4a Section 5.4: Encoding, Section 5.2.2.1: Video Guard Band, Section 5.2.3.3: Data Island Guard Bands.
// By Sameer Puri https://github.com/sameer
// Timing refactor and explanatory comments by OpenAI Codex (GPT-6).

module tmds_channel
#(
    // TMDS Channel number.
    // There are only 3 possible channel numbers in HDMI 1.4a: 0, 1, 2.
    parameter int CN = 0
)
(
    input logic clk_pixel,
    input logic [7:0] video_data,
    input logic [3:0] data_island_data,
    input logic [1:0] control_data,
    input logic [2:0] mode,  // Mode select (0 = control, 1 = video, 2 = video guard, 3 = island, 4 = island guard)
    output logic [9:0] tmds = 10'b1101010100
);

// See Section 5.4.4.1
// Implements Figure 5-7 with the following timing-oriented changes:
// - Balanced, explicitly sized bit counts replace chained sums and the redundant
//   count-to-value case decoder.
// - Independent XOR reductions replace the seven-bit XOR/XNOR dependency chain.
//   They can run in parallel with the input bit count; the XOR/XNOR selection
//   then only needs to invert odd-numbered prefix bits.
// - A single signed balance replaces separate ones/zeros counts and repeated
//   subtraction. One shared inversion decision controls both the symbol and
//   the accumulator correction, reducing duplicated branch logic.
// This shortens the RGB-to-disparity-register combinational path without adding
// pipeline registers: acc and tmds still update on the original pixel edge.
// Formal equivalence was checked against the original encoder for CN=0,1,2.

logic signed [4:0] acc = 5'sd0;

logic [8:0] q_m;
logic [9:0] q_out;
logic [9:0] video_coding;
assign video_coding = q_out;

// Explicitly sized, balanced population count: pairs -> nibbles -> byte.
function automatic [3:0] count_ones(input logic [7:0] value);
    logic [1:0] pair0, pair1, pair2, pair3;
    logic [2:0] low_count, high_count;
    begin
        pair0 = {1'b0, value[0]} + {1'b0, value[1]};
        pair1 = {1'b0, value[2]} + {1'b0, value[3]};
        pair2 = {1'b0, value[4]} + {1'b0, value[5]};
        pair3 = {1'b0, value[6]} + {1'b0, value[7]};
        low_count  = {1'b0, pair0} + {1'b0, pair1};
        high_count = {1'b0, pair2} + {1'b0, pair3};
        count_ones = {1'b0, low_count} + {1'b0, high_count};
    end
endfunction

wire [3:0] input_ones = count_ones(video_data);
wire use_xnor = input_ones > 4'd4 ||
                (input_ones == 4'd4 && !video_data[0]);
wire [7:0] xor_prefix;

genvar bit_index;
generate
    for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin : gen_prefix
        // A reduction lets synthesis balance each prefix independently.
        assign xor_prefix[bit_index] = ^video_data[bit_index:0];
    end
endgenerate

// Repeated XNOR differs from XOR only at odd-numbered prefix bits.
assign q_m = {!use_xnor, xor_prefix ^ ({8{use_xnor}} & 8'hAA)};

wire [3:0] encoded_ones = count_ones(q_m[7:0]);
// ones - zeros = 2*ones - 8, in the signed range -8..+8.
// Compare the ones count directly with four instead of computing zeros first.

wire signed [4:0] balance = {encoded_ones, 1'b0} - 5'd8;
wire balanced = encoded_ones == 4'd4;
wire same_sign = (acc[4] && encoded_ones < 4'd4) ||
                 (!acc[4] && encoded_ones > 4'd4);
wire neutral = acc == 5'sd0 || balanced;
wire invert_output = neutral ? !q_m[8] : same_sign;

assign q_out = {neutral ? !q_m[8] : invert_output,
                q_m[8], q_m[7:0] ^ {8{invert_output}}};

// Select the sign once, then apply the 0/+2/-2 correction contributed by the
// two upper TMDS symbol bits. The neutral branch requires no correction.
wire signed [4:0] signed_balance = invert_output ? -balance : balance;
wire signed [4:0] correction = neutral ? 5'sd0 :
    (invert_output ? (q_m[8] ? 5'sd2 : 5'sd0) :
                     (q_m[8] ? 5'sd0 : -5'sd2));

wire signed [4:0] acc_add = signed_balance + correction;

always_ff @(posedge clk_pixel) acc <= mode != 3'd1 ? 5'sd0 : acc + acc_add;

// See Section 5.4.2
logic [9:0] control_coding;
always_comb
begin
    unique case(control_data)
        2'b00: control_coding = 10'b1101010100;
        2'b01: control_coding = 10'b0010101011;
        2'b10: control_coding = 10'b0101010100;
        2'b11: control_coding = 10'b1010101011;
    endcase
end

// See Section 5.4.3
logic [9:0] terc4_coding;
always_comb
begin
    unique case(data_island_data)
        4'b0000 : terc4_coding = 10'b1010011100;
        4'b0001 : terc4_coding = 10'b1001100011;
        4'b0010 : terc4_coding = 10'b1011100100;
        4'b0011 : terc4_coding = 10'b1011100010;
        4'b0100 : terc4_coding = 10'b0101110001;
        4'b0101 : terc4_coding = 10'b0100011110;
        4'b0110 : terc4_coding = 10'b0110001110;
        4'b0111 : terc4_coding = 10'b0100111100;
        4'b1000 : terc4_coding = 10'b1011001100;
        4'b1001 : terc4_coding = 10'b0100111001;
        4'b1010 : terc4_coding = 10'b0110011100;
        4'b1011 : terc4_coding = 10'b1011000110;
        4'b1100 : terc4_coding = 10'b1010001110;
        4'b1101 : terc4_coding = 10'b1001110001;
        4'b1110 : terc4_coding = 10'b0101100011;
        4'b1111 : terc4_coding = 10'b1011000011;
    endcase
end

// See Section 5.2.2.1
logic [9:0] video_guard_band;
generate
    if (CN == 0 || CN == 2)
        assign video_guard_band = 10'b1011001100;
    else
        assign video_guard_band = 10'b0100110011;
endgenerate

// See Section 5.2.3.3
logic [9:0] data_guard_band;
generate
    if (CN == 1 || CN == 2)
        assign data_guard_band = 10'b0100110011;
    else
        assign data_guard_band = control_data == 2'b00 ? 10'b1010001110
            : control_data == 2'b01 ? 10'b1001110001
            : control_data == 2'b10 ? 10'b0101100011
            : 10'b1011000011;
endgenerate

// Apply selected mode.
always @(posedge clk_pixel)
begin
    case (mode)
        3'd0: tmds <= control_coding;
        3'd1: tmds <= video_coding;
        3'd2: tmds <= video_guard_band;
        3'd3: tmds <= terc4_coding;
        3'd4: tmds <= data_guard_band;
        default: ;
    endcase
end

endmodule
