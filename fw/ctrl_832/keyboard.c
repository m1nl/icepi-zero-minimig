#include "hardware.h"
#include "interrupts.h"

/* Up to 127 keys, including the in-flight head entry. Static storage keeps the
 * controller's 4 KiB stack free. Mouse events bypass this keyboard queue.
 * All queue access runs with controller interrupts disabled.
 */
#define KEYBOARD_QUEUE_SIZE 128
#define KEYBOARD_QUEUE_MASK (KEYBOARD_QUEUE_SIZE - 1)

static unsigned short keyboard_queue[KEYBOARD_QUEUE_SIZE];
static unsigned int keyboard_head;
static unsigned int keyboard_tail;
static unsigned long keyboard_deadline;
static unsigned int keyboard_waiting;
/* Shared raw-key state for USB, AUX and other firmware input producers.
 * Track arrivals even on overflow so a held key still delays OSD capture.
 */
static unsigned int keyboard_held[4];

volatile unsigned int keyboard_queue_overflows;

/* ISR context, or main context with interrupts disabled. Never waits for the
 * guest. One MMIO write per call leaves time for the registered busy response.
 */
void KeyboardService(void) {
    unsigned int status = HW_KEYBOARD_STATUS;

    if (keyboard_waiting) {
        if ((status & KEYBOARD_BUSY) && !CheckTimer(keyboard_deadline))
            return;
        /* ACK or timeout retires the head. It is never retransmitted. */
        keyboard_tail = (keyboard_tail + 1) & KEYBOARD_QUEUE_MASK;
        keyboard_waiting = 0;
    }

    if (keyboard_tail != keyboard_head) {
        HW_KEYBOARD(REG_KEYBOARD_OUT) = keyboard_queue[keyboard_tail];
        keyboard_deadline = GetTimer(KEYBOARD_TIMEOUT_MS);
        keyboard_waiting = 1;
    }
}

/* Called by the HID interrupt handlers. Return zero only on queue overflow;
 * preserve older events and count the rejected event for diagnosis.
 */
int KeyboardSend(unsigned short event) {
    unsigned int next;
    unsigned int key, mask;

    if ((event & 0xc000U) != 0x8000U) {
        HW_KEYBOARD(REG_KEYBOARD_OUT) = event;
        return 1;
    }

    key = event & 0x7fU;
    mask = 1U << (key & 31);
    if (event & 0x80U)
        keyboard_held[key >> 5] &= ~mask;
    else
        keyboard_held[key >> 5] |= mask;

    /* Retire an acknowledged/expired head before checking available space. */
    KeyboardService();
    next = (keyboard_head + 1) & KEYBOARD_QUEUE_MASK;
    if (next == keyboard_tail) {
        ++keyboard_queue_overflows;
        return 0;
    }

    keyboard_queue[keyboard_head] = event;
    keyboard_head = next;
    if (!keyboard_waiting)
        KeyboardService();
    return 1;
}

/* Caller must keep interrupts disabled through the OSD capture SPI write.
 * Service the final ACK/timeout before checking the queue and held keys.
 */
int KeyboardIdle(void) {
    KeyboardService();
    return keyboard_head == keyboard_tail && !keyboard_waiting &&
        !(keyboard_held[0] | keyboard_held[1] | keyboard_held[2] | keyboard_held[3]);
}

/* Main-context entry points. The callers here run with interrupts enabled;
 * do not call these from an ISR or an existing interrupt-disabled section.
 */
void KeyboardPoll(void) {
    DisableInterrupts();
    KeyboardService();
    EnableInterrupts();
}

int KeyboardSendMain(unsigned short event) {
    int accepted;
    DisableInterrupts();
    accepted = KeyboardSend(event);
    EnableInterrupts();
    return accepted;
}
