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

The small variant mixes `#1` and undelayed ACK assignments on writes, producing a short write-ACK pulse in behavioral simulation. The test observes that ACK asynchronously. These delays are ignored by synthesis, so this observation alone does not establish a hardware fault.

Combined long writes across a 16-byte line boundary have an inherited cache-update problem in the root. `sdram_ctrl.v` already disables combined long writes at the last word of a line.

Controller elaboration and lint pass with the root cache at the default address width. This test uses inferred simulation memories and an abstract responder; it does not validate SDRAM hardware timing or Diamond memory mapping.
