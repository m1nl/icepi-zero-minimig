`timescale 1ns/1ps
// Unrelated VHDL peripherals may remain unbound: this checks elaborated RTG
// parameters, not operation of the mixed-language SoC.
module rtg_top_config_tb;
    minimig_virtual_top #(
        .havertg(1),
        .rtg_screen_width(1280),
        .rtg_screen_height(720)
    ) dut ();

    initial begin
        #1;
        if (dut.gen_rtg.rtg.H_ACTIVE != 1280 ||
            dut.gen_rtg.rtg.V_ACTIVE != 720 ||
            dut.gen_rtg.rtg.PREPARE_DELAY != 4096)
            $fatal(1,"RTG dimensions or fixed preparation delay are incorrect");
        $display("PASS: virtual top forwards RTG dimensions and retains the 4096-cycle delay");
        $finish;
    end
endmodule
