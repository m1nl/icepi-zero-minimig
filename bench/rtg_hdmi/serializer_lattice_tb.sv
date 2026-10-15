`timescale 1ns/1ps
// Compile with -DLATTICE and Lattice's ODDRX1F.v model.
module GSR_INST;
    wire GSRNET = 1'b1;
endmodule
module PUR_INST;
    wire PURNET = 1'b1;
endmodule
module serializer_lattice_tb;
    reg clk5 = 0, clk_pixel = 0, reset = 1;
    real half_period = 3.5;
    always begin #(half_period) clk5 = ~clk5; end
    always #17.5 clk_pixel = ~clk_pixel;
    wire [9:0] words [2:0];
    assign words[0] = 10'b1101010100;
    assign words[1] = 10'b0010101011;
    assign words[2] = 10'b1011001100;
    wire [2:0] tmds;
    wire tmds_clock;
    serializer #(.VIDEO_RATE(28.5714)) dut (
        .clk_pixel(clk_pixel), .clk_pixel_x5(clk5), .reset(reset),
        .tmds_internal(words), .tmds(tmds), .tmds_clock(tmds_clock)
    );
    reg previous_clock = 0;
    reg [9:0] received [2:0];
    integer bit_index = -1, frames = 0, edges = 0, channel;
    integer ticks_since_load = 0;
    reg acquired = 0;
    always @(posedge clk5) begin
        if (dut.reset_x5) begin
            acquired = 0;
            ticks_since_load = 0;
        end else begin
            if (!acquired && dut.load_word !== dut.pixel_event)
                $fatal(1, "Initial word load moved from the acquisition event");
            if (dut.load_word) begin
                if (acquired && ticks_since_load != 4)
                    $fatal(1, "TMDS word loads must be five fast clocks apart");
                acquired = 1;
                ticks_since_load = 0;
            end else if (acquired) begin
                ticks_since_load = ticks_since_load + 1;
                if (ticks_since_load > 4)
                    $fatal(1, "TMDS periodic word load missing");
            end
        end
    end
    always @(clk5) begin
        #0.01;
        if (reset) begin
            previous_clock = 0;
            bit_index = -1;
            edges = 0;
        end else begin
            edges = edges + 1;
            if (edges > 30) begin
                if (tmds_clock && !previous_clock) bit_index = 0;
                if (bit_index >= 0) begin
                    for (channel = 0; channel < 3; channel = channel + 1)
                        received[channel][bit_index] = tmds[channel];
                    if (bit_index == 9) begin
                        for (channel = 0; channel < 3; channel = channel + 1)
                            if (received[channel] !== words[channel])
                                $fatal(1, "TMDS channel %0d misaligned: got %b expected %b", channel, received[channel], words[channel]);
                        frames = frames + 1;
                        bit_index = -1;
                    end else bit_index = bit_index + 1;
                end
            end
            previous_clock = tmds_clock;
        end
    end
    initial begin
        #100 reset = 0;
        #700;
        if (frames < 8) $fatal(1, "Native TMDS words missing");
        reset = 1;
        #100 half_period = 1.5151515;
        #100 reset = 0;
        #400;
        if (frames < 20) $fatal(1, "RTG TMDS words missing");
        $display("PASS: native and RTG TMDS data/clock word alignment with Lattice DDR model");
        $finish;
    end
endmodule
