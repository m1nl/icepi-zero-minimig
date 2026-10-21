# Testbenches

Tests added during RTG/HDMI and SDRAM/cache development live here. Production
RTL is not copied into the active test directories. Build products are generated
in temporary directories unless an existing Makefile specifies otherwise.

| Directory | Contents |
| --- | --- |
| [`input/`](input/README.md) | Firmware event timing, mouse counters, keyboard/OSD delivery and serial key transmission |
| `rtg_hdmi/` | RTG pixels/repetition, DMA addresses/contention, MMIO, IRQ, FIFO reset, HDMI timing, serializer, clock switching, audio and OSD tests |
| [`ide/`](ide/README.md) | IDE/FIFO packet phases, abort/reset recovery and ATA read/write tests |
| [`sd/`](sd/README.md) | SD SPI clock limits, byte transfers and direct sector clocks using production HDL and firmware dividers |
| `rtg_area/` | Isolated ECP5 resource assessments, equivalence checks and optimization patches |
| `cpu_cache_fsm/` | Cache handshake/FSM and TG68K paired memory accesses; small-cache variant is the default |
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
make -C bench/input test
make -C bench/ide test
make -C bench/sd test
python3 bench/rtg_hdmi/run.py
python3 bench/rtg_hdmi/run.py reset config top_config
python3 bench/rtg_hdmi/run.py audio_counter
python3 bench/rtg_hdmi/run.py audio_stream
python3 bench/rtg_hdmi/run.py avi_checksum
python3 bench/rtg_hdmi/run.py repeat repeat720 priority viewport
python3 bench/rtg_hdmi/run.py contention addresses integrated
python3 bench/rtg_area/check_config_paths.py
python3 bench/cpu_cache_fsm/run.py
bash bench/rtg_hdmi/run_cpu_mmio.sh
make -C amiga_sw/rtg test
```

The default RTG runner checks FIFO reset, register transactions, RTG/native
interrupt isolation, audio CDC, OSD, HDMI reset/events and native-width RTG pixels. The repetition and priority tests exercise all twelve repeat
combinations and all three pixel formats. The viewport test covers minimum
320x192 source viewports, black borders, single-line split sections and exact FIFO
consumption. `repeat720` repeats the pixel checks at 1280-wide/74.25 MHz.
The CPU/driver tests additionally
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

The `config` case checks 1280x720 totals, sync widths/polarities, CEA code,
request alignment and native fallback. The `reset` case checks the default
1024x768 profile. `top_config` checks forwarding of custom active dimensions
and the fixed 4096-cycle preparation delay; unrelated VHDL
peripherals are intentionally unbound in that elaboration check.

RTG frame requests arrive during blanking, one cycle before the first pixel
request. Standalone raster generators follow the same timing as HDMI so frame
configuration is registered before FIFO consumption starts.

The audio CDC module has no reset input or HDL initialization. Its bench seeds
handshake state once at simulation startup and checks capture, hold and clock
switching afterward; it does not establish FPGA power-up behavior.
The separate `audio_counter` case checks the HDMI sample-enable accumulator
against its original recurrence at native, 66 MHz and 74.25 MHz pixel rates,
including 44.1/48 kHz audio, asynchronous reset and live native/RTG switching.
The optional `audio_queue` case tests the saved LUTRAM experiment in
`rtl/hdmi/packet_picker.sv.bak`, rather than the restored production picker.
It requires that reference file and is excluded from the default quick suite.
Run it explicitly with `python3 bench/rtg_hdmi/run.py audio_queue`.
It checks 16/24-bit sample ordering and stability through
the real packet assembler, including serialized payload/header BCH, consecutive
packets, simultaneous capture/completion, full-queue overrun, field-end retry,
reset and bank/IEC frame wrap.
The longer `audio_stream` case checks continuous 48 kHz audio across two frames
using the real HDMI scheduler in native wide mode and both RTG raster profiles;
it verifies ordered delivery without sample loss while active pixels defer
audio transmission. It uses Verilator by default.
The `avi_checksum` case checks the transmitted AVI header/body sum for all 256
VICs, with module defaults, core defaults and custom fields including bar bytes.

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
