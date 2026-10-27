/* Reuse the queue/MMIO harness, then exercise the production OSD handoff. */
#define main keyboard_queue_regression_main
#include "keyboard_queue_test.c"
#undef main

#include "../osd.h"
#define RAMFUNC
static unsigned int spi_position, captures, osd_mode;
static unsigned int video_writes, reset_writes;
static unsigned char video_byte, video_x, video_y, reset_value;
static unsigned char spi_command;
static unsigned char capture_spi(unsigned char value) {
    if (!spi_position++) spi_command = value;
    else if (spi_command == OSD_CMD_OSD) {
        if ((value & DISABLE_KEYBOARD) && !(osd_mode & DISABLE_KEYBOARD)) {
            assert(!interrupts_enabled);
            assert(keyboard_head == keyboard_tail && !keyboard_waiting);
            assert(!(keyboard_held[0] | keyboard_held[1] | keyboard_held[2] | keyboard_held[3]));
            ++captures;
        }
        osd_mode = value;
    } else if (spi_command == OSD_CMD_VID) {
        video_byte = value;
        ++video_writes;
    } else if (spi_command == OSD_CMD_VID_XOFF) {
        video_x = value;
    } else if (spi_command == OSD_CMD_VID_YOFF) {
        video_y = value;
    } else if (spi_command == OSD_CMD_RST) {
        reset_value = value;
        ++reset_writes;
    }
    return 0;
}
#define EnableOsd() (spi_position = 0)
#define DisableOsd() ((void)0)
#define SPI(x) capture_spi(x)
static unsigned long CheckButton(void) { return 0; }
static void SendKeypress(unsigned char key, unsigned short delay) { (void)key; (void)delay; }
#include "../osd.c"
configTYPE config;

int main(void) {
    unsigned int before;
    reset_queue();
    interrupts_enabled = 1;
    assert(KeyboardSendMain(0x8020)); /* Held guest key. */
    simulated_status = KEYBOARD_BUSY;
    assert(KeyboardSendMain(0x8069)); /* OSD trigger must also be released. */
    OsdShow(DISABLE_KEYBOARD);
    assert(!osd_visible && !OsdPoll() && !captures && interrupts_enabled);
    /* New presses are still forwarded normally while opening is pending. */
    assert(KeyboardSendMain(0x8060)); /* Left shift, from any firmware producer. */
    simulated_status = 0;
    KeyboardPoll();
    assert(writes == 2 && sent[1] == 0x8069);
    KeyboardPoll();
    assert(writes == 3 && sent[2] == 0x8060);
    KeyboardPoll();
    assert(!OsdPoll()); /* Queue drained, but held bitmap is not empty. */
    assert(KeyboardSendMain(0x80a0));
    simulated_status = KEYBOARD_BUSY;
    assert(KeyboardSendMain(0x80e9));
    assert(KeyboardSendMain(0x80e0));
    assert(!OsdPoll()); /* Bitmap clear, but releases are still queued. */
    simulated_status = 0;
    assert(!OsdPoll());
    assert(sent[writes - 1] == 0x80e9);
    assert(!OsdPoll());
    assert(sent[writes - 1] == 0x80e0);
    simulated_status = KEYBOARD_BUSY;
    assert(!OsdPoll()); /* Final release still awaits ACK. */
    simulated_status = 0;
    assert(OsdPoll() && captures == 1 && osd_visible && osd_mode == 3);
    assert(interrupts_enabled && OsdPoll() && captures == 1);

    /* Replacing an already captured menu with an error must not wait on
     * keys being used inside OSD; the guest is already protected. */
    assert(KeyboardSendMain(0x8024));
    OsdShow(DISABLE_KEYBOARD);
    assert(OsdPoll() && captures == 1 && osd_mode == 3);
    assert(KeyboardSendMain(0x80a4));
    KeyboardPoll(); KeyboardPoll();

    OsdHide();
    assert(!osd_visible && !osd_mode);
    assert(KeyboardSendMain(0x8021));
    OsdShow(DISABLE_KEYBOARD);
    assert(!OsdPoll());
    OsdHide(); /* Cancels pending capture. */
    assert(KeyboardSendMain(0x80a1));
    KeyboardPoll(); KeyboardPoll();
    assert(OsdPoll() && !osd_visible && captures == 1);

    /* Noncapturing overlays remain immediate and cancel a pending request. */
    assert(KeyboardSendMain(0x8022));
    OsdShow(DISABLE_KEYBOARD);
    assert(!OsdPoll());
    OsdShow(0);
    assert(OsdPoll() && osd_visible && osd_mode == 1 && captures == 1);
    assert(KeyboardSendMain(0x80a2));
    KeyboardPoll(); KeyboardPoll();
    OsdHide();

    /* An unresponsive guest still uses the existing 75 ms retirement policy. */
    assert(KeyboardSendMain(0x8023));
    simulated_status = KEYBOARD_BUSY;
    assert(KeyboardSendMain(0x80a3));
    OsdShow(DISABLE_KEYBOARD);
    before = writes;
    simulated_ms += KEYBOARD_TIMEOUT_MS;
    assert(!OsdPoll() && writes == before + 1 && sent[writes - 1] == 0x80a3);
    simulated_ms += KEYBOARD_TIMEOUT_MS - 1;
    assert(!OsdPoll());
    ++simulated_ms;
    assert(OsdPoll() && captures == 2 && interrupts_enabled);

    /* Reset with Space restores mode 0 and reapplies its unadjusted offsets,
     * preserving filters, scanlines and the configured offset values.
     */
    config.video_mode = 2;
    config.x_offset = 166; config.y_offset = 47;
    config.filter.hires = 2; config.filter.lores = 1; config.scanlines = 3;
    assert(KeyboardSendMain(0x8040));
    OsdReset();
    assert(!config.video_mode && video_writes == 1 && video_byte == 0x27);
    assert(video_x == 166 && video_y == 47 && reset_writes == 2 && !reset_value);
    assert(config.x_offset == 166 && config.y_offset == 47);
    assert(KeyboardKeyDown(KEY_SPACE));
    assert(KeyboardSendMain(0x80c0));
    config.video_mode = 1;
    OsdReset();
    assert(config.video_mode == 1 && video_writes == 1 && reset_writes == 4);
    /* Key-state snapshots are also safe inside a HID interrupt handler. */
    interrupts_enabled = 0;
    assert(KeyboardSend(0x8040));
    OsdReset();
    assert(!interrupts_enabled && !config.video_mode && video_writes == 2);
    assert(KeyboardSend(0x80c0));
    assert(!KeyboardKeyDown(KEY_SPACE));
    puts("PASS: deferred OSD capture, held keys/modifiers, continued input, final ACK/timeout, cancellation and atomic capture");
    puts("PASS: Space-reset restores mode 0 and offsets, preserves filters and ISR interrupt state; ordinary reset preserves mode");
    return 0;
}
