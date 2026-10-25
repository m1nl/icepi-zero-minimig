# Cache FSM migration checks

Run `python3 bench/cpu_cache_fsm/run.py` with Icarus Verilog installed. The default runs `rtl/sdram/cpu_cache_small.v`, which passes with the current source. `--variant root` or `--variant all` selects the historical root-cache checks; these currently fail elaboration because the root cache interface/layout has changed. The same abstract SDRAM responder was originally used for both variants.

The test covers a miss held while `sdr_read_pre` is low, a previous burst still active, request retention after the launch pulse until data arrives, instruction/data cache hits without a launch pulse, writes with `sdr_read_pre` low, consecutive inhibited misses while the previous burst drains, unexpected FSM states, and reset during a matching write.

The inferred data RAM models the always-enabled CPU and snoop ports. The
small-cache checks exercise restoration of both predicted pairs during
peripheral accesses: `cpu_req` represents TG68K's `req_enable`, which stays high
while the peripheral completes even though RAM `cpu_cs` remains low. The bench
checks restored data and the first RAM reads after returning from the peripheral,
rather than requiring every BRAM output to stay unchanged throughout the cycle.
Both BRAM fast-hit entries must be invalid after reset. Fill reads still use the
ordinary cache lookup before a BRAM fast-hit entry becomes valid.

Read hits prepare independent speculative pairs for I and D during WAIT. Even
narrow reads retain the pair; odd narrow reads and paired reads advance to the
next pair, wrapping inside the same 16-byte line. The latency checks require
first-cycle ACKs after TG68K-style address/type setup and the controller's
registered access-type decode. A request consumes ACK on a rising edge and
releases CS immediately afterward; the next request can present its address on
that same CPU advance edge, before the low-CS clock. Completed requests are not
held in WAIT for extra cycles. Checks cover wrong predictions, crossing into
another line, alternating I/D accesses, both ways, and clearing predictions.

The real-CPU MMIO runner also checks cached normal and overclock operation with
legacy write combining disabled and enabled. Its five-bit `cpustate` layout is
`{longword, req_enable, ramcs_n, access_type[1:0]}`; bit 3 is not `ram_req`.

## Migration decisions

- The root cache launches from `CPU_SM_READ` or `CPU_SM_SDWAI` only when `!sdr_read_ack && sdr_read_pre`, matching the small cache's read-launch qualification.
- The small cache retries in `CPU_SM_READ`. The root uses `CPU_SM_SDWAI` because its READ state advances a four-word line copy and returns after four cycles; looping there would advance that machinery while waiting.
- After launch, both variants hold the request in FILL1 until the first SDRAM word arrives. `sdr_read_pre` describes a launch opportunity, not guaranteed arbitration acceptance.
- Unexpected CPU states fall back to INIT, and unexpected SDRAM states fall back to INIT0, following the small variant. All four two-bit SDRAM encodings are legal, so the directed SDRAM fallback check injects an unknown simulation value.
- Root line-buffer write enables are suppressed during reset, restoring the original cache's hold behavior without adding a reset to LUTRAM contents.
- The root retains its four-word line-copy schedule, full-line hits, and write-through machinery. The small variant's two-word last-pair buffering and different ACK scheduling are not appropriate replacements for those paths.

## Review findings

Both variants qualify main-cache READ hits with `cc_en` but do not exclude `cache_inhibit`. An inhibited read of an already cached address can still acknowledge from a main cache way. The test above exercises inhibited misses; it does not claim inhibited cached reads bypass the main cache. This inherited behavior remains outside the migration.

The small cache now uses the same registered ACK timing for writes and reads. Paired writes supply both words in one request; WAIT_LOWORD and WRITE_32BIT are only reachable when optional legacy combining is enabled. The root-cache observations below describe its historical protocol.

Combined long writes across a 16-byte line boundary have an inherited cache-update problem in the root. `sdram_ctrl.v` already disables combined long writes at the last word of a line.

