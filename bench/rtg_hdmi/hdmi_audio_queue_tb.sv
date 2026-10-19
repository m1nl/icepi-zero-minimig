`timescale 1ns/1ps

module hdmi_audio_queue_case #(parameter BITS = 16)(output reg done = 0);
    reg clk = 0, reset = 1, field_end = 0;
    reg packet_enable = 0, island = 0, sample_en = 0;
    reg [BITS-1:0] sample_left = 0, sample_right = 0;
    wire [23:0] header;
    wire [55:0] sub_0, sub_1, sub_2, sub_3;
    wire [55:0] subs [0:3];
    assign subs[0] = sub_0;
    assign subs[1] = sub_1;
    assign subs[2] = sub_2;
    assign subs[3] = sub_3;
    wire [4:0] counter;
    wire [8:0] packet_data;
    wire overflow;
    always #5 clk = ~clk;

    packet_picker #(.AUDIO_BIT_WIDTH(BITS), .AUDIO_RATE(48000)) picker (
        .clk_pixel(clk), .reset(reset), .video_field_end(field_end), .video_id_code(8'd0),
        .packet_enable(packet_enable), .packet_pixel_counter(counter),
        .audio_sample_word_0(sample_left), .audio_sample_word_1(sample_right),
        .audio_sample_en(sample_en), .header(header),
        .sub_0(sub_0), .sub_1(sub_1), .sub_2(sub_2), .sub_3(sub_3),
        .audio_overflow(overflow)
    );
    packet_assembler assembler (
        .clk_pixel(clk), .reset(reset), .data_island_period(island), .header(header),
        .sub_0(sub_0), .sub_1(sub_1), .sub_2(sub_2), .sub_3(sub_3),
        .packet_data(packet_data), .counter(counter)
    );

    // Independent sample FIFO model. Four samples remain occupied until the
    // complete audio packet has actually crossed the assembler output.
    reg [BITS-1:0] expected_left [0:4095], expected_right [0:4095];
    integer written = 0, consumed = 0, dropped = 0, packets = 0;
    integer accepted_on_finish = 0, aborted = 0;
    integer expected_frame = 0;
    reg expected_overflow = 0, transmitting = 0;
    reg [63:0] serialized [0:3];
    reg [31:0] serialized_header;
    integer lane;

    function automatic [7:0] body_ecc(input [55:0] data);
        reg [7:0] ecc;
        integer bit_index;
        begin
            ecc = 0;
            for (bit_index = 0; bit_index < 56; bit_index = bit_index + 1)
                ecc = (ecc >> 1) ^ ((ecc[0] ^ data[bit_index]) ? 8'h83 : 8'h00);
            body_ecc = ecc;
        end
    endfunction
    function automatic [7:0] header_ecc(input [23:0] data);
        reg [7:0] ecc;
        integer bit_index;
        begin
            ecc = 0;
            for (bit_index = 0; bit_index < 24; bit_index = bit_index + 1)
                ecc = (ecc >> 1) ^ ((ecc[0] ^ data[bit_index]) ? 8'h83 : 8'h00);
            header_ecc = ecc;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            written = 0;
            consumed = 0;
            dropped = 0;
            expected_overflow = 0;
            transmitting = 0;
            expected_frame = 0;
        end else begin
            if (island && header[7:0] == 8'd2) begin
                if (counter == 0) begin
                    if (written - consumed < 4)
                        $fatal(1, "Audio packet without four queued samples (%0d bits)", BITS);
                    if (header[23:20] !== (expected_frame == 0 ? 4'b0001 : 4'b0000))
                        $fatal(1, "IEC frame-start indication lost across queue/abort/reset");
                    transmitting = 1;
                end
                if (!transmitting)
                    $fatal(1, "Audio packet started at a nonzero counter");
                // All four payloads must remain stable, even during capture.
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (subs[lane][23:0] !== (24'(expected_left[consumed+lane]) << (24-BITS)) ||
                        subs[lane][47:24] !== (24'(expected_right[consumed+lane]) << (24-BITS)))
                        $fatal(1, "Audio ordering/stability: bits=%0d packet=%0d pixel=%0d lane=%0d", BITS, packets, counter, lane);
                    serialized[lane][2*counter +: 2] = {packet_data[lane+5], packet_data[lane+1]};
                end
                serialized_header[counter] = packet_data[0];
                if (counter == 31) begin
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        if (serialized[lane][55:0] !== subs[lane] ||
                            serialized[lane][63:56] !== body_ecc(serialized[lane][55:0]))
                            $fatal(1, "Serialized audio payload/BCH mismatch");
                    end
                    if (serialized_header[23:0] !== header ||
                        serialized_header[31:24] !== header_ecc(serialized_header[23:0]))
                        $fatal(1, "Serialized audio header/BCH mismatch");
                    consumed = consumed + 4;
                    packets = packets + 1;
                    expected_frame = (expected_frame + 4) % 192;
                    transmitting = 0;
                    if (sample_en)
                        accepted_on_finish = accepted_on_finish + 1;
                end
            end
            if (field_end && transmitting) begin
                transmitting = 0;
                aborted = aborted + 1;
            end
            if (sample_en) begin
                if (written - consumed == 12) begin
                    dropped = dropped + 1;
                    expected_overflow = 1;
                end else begin
                    expected_left[written] = sample_left;
                    expected_right[written] = sample_right;
                    written = written + 1;
                end
            end
        end
        #1;
        if (overflow !== expected_overflow)
            $fatal(1, "Audio overflow flag mismatch");
    end

    integer next_sample = 1;
    task drive_sample;
        begin
            sample_left = BITS'(next_sample * 32'h10203);
            sample_right = BITS'((next_sample * 32'h50709) ^ 32'ha5c39b71);
            next_sample = next_sample + 1;
        end
    endtask
    task capture(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(negedge clk);
                drive_sample();
                sample_en = 1;
                @(negedge clk);
                sample_en = 0;
            end
        end
    endtask
    // Packet selection occurs one clock before its first data pixel. Consecutive
    // packets are selected while the previous packet presents pixel 31.
    task burst(input integer count, input bit capture_on_finish);
        integer pixel;
        begin
            @(negedge clk);
            packet_enable = 1;
            @(negedge clk);
            packet_enable = 0;
            island = 1;
            for (pixel = 0; pixel < count*32; pixel = pixel + 1) begin
                packet_enable = pixel % 32 == 31 && pixel != count*32-1;
                sample_en = capture_on_finish && pixel == 31;
                if (sample_en)
                    drive_sample();
                @(negedge clk);
            end
            packet_enable = 0;
            sample_en = 0;
            island = 0;
        end
    endtask
    task drain;
        integer attempts;
        begin
            attempts = 0;
            while (written - consumed >= 4 && attempts < 16) begin
                burst(1, 0);
                attempts = attempts + 1;
            end
            if (written - consumed >= 4)
                $fatal(1, "Queued audio failed to drain");
        end
    endtask
    task abort_audio(input bit reset_queue);
        begin
            @(negedge clk);
            packet_enable = 1;
            @(negedge clk);
            packet_enable = 0;
            island = 1;
            repeat (8) @(negedge clk);
            if (!transmitting)
                $fatal(1, "Abort test did not select an audio packet");
            if (reset_queue) reset = 1;
            else field_end = 1;
            @(negedge clk);
            island = 0;
            field_end = 0;
            reset = 0;
            @(negedge clk);
        end
    endtask

    integer iteration;
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        // Fill all three banks while no data islands are available. Overrun
        // must reject incoming samples without changing any queued payload.
        capture(12);
        capture(3);
        if (dropped != 3) $fatal(1, "Full queue did not reject three samples");
        burst(3, 1);
        if (accepted_on_finish == 0)
            $fatal(1, "Full-bank release/capture overlap not exercised");
        capture(3);
        drain();
        // One complete packet plus three samples: commit the next packet on
        // the exact clock that releases the transmitting packet.
        capture(7);
        burst(1, 1);
        drain();
        // Field-end abort retries the head; reset instead flushes all metadata.
        capture(4);
        abort_audio(0);
        if (aborted == 0) $fatal(1, "Field-end abort was not exercised");
        drain();
        capture(7);
        abort_audio(1);
        capture(4);
        drain();
        // Wrap bank pointers and the 192-sample IEC frame repeatedly.
        for (iteration = 0; iteration < 64; iteration = iteration + 1) begin
            capture(8);
            burst(3, 0);
            drain();
        end
        if (written != consumed || expected_overflow)
            $fatal(1, "Queue did not drain cleanly after reset");
        $display("PASS: %0d-bit LUTRAM audio queue, ordering, serialization/BCH, overlap, full, abort/reset and wrap", BITS);
        done = 1;
    end
endmodule

module hdmi_audio_queue_tb;
    wire done_16, done_24;
    hdmi_audio_queue_case #(.BITS(16)) stereo_16(done_16);
    hdmi_audio_queue_case #(.BITS(24)) stereo_24(done_24);
    initial begin
        wait (done_16 && done_24);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Audio queue test timeout");
    end
endmodule
