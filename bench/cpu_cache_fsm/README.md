# Cache FSM regressions

Run from the repository root:

```sh
python3 bench/cpu_cache_fsm/run.py
bash bench/rtg_hdmi/run_cpu_mmio.sh
python3 bench/sdram_write_queue/run.py
```

The FSM runner uses the production `rtl/sdram/cpu_cache_small.v`, Icarus
Verilog, and the inferred simulation RAMs. It runs all combinations of
`data_cache=0/1` and `unaligned_write_combine=0/1`. Products go to temporary
directories. Historical `--variant root` / `--variant all` runs target an
obsolete interface and are not current regressions.

## Timing and coverage

Predicted reads must ACK on the first eligible IDLE edge after address/type
setup, and return the correct narrow word or aligned pair. Ordinary resident
hits must ACK one cache clock later, through READ. These are cache-controller
latencies, not complete TG68K bus-cycle lengths. The access-type decode is
registered as in `sdram_ctrl.v`; `cpu_restore` is combinational.

The five-bit CPU state is `{longword, req_enable, ramcs_n, access_type[1:0]}`.
Bit 3 is `req_enable`, which remains high during peripheral service. Restoration
uses `req_enable && ramcs_n`. The CPU consumes ACK on a rising edge, then can
present the following address immediately; completed requests are not held in
WAIT for extra cycles. Both BRAM ports are always enabled.

With D-cache enabled, checks cover narrow and paired I/D reads, same-pair and
next-pair predictions, wrap inside a 16-byte line, wrong predictions, alternating
I/D accesses, both ways, peripheral restoration, prediction clear/reset, fill
handshakes, inhibited misses, write-through, byte masks and legacy combining.
`valid` records the saved line/way; `ready` qualifies the fast BRAM read.

The production interface has active-low asynchronous `rstn` and a separate
active-high `clr`. The bench drives `rstn` from its reset stimulus and tests
external clear plus CACR software clear on warm instruction lines. Backing RAM
is changed before each clear to verify that resident tags and predictions are
discarded. Reset during an incomplete paired read checks ACK/write suppression;
a subsequent narrow read checks that stale paired-read state cannot leak out.

With D-cache disabled, the bench requires every repeated narrow/paired data
read to fetch SDRAM, while instruction reads remain cached and their saved
prediction survives data accesses. It also checks direct return to an instruction
prediction, instruction fast reads and write-through with combining on/off.

## ACK handoff

The disabled-D-cache case returns from an uncached data read at `0xC08` directly
to saved instruction prediction `0xE04`. The next address is presented before
FILLW observes low CS, as TG68K advances on ACK. The I pointer remains parked
at the prediction throughout FILLW, and the first-cycle instruction read must
return the correct pair without fetching SDRAM. Both narrow and paired uncached
data handoffs are checked, with both combining settings.

An earlier bench held the old data address for 20 idle clocks after releasing
CS, then demanded a fast instruction return. That synthetic idle gap overwrote
the parked I pointer and did not model the immediate TG68K handoff. It has been
removed from this check. Real-TG68K traces show one address setup edge before
request sampling in overclock mode and two in normal mode.

The inherited ordinary READ-hit conditions still do not exclude `cache_inhibit`;
inhibited tests cover misses,
not bypass of already resident addresses.

## Real CPU and controller integration

The real-TG68K runner builds the IcePi Zero CPU configuration once and runs nine
ROM cases: one behavioral uncached responder plus cached normal/overclock runs
with D-cache and legacy combining independently enabled/disabled. The ROM checks
aligned paired reads/writes, byte writes, unaligned longwords, cache-line
boundaries, narrow RTG MMIO ordering and accepted-read data against memory.

It also runs the permanent Doom-style Akiko/cache ROM in
`bench/rtg_hdmi/rtg_cpu_akiko.asm`: sixteen overclock cases span eight instruction
layouts and D-cache off/on. The bench checks accepted instruction/data reads
against RAM, all 128 Akiko word reads and writes, and an Akiko ACK coinciding
with a FILL2 exit when D-cache is enabled. The fill-exit pointer selection must
honor `cpu_restore` without redirecting an active fill's pointer.

The controller regression checks write-queue merging/backpressure, arbitration,
command spacing and production-cache read-after-write with the queue off/on.
Its cache source stub accepts the production `data_cache` parameter.

These simulations do not establish FPGA timing closure, physical RAM removal,
or general workload throughput. Those require the selected board build/reports.
