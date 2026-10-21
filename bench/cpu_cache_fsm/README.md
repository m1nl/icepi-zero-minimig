# Cache FSM migration checks

Run `python3 bench/cpu_cache_fsm/run.py` with Icarus Verilog installed. The default runs `rtl/sdram/cpu_cache_small.v`, which passes with the current source. `--variant root` or `--variant all` selects the historical root-cache checks; these currently fail elaboration because the root cache interface/layout has changed. The same abstract SDRAM responder was originally used for both variants.

The test covers a miss held while `sdr_read_pre` is low, a previous burst still active, request retention after the launch pulse until data arrives, instruction/data cache hits without a launch pulse, writes with `sdr_read_pre` low, consecutive inhibited misses while the previous burst drains, unexpected FSM states, and reset during a matching write.

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
input replaces the old `cpu_32bit` write-combining hint. `cpu_long_ack`
qualifies `cpu_ack` for aligned, full-word read/write pairs, including
instruction extensions. The first word is `cpu_dat_w` / `cpu_dat_r_hi`;
the second is `cpu_dat_w_lo` / `cpu_dat_r`. Narrow reads still use
`cpu_dat_r`. SDRAM/cache entries retain their existing first-word-in-low-half
layout; the cache translates the CPU's big-endian pair ordering.

The test covers paired I/D misses, BRAM and last-pair hits, paired
write-through hits/misses, line-end aligned pairs, inhibited pair reads and
unaligned-candidate rejection and reset between paired read beats. A paired miss waits for the second SDRAM
beat before acknowledging; the SDRAM burst protocol is unchanged.

`rtl/soc/TG68K.vhd` exposes `ram_long_cand`, `ram_long_ack`, `fromram_hi`
and `toram_lo`; `minimig_virtual_top.v` connects them through `sdram_ctrl.v`.
Only directly selected SDRAM memory can offer/accept pairs. Chipset bus
transactions, NMI interception, RTG/Akiko/host registers, undecoded space
and the SDRAM-backed audio peripheral retain their existing narrow protocol.
Turbo chip/slow/Kickstart memory served directly by SDRAM can pair.
The legacy `cpustate[3]`/`longword` remains available for chipset bus timing;
the SDRAM controller only uses it for the optional legacy combining path.

Run `bash bench/rtg_hdmi/run_cpu_mmio.sh` to test the real synthesized
TG68K wrapper/kernel with both a narrow memory responder and the production
small cache. The ROM checks aligned paired reads/writes, byte writes,
unaligned longwords across a cache-line boundary and RTG MMIO word ordering.
The cached run requires accepted instruction-extension and data pairs.
These tests do not establish board timing closure.

### Optional legacy write combining

`legacy_write_combine=0` is the default in both the cache and SDRAM controller.
Setting the controller parameter to 1 forwards it to the cache and restores
collection of two narrow writes using the `cpu_longword` hint from
`cpustate[3]`. This can combine a pair starting two bytes into a 32-bit cache
entry, updating both touched entries. Byte masks are preserved; combining
remains disabled at the final word of a 16-byte line. Reads never use this
legacy hint. A new-interface complete pair always takes precedence.

The FSM runner tests parameter values 0 and 1, checking write counts,
aligned/unaligned pairs, partial byte masks, line-boundary fallback and I/D
cache updates. The real-CPU MMIO runner also checks both parameter settings.
No production instantiation enables legacy combining.
