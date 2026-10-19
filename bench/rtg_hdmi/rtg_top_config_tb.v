`timescale 1ns/1ps
// Unrelated VHDL peripherals may remain unbound during this elaboration check.
module rtg_top_config_tb;
    minimig_virtual_top #(.havertg(1)) dut ();

    initial begin
        #1;
        if (dut.gen_rtg.rtg.PREPARE_DELAY != 4096)
            $fatal(1,"RTG fixed preparation delay is incorrect");
        $display("PASS: raster-independent RTG retains the 4096-cycle delay");
        $finish;
    end
endmodule
