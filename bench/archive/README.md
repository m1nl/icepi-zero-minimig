# Historical temporary tests

Source files recovered from `/tmp` during RTG/HDMI and cache development.
`sources.json` records each original path, its saved path and SHA-256 digest.
Files are copied unchanged so earlier comparisons remain inspectable.

- `rtg-cdc-review/`: toggle/reset, register, vblank and pixel-stream tests.
- `rtg-countdown-assessment/`, `rtg-countdown-final/`: counter optimization and
  boundary/equivalence tests, with the RTL snapshots they compared.
- `rtg-area-assessment/`: resource comparison variants and pixel testbenches.
  The separate bursts reproduction used identical sources; its paths are aliases
  in the manifest. Current assessment scripts remain in `../rtg_area/`.
- `rtg-optimization-assessment/`: later cleanup/repetition experiments.
- `serializer-analysis/`: phase, dynamic-clock and serialization experiments,
  including the proposed serializer variants.
- `hdmi-reset-synthesis/`: HDL snapshots used for reset resource assessment.
- `cpu-cache-review/`: scoreboard, reset, boundary, inhibit and tag tests, with
  reference/candidate cache snapshots.
- `early-reproductions/`: earlier HDMI, RTG priority/contention and
  TMDS timing sources. Current priority stress test is also in `../rtg_hdmi/`.

These are historical sources, not a passing test suite for today's RTL. Some
expect old port/register layouts or deliberately reproduce bugs. The early
`test_driver_repeat.py` and `test_driver_clocks.py` generate ROMs with obsolete
mode expectations. These and their generated driver ROM sources now live in
`../../amiga_sw/rtg/tests/archive/`; the manifest records their new paths.
Use `make -C amiga_sw/rtg test` for today's driver.
Some original scripts refer to `/tmp` or the original workspace; inspect them
before running. They are preserved for reference rather than made portable.

Generated simulations, translated CPU netlists, object files, logs and mapped
netlists are excluded. The CPU netlist is reproducible with
`../rtg_hdmi/run_cpu_mmio.sh`. No production HDL is changed by this collection.
