# Mouse and keyboard event regression

Run from the repository root:

```sh
make -C bench/input test
make -C bench/input test BOARD=fleaohm
```

Requires Icarus Verilog. Products go to `/tmp/minimig-input-tests`.
IcePi Zero XL shares the IcePi Zero input RTL and board defines.

The bench instantiates the production `minimig_virtual_top` strobe generator,
`userio` (including its OSD dependencies), and `amiga_keyboard`. It models the
registered `cfide` MMIO event outputs and supplies the 28 MHz clock and 7 MHz
enable. Icarus `-i` deliberately omits unrelated virtual-top CPU, chipset,
memory, PLL and peripheral modules. This is an integrated input-path simulation,
not a full Amiga/firmware or FPGA timing simulation. Existing uninitialized
event-toggle/strobe registers are seeded once to model FPGA startup.

Coverage includes:

- Every 8-bit signed mouse delta, both ports, all four clock arrival phases,
  wrapping counters and explicit wheel events.
- All 256 raw keyboard bytes (including press/release), OSD-only events, and
  keyboard/mouse interleaving, checking exact event counts and encoded key data.
- Bursts with one event every five bus clocks, rotating through all phases.
- Disabled guest keyboard with continued OSD and mouse delivery.
- Reset with movement pending, followed by fresh movement.
- Complete serial keyboard press/release transmission at every arrival phase.

The existing shared event interface has no queue. Its data register must stay
valid until consumption; events closer together than the four-clock consumer
interval plus one bus clock are outside this bench's delivery guarantee. The
keyboard serial checks wait for each transmission to complete; the parallel
stress checks intentionally run faster to test event acceptance. The bench does
not execute firmware keyboard-busy polling or emulate CIA guest acknowledgements.

Before the mouse fix, the regression fails because a stretched X event is added
multiple times; repeated Y cycles are also misinterpreted as wheel movement.
