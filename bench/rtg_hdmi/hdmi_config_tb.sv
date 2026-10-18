`timescale 1ns/1ps
// Full-frame checks of a second raster, including the non-power-of-four wrap,
// positive sync polarity and a nonzero CEA identification code.
module hdmi_config_tb;
    hdmi_reset_tb #(
        .FW(1650),.FH(750),.SW(1280),.SH(720),
        .HS_START(110),.HS_SIZE(40),.VS_START(5),.VS_SIZE(5),
        .POLARITY(2'b00),.CEA_MODE(8'd4),.PIXEL_HZ(74250000)
    ) profile_720p ();
endmodule
