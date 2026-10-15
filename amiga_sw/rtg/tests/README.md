# Driver regressions on the simulated TG68K/RTG core

From the repository root:

```sh
make -C amiga_sw/rtg test
make -C amiga_sw/rtg test TEST_PROFILE=1280x720
```

The default tests both profiles, independent of the RTG_720P build option.
It leaves the installed/generated driver and ADF untouched. See the parent
[driver README](../README) for dependencies, detailed coverage and limitations.

- `run.py`: translates the current TG68K wrapper/kernel once, runs the MMIO ROM,
  then runs driver callbacks for the requested profile(s).
- `test_driver_fallback.py`: generates a 68020 ROM from real driver callbacks
  and independent expected results for 26 cases in three formats. Also checks
  sync widths and vertical split limits. Run standalone with `--rtg-720p` to
  select that profile; default is 1024x768.
- `sim_core.py`: assembles ROMs, generates the CPU model, and runs the shared
  real-RTL MMIO harness in `../../../bench/rtg_hdmi/`.
- `archive/`: historical driver tests and ROM sources, preserved unchanged.

Tools: vasm, GHDL, Icarus Verilog and Python 3. The Make target obtains the
NDK/P96 headers using the existing dependency rules. Standalone entry points
expect those headers to be present. Source and include path overrides from
the driver Makefile are forwarded to the tests.

This simulates actual CPU instructions and the TG68K RTG bus decode/ACK path
with the current RTG/Akiko RTL. RAM/ROM are behavioral and RTG scanout is held
inactive. It does not load the complete .card hunk into AmigaOS, emulate P96,
boot Workbench or validate HDMI/SDRAM timing. RTL integration, pixels, IRQ,
FIFO/CDC and serializer tests remain under `bench/`.

Examples without Make:

```sh
python3 amiga_sw/rtg/tests/run.py
python3 amiga_sw/rtg/tests/run.py --profile 1024x768
python3 amiga_sw/rtg/tests/run.py --mmio-only
python3 amiga_sw/rtg/tests/test_driver_fallback.py --rtg-720p
```

`--cpu-netlist /path/cpu.v` optionally reuses an existing GHDL translation.
Without it, the current CPU sources are translated on every suite run. Build
products go to temporary directories and are removed afterward. Failures
return nonzero status; the simulation has a bounded cycle/time limit.
