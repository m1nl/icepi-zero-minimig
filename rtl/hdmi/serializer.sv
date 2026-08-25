module serializer
#(
    parameter int NUM_CHANNELS = 3
)
(
    input  logic clk_pixel,
    input  logic clk_pixel_x5,
    input  logic reset,

    input  logic [9:0] tmds_internal [NUM_CHANNELS-1:0],

    output logic [2:0] tmds,
    output logic       tmds_clock
);

    // Modulo-5 counter in the 5x domain drives load vs shift
    logic [2:0] bit_cnt;

    always_ff @(posedge clk_pixel_x5, posedge reset) begin
        if (reset)
            bit_cnt <= 3'd0;
        else
            bit_cnt <= (bit_cnt == 3'd4) ? 3'd0 : bit_cnt + 3'd1;
    end

    // ----------------------------------------------------
    // Data channels
    // ----------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i++) begin : g_ser
            logic [9:0] shift;

            always_ff @(posedge clk_pixel_x5) begin
                if (reset)
                    shift <= 10'b0;
                else if (bit_cnt == 3'd4)
                    shift <= tmds_internal[i];   // load at end of each pixel period
                else
                    shift <= {2'b0, shift[9:2]}; // shift by 2: DDR outputs 2 bits per cycle
            end

            ODDRX1F u_oddr (
                .Q    (tmds[i]),
                .D0   (shift[0]),     // bit on rising edge
                .D1   (shift[1]),     // bit on falling edge
                .SCLK (clk_pixel_x5),
                .RST  (reset)
            );
        end
    endgenerate

    // ----------------------------------------------------
    // TMDS clock channel (50% duty cycle at pixel rate)
    // ----------------------------------------------------
    logic [9:0] clk_shift;

    always_ff @(posedge clk_pixel_x5) begin
        if (reset)
            clk_shift <= 10'b0;
        else if (bit_cnt == 3'd4)
            clk_shift <= 10'b0000011111;
        else
            clk_shift <= {2'b0, clk_shift[9:2]};
    end

    ODDRX1F u_clk (
        .Q    (tmds_clock),
        .D0   (clk_shift[0]),
        .D1   (clk_shift[1]),
        .SCLK (clk_pixel_x5),
        .RST  (reset)
    );

endmodule
