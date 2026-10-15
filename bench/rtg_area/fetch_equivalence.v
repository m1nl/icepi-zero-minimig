// Exhaustive combinational proof of the fetch decisions for eight-word bursts.
// This does not prove the entire dual-clock scanout state machine.
module fetch_equivalence (
    input [16:0] limit_bursts, issued_bursts,
    input [9:0] used,
    input enable,
    output match
);
    wire [19:0] limit_words = {limit_bursts,3'd0};
    wire [19:0] issued_words = {issued_bursts,3'd0};
    wire [19:0] original_remaining = limit_words > issued_words ? limit_words-issued_words : 20'd0;
    wire original_req = enable && original_remaining >= 8 && used < 480;
    wire original_pri = original_req && used < 256 && original_remaining > 32;

    wire [19:0] raw_remaining = limit_words-issued_words;
    wire fetch_req = enable && issued_words < limit_words && used < 480;
    wire fetch_pri = fetch_req && used < 256 && raw_remaining > 32;

    wire [16:0] remaining_bursts = limit_bursts > issued_bursts ? limit_bursts-issued_bursts : 17'd0;
    wire bursts_req = enable && remaining_bursts >= 1 && used < 480;
    wire bursts_pri = bursts_req && used < 256 && remaining_bursts > 4;

    wire [16:0] raw_bursts = limit_bursts-issued_bursts;
    wire both_req = enable && issued_bursts < limit_bursts && used < 480;
    wire both_pri = both_req && used < 256 && raw_bursts > 4;
    wire [25:0] original_byte_offset = {5'd0,issued_words,1'b0};
    wire [25:0] bursts_byte_offset = {5'd0,issued_bursts,4'd0};

    assign match = {original_req,original_pri} == {fetch_req,fetch_pri} &&
                   {original_req,original_pri} == {bursts_req,bursts_pri} &&
                   {original_req,original_pri} == {both_req,both_pri} &&
                   original_byte_offset == bursts_byte_offset;
endmodule
