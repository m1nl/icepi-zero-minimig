`timescale 1ns/1ps

module avi_checksum_case #(parameter PROFILE = 0)(input [7:0] vic);
    wire [23:0] header;
    wire [55:0] sub_0, sub_1, sub_2, sub_3;
    wire [223:0] body = {sub_3, sub_2, sub_1, sub_0};
    auxiliary_video_information_info_frame #(
        .IT_CONTENT(PROFILE != 0),
        .VIDEO_FORMAT(PROFILE == 2 ? 2'b10 : 2'b00),
        .ACTIVE_FORMAT_INFO_PRESENT(PROFILE == 2),
        .BAR_INFO(PROFILE == 2 ? 2'b11 : 2'b00),
        .SCAN_INFO(PROFILE == 2 ? 2'b11 : 2'b00),
        .COLORIMETRY(PROFILE == 2 ? 2'b10 : 2'b00),
        .PICTURE_ASPECT_RATIO(PROFILE == 2 ? 2'b01 : 2'b00),
        .EXTENDED_COLORIMETRY(PROFILE == 2 ? 3'b101 : 3'b000),
        .RGB_QUANTIZATION_RANGE(PROFILE == 2 ? 2'b10 : 2'b00),
        .NON_UNIFORM_PICTURE_SCALING(PROFILE == 2 ? 2'b10 : 2'b00),
        .YCC_QUANTIZATION_RANGE(PROFILE == 2 ? 2'b01 : 2'b00),
        .CONTENT_TYPE(PROFILE == 2 ? 2'b11 : 2'b00),
        .PIXEL_REPETITION(PROFILE == 2 ? 4'hf : 4'h0)
    ) dut (vic, header, sub_0, sub_1, sub_2, sub_3);

    task check;
        integer sum, i;
        begin
            sum = 0;
            for (i = 0; i < 3; i = i + 1)
                sum = sum + header[i*8 +: 8];
            for (i = 0; i <= 13; i = i + 1)
                sum = sum + body[i*8 +: 8];
            if ((sum & 255) !== 0 || body[4*8 +: 8] !== vic)
                $fatal(1, "AVI checksum/VIC mismatch: profile=%0d VIC=%0d", PROFILE, vic);
        end
    endtask
endmodule

module avi_checksum_tb;
    reg [7:0] vic;
    avi_checksum_case defaults (vic);
    avi_checksum_case #(.PROFILE(1)) core_defaults (vic);
    avi_checksum_case #(.PROFILE(2)) custom_fields (vic);
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            vic = i[7:0];
            #1;
            defaults.check();
            core_defaults.check();
            custom_fields.check();
        end
        $display("PASS: AVI checksum for all 256 VICs, default/core/custom fields and bar bytes");
        $finish;
    end
endmodule
