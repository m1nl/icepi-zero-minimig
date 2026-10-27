#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define HARDWARE_H
#define INTERRUPTS_H
#define KEYBOARD_BUSY (1U << 16)
#define KEYBOARD_TIMEOUT_MS 75
#define REG_KEYBOARD_OUT 2
/* Model the timer helper contract in milliseconds with target-width wrap. */
static uint32_t simulated_ms;
static unsigned int simulated_status, writes;
static unsigned long GetTimer(unsigned short offset_ms) {
    return (uint32_t)(simulated_ms + offset_ms);
}
static int CheckTimer(unsigned long deadline) {
    return (int32_t)(simulated_ms - (uint32_t)deadline) >= 0;
}
static unsigned short sent[1024];
static int interrupts_enabled;
static unsigned short *output(void) {
    assert(!interrupts_enabled);
    assert(writes < sizeof(sent) / sizeof(sent[0]));
    return &sent[writes++];
}
#define HW_KEYBOARD_STATUS simulated_status
#define HW_KEYBOARD(x) (*output())
#define DisableInterrupts() (interrupts_enabled = 0)
#define EnableInterrupts() (interrupts_enabled = 1)
#include "../keyboard.c"

static void reset_queue(void) {
    unsigned int i;
    for (i = 0; i < 4; ++i) keyboard_held[i] = 0;
    keyboard_head = keyboard_tail = keyboard_waiting = 0;
    keyboard_deadline = keyboard_queue_overflows = 0;
    simulated_ms = simulated_status = writes = 0;
    interrupts_enabled = 0;
}

int main(void) {
    unsigned int i, before;
    reset_queue();
    assert(KeyboardSend(0x8000));
    assert(writes == 1 && sent[0] == 0x8000);
    simulated_status = KEYBOARD_BUSY;
    for (i = 1; i < 127; ++i)
        assert(KeyboardSend(0x8000U | i));
    assert(writes == 1); /* No duplicate or separate OSD delivery. */
    for (i = 0; i < 1000; ++i)
        KeyboardService();
    assert(writes == 1);
    assert(!KeyboardSend(0x80ff));
    assert(keyboard_queue_overflows == 1 && writes == 1);
    assert(KeyboardSend(0x0007)); /* Mouse bypasses blocked keyboard keys. */
    assert(writes == 2 && sent[1] == 0x0007);
    for (i = 1; i < 127; ++i) {
        simulated_status = 0; /* ACK retires the previous head. */
        before = writes;
        KeyboardService();
        assert(writes == before + 1 && sent[writes - 1] == (0x8000U | i));
        simulated_status = KEYBOARD_BUSY;
        KeyboardService();
        assert(writes == before + 1);
    }
    simulated_status = 0;
    before = writes;
    KeyboardService();
    assert(writes == before && !keyboard_waiting && keyboard_head == keyboard_tail);
    for (i = 0; i < 512; ++i) {
        before = writes;
        assert(KeyboardSend(0x8000U | (i & 255)));
        assert(writes == before + 1 && sent[writes - 1] == (0x8000U | (i & 255)));
        KeyboardService(); /* ACK with no following entry cannot resend it. */
        assert(writes == before + 1 && !keyboard_waiting);
    }

    reset_queue();
    simulated_ms = 1024;
    assert(KeyboardSend(0x8042));
    simulated_status = KEYBOARD_BUSY;
    simulated_ms += 20;
    assert(KeyboardSend(0x8043)); /* Arrival cannot restart the first wait. */
    assert(writes == 1);
    simulated_ms += KEYBOARD_TIMEOUT_MS - 21;
    KeyboardService();
    assert(writes == 1); /* Still waiting one millisecond before expiry. */
    simulated_ms += 1;
    KeyboardService();
    assert(writes == 2 && sent[1] == 0x8043);
    assert(KeyboardSend(0x8044));
    simulated_ms += KEYBOARD_TIMEOUT_MS - 1;
    KeyboardService();
    assert(writes == 2); /* Each new transmission gets a fresh timeout. */
    simulated_ms += 1;
    KeyboardService();
    assert(writes == 3 && sent[2] == 0x8044);
    simulated_ms += KEYBOARD_TIMEOUT_MS;
    KeyboardService(); /* Expired head is discarded even with no next key. */
    assert(writes == 3 && !keyboard_waiting && keyboard_head == keyboard_tail);
    assert(KeyboardSend(0x8045));
    assert(writes == 4 && sent[3] == 0x8045);
    assert(KeyboardSend(0x8046));
    simulated_status = 0;
    KeyboardService(); /* Real ACK releases the following key early. */
    assert(writes == 5 && sent[4] == 0x8046);

    reset_queue();
    simulated_ms = 0xfffffff0U;
    assert(KeyboardSend(0x8047));
    simulated_status = KEYBOARD_BUSY;
    assert(KeyboardSend(0x8048));
    simulated_ms += KEYBOARD_TIMEOUT_MS - 1;
    KeyboardService();
    assert(writes == 1);
    simulated_ms += 1;
    KeyboardService();
    assert(writes == 2 && sent[1] == 0x8048);

    reset_queue();
    interrupts_enabled = 1;
    assert(KeyboardSendMain(0x8049));
    assert(interrupts_enabled && writes == 1 && sent[0] == 0x8049);
    KeyboardPoll();
    assert(interrupts_enabled && writes == 1 && !keyboard_waiting);

    /* A drained queue is insufficient while any raw key/modifier is held. */
    reset_queue();
    assert(KeyboardIdle());
    for (i = 0; i < 128; ++i) {
        assert(KeyboardSend(0x8000U | i));
        KeyboardService();
        assert(!KeyboardIdle());
    }
    for (i = 0; i < 128; ++i) {
        assert(KeyboardSend(0x8080U | i));
        KeyboardService();
        assert(KeyboardIdle() == (i == 127));
    }
    /* Mouse and OSD-only events cannot change the held-key bitmap. */
    assert(KeyboardSend(0xc020));
    assert(KeyboardSend(0x0020));
    assert(KeyboardIdle());

    reset_queue();
    assert(KeyboardSend(0x8020));
    simulated_status = KEYBOARD_BUSY;
    assert(KeyboardSend(0x80a0));
    assert(!(keyboard_held[0] | keyboard_held[1] | keyboard_held[2] | keyboard_held[3]));
    assert(!KeyboardIdle()); /* Clear bitmap, but release remains queued. */
    simulated_status = 0;
    assert(!KeyboardIdle()); /* Release is now in flight. */
    assert(writes == 2 && sent[1] == 0x80a0);
    simulated_status = KEYBOARD_BUSY;
    simulated_ms = KEYBOARD_TIMEOUT_MS - 1;
    assert(!KeyboardIdle());
    ++simulated_ms;
    assert(KeyboardIdle()); /* Timeout retires the final release as before. */
    puts("PASS: send-once keyboard FIFO, ACK/75 ms retirement, timer/queue wrap, overflow, mouse bypass and main-context locking");
    return 0;
}
