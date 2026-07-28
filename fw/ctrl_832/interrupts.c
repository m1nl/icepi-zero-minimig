#include "interrupts.h"

static void dummy_handler()
{
    AckInterrupt();
}

__constructor(100.interrupts) void intconstructor()
{
    SetIntHandler(dummy_handler);
}