Controller elaboration and lint now use the production small cache at the default address width. The historical root cache retains its old interface and cannot be substituted into the updated controller. These tests use inferred simulation memories and an abstract responder; they do not validate SDRAM hardware timing or Diamond memory mapping.

## TG68K paired SDRAM transfers

The supported board projects use `cpu_cache_small.v`. Its `cpu_long_cand`
input replaces the old `cpu_32bit` write-combining hint. Aligned, full-word read/write candidates are always accepted, including
instruction extensions. `cpu_ack` alone indicates completion; paired reads wait
for both words. No pair-acceptance feedback port is required. The first word is `cpu_dat_w` / `cpu_dat_r_hi`;
the second is `cpu_dat_w_lo` / `cpu_dat_r`. Narrow reads still use
`cpu_dat_r`. SDRAM/cache entries retain their existing first-word-in-low-half
layout; the cache translates the CPU's big-endian pair ordering.

The test covers paired I/D misses, BRAM and last-pair hits, paired
write-through hits/misses, line-end aligned pairs, inhibited pair reads and
unaligned-candidate rejection and reset between paired read beats. A paired miss waits for the second SDRAM
beat before acknowledging; the SDRAM burst protocol is unchanged.

`rtl/soc/TG68K.vhd` exposes `ram_long_cand`, `fromram_hi`
and `toram_lo`; `minimig_virtual_top.v` connects them through `sdram_ctrl.v`.
Only directly selected SDRAM memory can offer/accept pairs. Chipset bus
transactions, NMI interception, RTG/Akiko/host registers, undecoded space
retain their existing narrow protocol.
Turbo chip/slow/Kickstart memory served directly by SDRAM can pair.
The legacy `cpustate[3]`/`longword` remains available for chipset bus timing;
the SDRAM controller only uses it for the optional legacy combining path.

Run `bash bench/rtg_hdmi/run_cpu_mmio.sh` to test the real synthesized
TG68K wrapper/kernel with both an uncached pair-capable memory responder and the production
small cache. The ROM checks aligned paired reads/writes, byte writes,
unaligned longwords (including odd addresses) across cache-line boundaries,
byte guards and RTG MMIO word ordering.
The runner compiles `fpga/icepi-zero/board_config.vhd` with the CPU. The cached
run requires accepted data read/write pairs; instruction-extension pairs depend
on that board's `tg68k_datapath32` setting.
These tests do not establish board timing closure.

### Combined writes

`unaligned_write_combine=1` remains the cache default. It collects two narrow
writes using the `cpu_longword` hint from `cpustate[3]`. A new-interface aligned
pair always takes precedence. Reads never use the legacy hint. Combining remains
disabled at the final halfword of a 16-byte line so SDRAM burst addressing cannot
wrap to the wrong word.

Both paths fill the existing `sdr_adr` / `sdr_dat_w` / `sdr_dqm_w` buffer and use
`CPU_SM_WRITE` to submit one SDRAM transaction and update resident I/D cache
ways. A combined pair starting at +2 uses `CPU_SM_WB` to update the next cache
entry. Its data and hit ways are retained from the first cache update. The
collection states fill the buffer. Cache updates use `cpu_dat_l` / `cpu_bs_l`
for the most recently accepted narrow word, while the first collected word stays
in the buffer. Direct aligned pairs use the complete buffer. WRITE registers
cache data and hit ways before the optional WB cycle, so later CPU input changes
cannot alter the second cache update. Both touched last-pair buffers are invalidated.

Collected writes take one extra cache-controller cycle to finish cache updates;
CPU ACK timing and the direct aligned-pair path are preserved. A held CPU request
must drop before another request is accepted. Last-pair read buffers remain
unchanged otherwise.

The FSM runner tests combining off and on, checking write counts, aligned and
unaligned pairs, partial byte masks, line-boundary fallback and I/D cache updates.
The real-CPU MMIO runner also checks both settings. The SDRAM controller uses the
cache's default (combining enabled). These simulations do not establish FPGA
resource counts or timing closure.
