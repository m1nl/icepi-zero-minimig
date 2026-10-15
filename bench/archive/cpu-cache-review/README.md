# CPU cache refactor review

Source: /home/mnalewajski/dev/icepi-zero-minimig/cpu_cache_new.v
Reference: rtl/sdram/cpu_cache_new.v
Production sources were not changed. Run `python3 /tmp/cpu-cache-review/validate.py` to reproduce.

## Results

- Differential simulation: 1,276 transactions, no normal-operation differences.
- Independent read scoreboard: 1,036 reads in 1,273 transactions, including 227 line-buffer hits. Both I/D ways, eight burst starting offsets, byte masks 0/1/2/3, aligned and unaligned long writes within a line, inhibit, enable/freeze controls, line invalidation and snoop with explicit line invalidation exercised.
- Tests use an abstract SDRAM burst responder and the existing SOC_SIM cache-memory models. They do not validate SDRAM electrical timing or vendor memory models. Traffic provides address setup before CS and ample idle time between transactions; maximum-throughput CPU traffic and exhaustive concurrent snoop interactions were not tested.
- Reset-gating regression: an active matching CPU write changes a line word while rst=1. Original holds it. Reset invalidates the line, so this is an equivalence discrepancy with limited practical impact. A temporary reset-gated candidate passes normal scoreboard and holds its RAM during reset. See reset-gating.patch; it has NOT been applied.
- Full-module Yosys ECP5 synthesis (main RAM instances black-boxed): original 600 FFs, 0 LUTRAM cells; candidate 344 FFs, 16 TRELLIS_DPR16X4 cells (eight per line buffer). This removes exactly 256 FFs, matching the two 128-bit line buffers. This is not a Diamond/Synplify or placed-and-routed result.
- Current IcePi project includes cpu_cache_small.v and excludes rtl/sdram/cpu_cache_new.v; the root candidate is absent from its source list. All three use module name cpu_cache_new, so select only one implementation.
- Current sdram_ctrl.v connects sdr_read_pre; the root candidate has no such port. Controller elaboration with the candidate fails. Reconcile that interface when integrating.
- Inherited combined long-write boundary defect: cache 0x200..0x20f, leave 0x210..0x21f uncached, write two halfwords starting at 0x20e, replace the small data line buffer with a read at 0x300, reread 0x20e. Backing memory and the small line buffer initially have 0x1234, but main-cache reload returns the stale 0xefc3 in BOTH implementations. First-half main-RAM write enables see tags selected by the live second-half index. sdram_ctrl.v already disables longword_en at word offset 7, so this case is avoided by current integration. If removing that guard, use independent halfword writes or retain the first-half hit/way information for its delayed commit, then resolve the second-half line separately.

## Files

validate.py orchestrates tests and saves logs. tb.v checks differential equivalence. tb_scoreboard.v adds independent expected-data checking under the controller longword restriction. tb_boundary.v is an intentionally failing inherited-defect reproducer. run.py creates reference/candidate copies and synthesizes isolated line memories. full.json and original_full.json show actual mapped cells. integration.log records the missing-port elaboration failure. reset-gating.patch is a tested suggested change.
