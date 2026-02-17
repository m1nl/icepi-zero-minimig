// Usb_hid_host: A compact USB HID host core.
//
// nand2mario, 8/2023, based on work by hi631
// 
// This should support keyboard, mouse and gamepad input out of the box, over low-speed 
// USB (1.5Mbps). Just connect D+, D-, VBUS (5V) and GND, and two 15K resistors between 
// D+ and GND, D- and GND. Then provide a 12Mhz clock through usbclk.
//
// See https://github.com/nand2mario/usb_hid_host
// 

module usb_hid_host (
    input  usbclk,	            // 12MHz clock
    input  usbrst_n,	            // reset
    inout  usb_dm, usb_dp,          // USB D- and D+

    output reg [1:0] typ,           // device type. 0: no device, 1: keyboard, 2: mouse, 3: gamepad
    output reg report,              // pulse after report received from device. 
                                    // key_*, mouse_*, game_* valid depending on typ
    output conerr,                  // connection or protocol error

    // keyboard
    output reg [7:0] key_modifiers,
    output reg [7:0] key1, key2, key3, key4,

    // mouse
    output reg [7:0] mouse_btn,            // {5'bx, middle, right, left}
    output reg signed [7:0] mouse_dx,      // signed 8-bit, cleared after `report` pulse
    output reg signed [7:0] mouse_dy,      // signed 8-bit, cleared after `report` pulse

    // gamepad 
    output reg game_l, game_r, game_u, game_d,  // left right up down
    output reg game_a, game_b, game_x, game_y, game_sel, game_sta,  // buttons

    // debug
    output [63:0] dbg_hid_report	// last HID report
);

wire data_rdy;          // data ready
wire data_strobe;       // data strobe for each byte
wire [7:0] ukpdat;		// actual data
reg [7:0] regs [7];     // 0 (VID_L), 1 (VID_H), 2 (PID_L), 3 (PID_H), 4 (INTERFACE_CLASS), 5 (INTERFACE_SUBCLASS), 6 (INTERFACE_PROTOCOL)
wire save;			    // save dat[b] to output register r
wire [3:0] save_r;      // which register to save to
wire [3:0] save_b;      // dat[b]
wire connected;

ukp ukp(
    .usbrst_n(usbrst_n), .usbclk(usbclk),
    .usb_dp(usb_dp), .usb_dm(usb_dm), .usb_oe(),
    .ukprdy(data_rdy), .ukpstb(data_strobe), .ukpdat(ukpdat), .save(save), .save_r(save_r), .save_b(save_b),
    .connected(connected), .conerr(conerr));

reg  [3:0] rcvct;		// counter for recv data
reg  data_strobe_r, data_rdy_r;	// delayed data_strobe and data_rdy
reg  [7:0] dat[8];		// data in last response
assign dbg_hid_report = {dat[7], dat[6], dat[5], dat[4], dat[3], dat[2], dat[1], dat[0]};
// assign dbg_regs = regs;

// Gamepad types, see response_recognition below
// localparam D_GENERIC = 0;
// localparam D_GAMEPAD = 1;			
// localparam D_DS2_ADAPTER = 2;
// reg [3:0] dev = D_GENERIC;			// device type recognized through VID/PID
// assign dbg_dev = dev;

reg valid = 0;		    // whether current gamepad report is valid

always @(posedge usbclk) begin : process_in_data
    data_rdy_r <= data_rdy; data_strobe_r <= data_strobe;
    report <= 0;                    // ensure pulse
    if (report == 1) begin
        // clear mouse movement for later
        mouse_dx <= 0; mouse_dy <= 0;
    end
    if(~data_rdy) rcvct <= 0;
    else begin
        if(data_strobe && ~data_strobe_r) begin  // rising edge of ukp data strobe
            dat[rcvct] <= ukpdat;

            if (typ == 1) begin     // keyboard
                case (rcvct)
                0: key_modifiers <= ukpdat;
                2: key1 <= ukpdat;
                3: key2 <= ukpdat;
                4: key3 <= ukpdat;
                5: key4 <= ukpdat;
                endcase
            end else if (typ == 2) begin    // mouse
                case (rcvct)
                0: mouse_btn <= ukpdat;
                1: mouse_dx <= ukpdat;
                2: mouse_dy <= ukpdat;
                endcase
            end else if (typ == 3) begin    // gamepad
                // A typical report layout:
                // - d[3] is X axis (0: left, 255: right)
                // - d[4] is Y axis
                // - d[5][7:4] is buttons YBAX
                // - d[6][5:4] is buttons START,SELECT
                // Variations:
                // - Some gamepads uses d[0] and d[1] for X and Y axis.
                // - Some transmits a different set when d[0][1:0] is 2 (a dualshock adapater)
                case (rcvct)
                0: begin
                    if (ukpdat[1:0] != 2'b10) begin
                        // for DualShock2 adapter, 2'b10 marks an irrelevant record
                        valid <= 1;
                        game_l <= 0; game_r <= 0; game_u <= 0; game_d <= 0;
                    end else
                        valid <= 0;
                    if (ukpdat==8'h00) {game_l, game_r} <= 2'b10;
                    if (ukpdat==8'hff) {game_l, game_r} <= 2'b01;
                end
                1: begin
                    if (ukpdat==8'h00) {game_u, game_d} <= 2'b10;
                    if (ukpdat==8'hff) {game_u, game_d} <= 2'b01;
                end
                3: if (valid) begin 
                    if (ukpdat[7:6]==2'b00) {game_l, game_r} <= 2'b10;
                    if (ukpdat[7:6]==2'b11) {game_l, game_r} <= 2'b01;
                end
                4: if (valid) begin 
                    if (ukpdat[7:6]==2'b00) {game_u, game_d} <= 2'b10;
                    if (ukpdat[7:6]==2'b11) {game_u, game_d} <= 2'b01;
                end
                5: if (valid) begin
                    game_x <= ukpdat[4];
                    game_a <= ukpdat[5];
                    game_b <= ukpdat[6];
                    game_y <= ukpdat[7];
                end
                6: if (valid) begin
                    game_sel <= ukpdat[4];
                    game_sta <= ukpdat[5];
                end
                endcase
                // TODO: add any special handling if needed 
                // (using the detected controller type in 'dev')                
            end
            rcvct <= rcvct + 1;
        end
    end
    if(~data_rdy && data_rdy_r && typ != 0)    // falling edge of ukp data ready
        report <= 1;
end

reg save_delayed;
reg connected_r;
always @(posedge usbclk) begin : response_recognition
    save_delayed <= save;
    if (save) begin
        regs[save_r] <= dat[save_b];
    end else if (save_delayed && ~save && save_r == 6) begin     
        // falling edge of save for bInterfaceProtocol
        if (regs[4] == 3) begin  // bInterfaceClass. 3: HID, other: non-HID
            if (regs[5] == 1)    // bInterfaceSubClass. 1: Boot device
                typ <= regs[6] == 1 ? 1 : 2;     // bInterfaceProtocol. 1: keyboard, 2: mouse
            else
                typ <= 3;       // gamepad
        end else
            typ <= 0;                   
    end
    connected_r <= connected;
    if (~connected & connected_r) typ <= 0;   // clear device type on disconnect
end

endmodule

