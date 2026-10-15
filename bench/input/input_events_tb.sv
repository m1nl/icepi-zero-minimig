`timescale 1ns/1ps

// Exercise the production 28 MHz event stretcher and both production consumers.
// Unrelated virtual-top peripherals are deliberately not elaborated by the runner.
module input_events_tb;
reg clk = 0;
always #5 clk = ~clk;
reg [1:0] phase = 0;
always @(posedge clk) phase <= phase + 1'b1;
wire clk7_en = phase == 0;
reg reset = 1;
reg event_stb = 0;
reg [15:0] event_data = 0;
reg [15:0] latched_event_data = 0;
reg latched_event_stb = 0;
// Model cfide's registered MMIO event outputs, including nonblocking updates.
always @(posedge clk) begin
    latched_event_stb <= event_stb;
    if (event_stb) latched_event_data <= event_data;
end
reg mouse_idx = 0;
reg keyboard_disabled = 0;
reg [7:0] address = 0;
reg [15:0] bus_data = 0;
wire [15:0] joy_data;
wire key_strobe;
wire [7:0] key_data, osd_ctrl;
wire kbclk, kbdata;
integer key_count = 0;
reg [7:0] last_key;
integer expected_keys = 0;
reg [7:0] expected_x [0:1];
reg [7:0] expected_y [0:1];
reg [7:0] expected_z [0:1];
integer events = 0;
reg burst = 0;
integer burst_received = 0;
reg [7:0] burst_key;

minimig_virtual_top #(.havertg(0), .haveaudio(0)) source ();
initial begin
    // These existing registers have no explicit RTL reset. Seed FPGA power-up
    // state once; subsequent resets and all event transitions use production RTL.
    source.kms_level = 0;
    source.kbd_mouse_stb = 0;
    source.amiga_key_stb_r = 0;
    force source.CLK_28 = clk;
    force source.clk7_en = clk7_en;
    force source.c64_translated_key = latched_event_data;
    force source.c64_translated_key_stb = latched_event_stb;
    force source.AMIGA_KEY_STB = 1'b0;
end

userio mouse (
    .clk(clk), .reset(reset), .clk7_en(clk7_en), .clk7n_en(phase == 2),
    .c1(1'b0), .c3(1'b0), .sol(1'b0), .sof(1'b0),
    .varbeamen(1'b0), .rtg_ena(1'b0),
    .reg_address_in(address), .data_in(bus_data), .data_out(joy_data),
    ._joy1(16'hffff), ._joy2(16'hffff), .joy_ana(16'hffff),
    ._lmb(1'b1), ._rmb(1'b1), .mou_emu(6'h3f), .aflock(1'b0),
    .mouse_idx(mouse_idx), .mouse0_btn(source.mouse0_buttons),
    .mouse1_btn(source.mouse1_buttons),
    .kbd_mouse_strobe(source.kbd_mouse_stb), .kms_level(source.kms_level),
    .kbd_mouse_type(source.kbd_mouse_type), .kbd_mouse_data(source.kbd_mouse_data),
    ._scs(1'b1), .sdi(1'b0), .sck(1'b0), .osd_ctrl(8'd0),
    .host_rdat(16'd0), .host_ack(1'b0), ._fire0_dat(1'b1), ._fire1_dat(1'b1)
);

amiga_keyboard keyboard (
    .clk(clk), .reset(reset), .clk7_en(clk7_en), .clk7n_en(phase == 2),
    .keyboard_disabled(keyboard_disabled),
    .kbd_mouse_strobe(source.kbd_mouse_stb), .kms_level(source.kms_level),
    .kbd_mouse_type(source.kbd_mouse_type), .kbd_mouse_data(source.kbd_mouse_data),
    .key_strobe(key_strobe), .key_data(key_data), .osd_ctrl(osd_ctrl),
    .keyack(1'b0), .hrtmon_en(1'b0), .kbclk(kbclk), .kbdata(kbdata)
);

always @(posedge clk) begin
    if (clk7_en) begin
        #2;
        if (!reset && key_strobe) begin
            key_count = key_count + 1;
            last_key = key_data;
            if (burst) begin
                burst_key = burst_received * 4 + 1;
                if (key_data !== ~{burst_key[6:0], burst_key[7]})
                    $fatal(1, "Lost/reordered burst keyboard event %0d", burst_received);
                burst_received = burst_received + 1;
            end
        end
    end
end

task check_counters;
begin
    if (mouse.mouse0dat !== {expected_y[0], expected_x[0]} ||
        mouse.mouse1dat !== {expected_y[1], expected_x[1]} ||
        mouse.zcount0 !== expected_z[0] || mouse.zcount1 !== expected_z[1])
        $fatal(1, "Mouse mismatch after event %0d: got %h/%h wheel %h/%h expected %h/%h wheel %h/%h",
               events, mouse.mouse0dat, mouse.mouse1dat, mouse.zcount0, mouse.zcount1,
               {expected_y[0], expected_x[0]}, {expected_y[1], expected_x[1]}, expected_z[0], expected_z[1]);
end
endtask

// Keep one full 7 MHz interval between events, allowing the shared single-event
// interface to drain. Firmware keyboard busy handling is outside this RTL bench.
task send_event;
input [1:0] typ;
input [7:0] data;
input [1:0] arrival;
input wheel;
begin
    @(negedge clk);
    while (phase != arrival) @(negedge clk);
    event_data = {typ, 6'b0, data};
    event_stb = 1;
    @(negedge clk);
    event_stb = 0;
    repeat (6) @(negedge clk);
    events = events + 1;
    case (typ)
        0: expected_x[mouse_idx] = expected_x[mouse_idx] + data;
        1: if (wheel) expected_z[mouse_idx] = expected_z[mouse_idx] - data;
           else expected_y[mouse_idx] = expected_y[mouse_idx] + data;
        2: if (!keyboard_disabled) begin
            expected_keys = expected_keys + 1;
            if (last_key !== ~{data[6:0], data[7]})
                $fatal(1, "Wrong keyboard data for %h: %h", data, last_key);
        end
    endcase
    if (key_count != expected_keys)
        $fatal(1, "Lost/duplicate/spurious key after event %0d: got %0d expected %0d", events, key_count, expected_keys);
    if (typ[1] && osd_ctrl !== data)
        $fatal(1, "Lost OSD keyboard event %h", data);
    check_counters;
end
endtask

task reset_consumers;
integer n;
begin
    reset = 1;
    repeat (8) @(negedge clk);
    reset = 0;
    for (n = 0; n < 2; n = n + 1) begin
        expected_x[n] = 0; expected_y[n] = 0; expected_z[n] = 0;
    end
    check_counters;
end
endtask

integer p, d, port;
reg [7:0] serial_key;
integer bitnum;
initial begin
    reset_consumers;
    for (port = 0; port < 2; port = port + 1) begin
        mouse_idx = port;
        for (p = 0; p < 4; p = p + 1) begin
            for (d = 0; d < 256; d = d + 1) begin
                send_event(0, d, p, 0);
                send_event(2, d, p, 0);
                send_event(1, d, p, 0);
                send_event(3, d, p, 0);
                send_event(1, d, p, 1);
            end
            $display("PASS port=%0d arrival phase=%0d: all signed deltas, keys, OSD and wheel", port, p);
        end
    end
    // One event every five bus clocks. The existing interface has no queue:
    // leave a bus clock after the four-clock consumer interval before replacing
    // cfide's data register. This also rotates arrival phase within each burst.
    for (p = 0; p < 4; p = p + 1) begin
        @(negedge clk);
        while (phase != p) @(negedge clk);
        burst = 1;
        burst_received = 0;
        for (d = 0; d < 64; d = d + 1) begin
            case (d % 4)
                0: begin
                    event_data = {2'b00, 6'b0, d[7:0]};
                    expected_x[mouse_idx] = expected_x[mouse_idx] + d;
                end
                1: begin
                    event_data = {2'b10, 6'b0, d[7:0]};
                    expected_keys = expected_keys + 1;
                end
                2: begin
                    event_data = {2'b01, 6'b0, d[7:0]};
                    expected_y[mouse_idx] = expected_y[mouse_idx] + d;
                end
                3: event_data = {2'b11, 6'b0, d[7:0]};
            endcase
            events = events + 1;
            event_stb = 1;
            @(negedge clk); event_stb = 0;
            repeat (4) @(negedge clk);
        end
        repeat (4) @(negedge clk);
        burst = 0;
        if (burst_received != 16 || key_count != expected_keys || osd_ctrl !== 8'd63)
            $fatal(1, "Burst event count/OSD mismatch at phase %0d", p);
        check_counters;
        $display("PASS five-clock event burst, initial arrival phase=%0d", p);
    end
    // Disabled guest keyboard still supplies OSD events; mouse events remain live.
    keyboard_disabled = 1;
    for (p = 0; p < 4; p = p + 1) begin
        send_event(0, 8'h80, p, 0);
        send_event(2, 8'h20, p, 0);
        send_event(1, 8'h7f, p, 0);
        send_event(3, 8'h69, p, 0);
    end
    keyboard_disabled = 0;
    // Reset while a mouse event is pending; hold reset through the strobe so
    // no discarded movement is replayed when the consumers restart.
    for (p = 0; p < 4; p = p + 1) begin
        @(negedge clk);
        while (phase != p) @(negedge clk);
        event_data = 16'h0009;
        event_stb = 1;
        @(negedge clk); event_stb = 0;
        reset_consumers;
        repeat (8) @(negedge clk);
        check_counters;
        send_event(0, 8'd7, p, 0);
        send_event(1, 8'd7, p, 0);
    end
    reset_consumers;
    // The legacy serial transmitter does not reset its private countdown.
    // Drain the earlier parallel-delivery stress traffic before serial checks.
    repeat (9000) @(negedge clk);
    // Check actual serial press/release delivery, allowing the complete serial
    // transmission to finish before sending the next key (as the guest does).
    for (p = 0; p < 4; p = p + 1) begin
        for (d = 0; d < 2; d = d + 1) begin
            send_event(2, d ? 8'ha0 : 8'h20, p, 0);
            for (bitnum = 7; bitnum >= 0; bitnum = bitnum - 1) begin
                @(negedge kbclk);
                serial_key[bitnum] = kbdata;
            end
            if (serial_key !== (d ? 8'hbe : 8'hbf))
                $fatal(1, "Serial key mismatch: %h", serial_key);
            repeat (1100) @(negedge clk);
        end
    end
    $display("PASS %0d events, %0d keyboard deliveries; serial press/release at every phase", events, key_count);
    $finish;
end

initial begin
    #10000000;
    $fatal(1, "Timeout");
end
endmodule
