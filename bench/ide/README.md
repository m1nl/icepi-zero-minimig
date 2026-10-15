# IDE transport regression

Run from the repository root:

```sh
make -C bench/ide test
```

Requires Icarus Verilog (`iverilog` and `vvp`). Build products go to
`/tmp/minimig-ide-tests`.

`ide_packet_tb.v` exercises the production `ide.v` and `ide_fifo.v`: packet
phases, odd byte counts, intermediate/final interrupts, abort/reset recovery,
command-generation metadata, and ATA sector reads/writes. It simulates the IDE
hardware interface without running firmware.

Firmware tests run separately with `make -C fw/ctrl_832/tests test`; see
[the firmware test README](../../fw/ctrl_832/tests/README.md).
