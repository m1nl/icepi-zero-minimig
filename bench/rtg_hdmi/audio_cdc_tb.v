`timescale 1ns/1ps
module audio_cdc_tb;
    reg src=0, dst=0, sample_en=0;
    always #17.5 src=~src;
    real half_period=7.575757;
    always begin #(half_period) dst=~dst; end
    reg [15:0] left=0;
    wire [31:0] sample;
    audio_cdc dut (.clk(src),.clk_pixel(dst),
        .audio_l(left),.audio_r(~left),.sample_en(sample_en),.sample(sample));
    always @(posedge src) left<=left+1'b1;
    reg [31:0] captured, held;
    integer i, j;
    task sample_mode;
        input real period;
        begin
            half_period=period;
            for(i=0;i<8;i=i+1) begin
                // The previous pair remains held until HDMI samples it.
                held=sample;
                repeat(1400) @(negedge dst);
                if(sample!==held) $fatal(1,"pair changed without acknowledgement");
                sample_en=1;
                @(posedge dst);captured=sample;
                if(captured[31:16]!==~captured[15:0])
                    $fatal(1,"incoherent stereo capture");
                @(negedge dst);sample_en=0;
                repeat(6) @(negedge src);
                if(sample[31:16]!==~sample[15:0] || sample===held)
                    $fatal(1,"acknowledgement failed to refresh stereo pair");
            end
        end
    endtask
    initial begin
        // The current interface has no reset or HDL initial values. Seed the
        // handshake only at simulation startup; this tests CDC operation,
        // not whether FPGA configuration supplies these initial values.
        dut.sample_ack=0;
        dut.sample_ack_sync=0;
        dut.sample_ack_seen=0;
        dut.sample=32'hffff0000;
        #100;
        sample_mode(7.575757);
        held=sample;
        #100;
        if(sample!==held) $fatal(1,"clock switch changed held pair without acknowledgement");
        sample_mode(17.5);
        $display("PASS: coherent held audio, acknowledgement CDC and pixel clock switch");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
