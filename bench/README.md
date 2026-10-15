# Testbenches

Tests added during RTG/HDMI and SDRAM/cache development live here. Production
RTL is not copied into the active test directories. Build products are generated
in temporary directories unless an existing Makefile specifies otherwise.

| Directory | Contents |
| --- | --- |
| `rtg_hdmi/` | RTG pixels/repetition, DMA addresses/contention, MMIO, IRQ, FIFO reset, HDMI timing, serializer, clock switching, audio and OSD tests |
| [`ide/`](ide/README.md) | IDE/FIFO packet phases, abort/reset recovery and ATA read/write tests |
| `rtg_area/` | Isolated ECP5 resource assessments, equivalence checks and optimization patches |
| `cpu_cache_fsm/` | Cache handshake/FSM tests; working small-cache variant is the default |
| `cpu_cache_tags/` | Historical parameterized cache tag tests |
| `cpu_cache_sdram/`, `cpu_cache_sdram_verilator/` | Existing SDRAM/cache integration benches, including the RTG interface additions |
| `archive/` | Earlier temporary reproductions and their supporting RTL snapshots |
| [`../amiga_sw/rtg/tests/`](../amiga_sw/rtg/tests/README.md) | Driver callback tests and historical driver ROMs/scripts |

Firmware regression tests for ATAPI, HDD, FAT and SD access live in
[`fw/ctrl_832/tests/`](../fw/ctrl_832/tests/README.md). Run them with
`make -C fw/ctrl_832/tests test`.

## Current regressions

Run from the repository root (the Python runners also work from other directories):

```sh
make -C bench/ide test
python3 bench/rtg_hdmi/run.py
python3 bench/rtg_hdmi/run.py repeat priority
python3 bench/rtg_hdmi/run.py contention addresses integrated
python3 bench/cpu_cache_fsm/run.py
bash bench/rtg_hdmi/run_cpu_mmio.sh
make -C amiga_sw/rtg test
```

The default RTG runner checks FIFO reset, register transactions, RTG/native
interrupt isolation, audio CDC, OSD, HDMI reset/events and native-width RTG pixels. The repetition and priority tests exercise all nine repeat
combinations and all three pixel formats. The CPU/driver tests additionally
require GHDL and installed vasm. The driver test target downloads missing
headers and translates the current CPU once for both raster profiles. Driver
test source lives under `amiga_sw/rtg/tests/`; the old entry point in
`bench/rtg_hdmi/test_driver_fallback.py` delegates there. Icarus Verilog and Python 3 are required. Full-frame and SDRAM tests use
Verilator by default because Icarus is much slower for these tests; use
`--sim iverilog` to override it.

For the actual ECP5 serializer model, point to your installed Diamond models:

```sh
python3 bench/rtg_hdmi/run.py serializer clocks --lattice-models \
    "$HOME/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u"
```

The model files are not copied into this repository. This test checks actual
serialized data and clock alignment; `tmds_stubs.v` is only for HDMI timing tests.

The longer SDRAM address/contention tests use the real controller and cache.
Their data pins are mocked; they check arbitration, addresses, burst boundaries
and frame progress, rather than SDRAM electrical timing. Example with Verilator:

```sh
CCACHE_DISABLE=1 verilator --binary --timing -Wno-fatal -DSOC_SIM \
    --output-split 0 --output-split-cfuncs 0 \
    --top-module rtg_sdram_address_tb --Mdir /tmp/rtg-sdram-test \
    bench/rtg_hdmi/rtg_sdram_address_tb.v \
    rtl/rtg/rtg_video.v rtl/rtg/rtg_async_fifo.v \
    rtl/sdram/sdram_ctrl.v rtl/sdram/cpu_cache_new.v \
    rtl/sdram/dpram_inf_256x32.v rtl/sdram/dpram_inf_be_1024x32.v \
    rtl/sdram/dpram_inf_generic.v
/tmp/rtg-sdram-test/Vrtg_sdram_address_tb
```

## Testbench assumptions

The audio CDC module has no reset input or HDL initialization. Its bench seeds
handshake state once at simulation startup and checks capture, hold and clock
switching afterward; it does not establish FPGA power-up behavior.

OSD enable latches on its start-request edge. The first requested pixel uses
the previous frame's enable, and the bench checks that transition explicitly.
The clock-switch test follows the current policy: both PLLs must be locked
before HDMI reset releases, even when native video is selected.

The basic RTG pixel bench uses native-width rows. The earlier 64-pixel single-row
sections are too short for fixed prefill after the short-section clamps were
removed. It still checks first/last-row splits, all formats, starvation,
frame restart and disable during a transfer.

## Historical tests

`cpu_cache_fsm/run.py --variant root` and `cpu_cache_tags/run.py` target an
earlier root-level cache interface/layout and still need adapting. The working
small-cache FSM variant remains the default. These cache tests are separate
from the RTG/HDMI regressions.

`archive/` preserves historical sources and intentionally failing reproductions;
see its README before running them against current RTL.
