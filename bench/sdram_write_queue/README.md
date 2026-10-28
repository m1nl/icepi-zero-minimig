# Posted CPU writes

Run from the repository root:

```sh
python3 bench/sdram_write_queue/run.py
python3 bench/rtg_hdmi/run.py contention_queue
```

The first runner requires Python 3 and Icarus Verilog. Products use a temporary
directory. It covers the four-entry queue, tail-only same-address byte merging,
full-queue backpressure, simultaneous pop/push, pointer wrap, and reset. `A,B,A`
stays in order; only consecutive entries with identical starting halfword
addresses merge. Incoming selected bytes win; unselected bytes retain their
old data and active-low masks.

Controller tests run the production controller and queue with a synthetic cache
request source. They check both four-halfword drains, normal fallback, masks
merged during allocation, late FIFO heads versus registered bank eligibility,
row/bank boundaries, competing reads, refresh, reset/reinitialization, and
CPU read exclusion while queued or in-flight writes remain. The command checker
uses W9825G6KH-6I limits at 114 MHz: tRCD/tRP=18 ns, tRAS=42 ns, tRC=60 ns,
tRRD=2 clocks, and write recovery=2 clocks. Tests also cover disabled operation,
shortcut operation, and the queue overriding legacy `fast_write` scheduling.
The readback test uses the real small CPU cache and behavioral memory to check
paired and narrow inhibited CPU reads after full and byte writes. The separate
RTG contention case uses the real cache, controller and RTG producer.

These are functional and command-spacing simulations, not a Winbond electrical
model or proof of FPGA timing closure. Inspect board timing reports and test on
hardware before claiming either.

## Enabling the feature

`sdram_ctrl #(.cpu_write_queue(1))` enables both the queue and opportunistic
four-halfword writes. Its default is zero. The IcePi Zero XL board header alone
defines `MINIMIG_SDRAM_WRITE_QUEUE`; the shared top passes that choice to the
controller. Standard IcePi Zero and FleaOhm retain the disabled path.

The cache's existing request/acknowledge toggles feed a four-entry queue. A write
is acknowledged after copying or merging its bytes. The controller captures a
complete payload and masks into per-slot registers before popping an entry.
Cache-only clear preserves its request toggle and does not reset the queue, so
accepted writes remain posted. The queue now uses active-low asynchronous
`rstn`, driven by SDRAM initialization readiness. SDRAM reset clears the queue
along with controller initialization. Reset checks reject stale WRITE commands;
the current phase sequencer is not required to stay in ph0 during reset.

If the next entry shares the active bank and row and the opposite slot has no
read, slot 1 issues WRITEs at ph8/ph10/ph11/ph12, or slot 2 at ph0/ph2/ph3/ph4.
Only the final WRITE auto-precharges. Otherwise the original two-WRITE pattern
is used. Slot 2 also falls back during chipset override cycles. ACTIVATE and
read-burst phases remain unchanged. Queue mode suppresses
legacy `fast_write`, including for chipset/host writes, to retain recovery and
avoid competing WRITE commands. Slot ownership lasts through recovery; the
final extended WRITE leaves at least five clocks before same-bank activation.

CPU SDRAM reads wait for source requests, queued entries and in-flight CPU write
slots to drain. There is no queue forwarding to CPU reads. Cache hits may still
complete normally. Chipset, RTG and host retain their existing arbitration;
the barrier orders CPU memory requests, not independent bus masters.
