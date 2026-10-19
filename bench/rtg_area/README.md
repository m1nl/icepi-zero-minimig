# Isolated ECP5 RTG resource assessment

## Further programmable-viewport LUT experiments

Configuration readback removal and explicit stride have now been applied.
The final RTL maps to **845 LUT4, 127 CCU2C, 641 flip-flops, three EBR,
165 PFUMX and 11 L6MUX21**: 63 fewer LUT4 and eight fewer flip-flops than
its 908-LUT baseline. The experiment below retained an intermediate stride
wire; removing it changed mapping by one LUT4. The remaining experiments
are still proposals. Applied variants become no-ops when rerun against the
working tree. Use `--variants current` to measure only the current module.

With readback removed, repeating the packed-viewport experiment gives
844 LUT4 for either packed format retaining offsets, or 850 LUT4 for either
compact layout, versus 845 unpacked. All use 127 carry cells and 641
flip-flops, and pass the adapted write-only MMIO bench. Packing remains
unapplied; it now offers at most one ordinary LUT4 in this synthesis.

Run `python3 bench/rtg_area/assess_lut_options.py` to synthesize isolated
copies of the current RTG module. Production RTL is not modified. Results,
source hash, tool version and mapped netlists go to `/tmp/rtg-lut-options`.
These experiments use Yosys 0.69 and default `synth_ecp5` options; they are
resource estimates, without functional regression or placed timing validation.

| Variant | LUT4 | CCU2C | Flip-flops | EBR | PFUMX | L6MUX21 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current programmable viewport | 908 | 124 | 649 | 3 | 174 | 11 |
| Geometry readback removed | 878 | 127 | 649 | 3 | 172 | 11 |
| Geometry/repeat/stride/split readback removed | 859 | 127 | 641 | 3 | 167 | 11 |
| Explicit stride, without automatic fallback | 898 | 124 | 649 | 3 | 146 | 11 |
| Write-only controls + explicit stride | 844 | 127 | 641 | 3 | 163 | 11 |
| Shared row decrement | 918 | 117 | 649 | 3 | 170 | 11 |
| Forced one-hot FSM | 912 | 127 | 654 | 3 | 133 | 11 |
| RGB565 only, retaining indexed pixels | 896 | 127 | 645 | 3 | 176 | 11 |
| RGB expansion after pipeline register | 915 | 124 | 647 | 3 | 173 | 11 |
| Shared address increment/stride adder | 1048 | 116 | 649 | 3 | 196 | 43 |

The recommended combination saves 64 ordinary LUT4 cells and eight
flip-flops, with three additional carry cells. Keep status, ID and display
enable readable. The driver and `rtgcheck` do not read the configuration
controls; tests that verify their readback would need adjustment.

Removing the zero-stride fallback requires the driver to program a default
bitmap pitch in SetGC, then the actual pitch in SetPanning. Preserve a
larger virtual bitmap pitch across SetDAC callbacks. Removing RGB555 support
is a separate compatibility tradeoff for a relatively small saving.

Sharing arithmetic introduces operand multiplexers, which can outweigh
the saved arithmetic. The one-hot experiment also reduces wider muxes,
so LUT4 counts alone do not establish its packed area or timing. Only a
board build can settle those tradeoffs.

These measurements were taken from isolated variants of the original RTL.
The patches in `patches/` record those experiments. Change 2 has since been
applied, followed by the timing-oriented countdown implementation described
below. Each numbered measurement starts from the same original baseline.

| Variant | LUT4 | CCU2C | Flip-flops | EBR | PFUMX | L6MUX21 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 644 | 149 | 528 | 3 | 30 | 8 |
| 1: simplify fetch decisions | 638 | 141 | 528 | 3 | 31 | 10 |
| 2: burst counters and fixed prefill | 651 | 111 | 527 | 3 | 34 | 13 |
| 3: shared FIFO RAM | 649 | 149 | 527 | 2 | 31 | 10 |
| 1 + 2 | 656 | 111 | 527 | 3 | 38 | 11 |
| 2 + 3 | 647 | 110 | 526 | 2 | 37 | 10 |
| 1 + 2 + 3 | 652 | 111 | 526 | 2 | 42 | 14 |

These are standalone `rtg_video` results from Yosys 0.69,
`synth_ecp5 -top rtg_video` with default options and production parameters
(1024x768 active, 1344x806 total, preparation delay 4096).
They include FIFO and palette memory. Source hashes and tool version are in
`metadata.json`; complete mapped cell counts are in `results.json`.

The absolute counts differ from Synplify's integrated board area report.
Compare variants with this baseline, not with the earlier Synplify numbers.
No placement, routing, or timing assessment was performed.

CCU2C carry cells consume logic resources too. Each implements the two-bit
carry function of a slice with two LUT4 positions; counting only ordinary
LUT4 cells misses those resources. `LUT4 + 2*CCU2C` is a useful estimate of
occupied LUT positions, not a packed slice count. It is 942 for the baseline
and 867 for 2 + 3 (75 fewer positions, approximately 8%). Dedicated wider
muxes, flip-flop packing and routing also matter. See the
[Lattice ECP5 family data sheet, slice and ripple-mode descriptions](https://www.latticesemi.com/-/media/LatticeSemi/Documents/DataSheets/ECP5/FPGA-DS-02012-2-2-ECP5-ECP5G-Family-Data-Sheet.ashx?document_id=50461).

## Changes

1. Remove the clamp-to-zero from remaining-word subtraction. Qualify fetches
   directly with `issued < limit`; priority remains qualified by the fetch
   request. Retain the minimum-eight-word check for non-burst-aligned widths.
2. Express transfer counters and limits in eight-word SDRAM bursts. The
   production maximum of 98,304 bursts requires 17 bits. Express addresses
   as burst index times 16 bytes. Every nonempty production section has at
   least 512 words, so its prefill target is fixed at 32 bursts / 256 words.
   Smaller test widths retain the original minimum-section prefill behavior.
3. Pack the two 512x16 FIFO banks into one 1024x16 RAM. Independent binary
   and Gray pointers, two-stage synchronizers, full/empty protection and
   reset-release logic remain. Writes and reads each select only one bank
   per cycle, permitting one shared dual-clock memory. One shared read-data
   output replaces the two independently held outputs and their mux.

Change 2 produces the largest carry-logic reduction. Change 3 demonstrably
saves one EBR, but alone slightly increases ordinary LUT use. The best
measured combination is 2 + 3. Adding change 1 to that combination produces
a slightly worse mapping; standalone savings are not additive.

The shared-memory patch splits the original FIFO into a pointer-control
module and an RTG-owned RAM. The source file keeps its existing filename,
but its module becomes `rtg_fifo_control`. It retains both banks' capacity
and screen-drag support. This is not a reduction to a single logical FIFO.

## Validation

All seven variants pass simulations using 64-pixel and 1024-pixel rows:
RGB565, RGB555, indexed palette, split rows including first/last rows,
FIFO wraparound, starvation, frame restart, and disable during a transfer.
The wider bench uses 12 active rows and the production horizontal timing;
synthesis uses the full production 768 active rows.

`fetch_equivalence.v` proves, with Yosys SAT, that original and revised fetch
requests, priorities, and byte offsets agree for all burst-aligned 17-bit
counts and occupancy values. This is a combinational proof, not formal
equivalence of the complete two-clock state machine or RAM contents.

The temporary bench copies omit the obsolete `clk_pixel` connection when
the current RTG module does not expose that port. No clocking or interrupt
changes are introduced into any RTL variant.

## Reproduce

Run from the repository root with Yosys and Icarus Verilog installed:

```sh
python3 bench/rtg_area/assess.py --baseline-ref 58d2d6a \
    --output /tmp/rtg-area-assessment --jobs 2
```

The Git baseline reference keeps this assessment reproducible after an
optimization has been applied to the working RTL. Omit it to assess an
unoptimized working-tree baseline.

The output directory contains isolated RTL, patches, simulation logs,
Yosys logs, JSON netlists, source metadata, and results. The script does not
modify production RTL or install dependencies. To rerun a subset against
the same source snapshot:

```sh
python3 bench/rtg_area/assess.py --baseline-ref 58d2d6a \
    --output /tmp/rtg-area-assessment --variants 23_bursts_shared
```

## Timing-oriented countdown implementation

The working RTG controller now keeps two saturating remaining-burst counters
and two running raw addresses. Eligibility and priority use per-bank zero/
constant tests, followed by selection. The old limit-minus-issued arithmetic
and base-plus-issued-offset adder are absent from the SDRAM request/address
paths. The update increment/decrement arithmetic is shared between banks and
terminates at RTG registers. A stable split flag and six-bit bottom-prefill
counter preserve ownership and prefill after a section has finished fetching.
Small-width simulations retain their original partial-section prefill targets.

Compared with change 2 alone, standalone Yosys results are:

| Resource | Change 2 | Countdown | Difference |
| --- | ---: | ---: | ---: |
| LUT4 | 651 | 745 | +94 |
| CCU2C | 111 | 92 | -19 |
| Flip-flops | 527 | 513 | -14 |
| EBR | 3 | 3 | 0 |
| PFUMX | 34 | 76 | +42 |
| L6MUX21 | 13 | 9 | -4 |

This trades more ordinary LUTs for fewer carry cells and registers. It is a
structural timing fix, not an overall area reduction in this Yosys mapping.
Diamond placement/routing must confirm timing closure; no new constraints or
extra request-pipeline latency have been introduced.

Cycle-by-cycle comparison against change 2 checks request, priority, address
and pixel output for small and 1024-pixel rows, all formats, splits, starvation
and restart. A third case crosses the raw 2 MiB bank boundary and wraps at
64 MiB. The actual SDRAM arbiter/cache contention test also passes with host,
Amiga CPU, RTG and refresh progress, and no FIFO overflow or frame fault.
This does not validate physical SDRAM electrical timing.

Reproduce the functional comparison and standalone synthesis with:

```sh
python3 bench/rtg_area/assess_countdown.py --output /tmp/rtg-countdown-check
```

Use `--skip-synthesis` for just the cycle comparisons. The golden controller
is generated from Git revision `58d2d6a` plus the measured change 2, so the
comparison remains reproducible after edits to the working RTL.

## Frame-total parameter assessment

`assess_totals.py` compares temporary variants of the pre-removal RTL, including
both FIFOs and palette RAM. It leaves production sources unchanged. The default
Git baseline is `5603d14da7e703b238aa377265c61cf815cf5148`; use `--baseline-ref`
to select another revision that still has the total parameters.

```sh
python3 bench/rtg_area/assess_totals.py --simulate
```

The default output directory `/tmp/rtg-totals-assessment` contains source
snapshots, patches, hashes, tool version, mapped netlists, logs and results.
`--simulate` runs the current pixel/format/split/starvation/restart regression
against each variant, removing obsolete parameter overrides only in temporary
bench copies. Requires Yosys and, for simulation, Verilator and a C++ compiler.

Measured with Yosys 0.69 for ECP5, default 1024x768 parameters, 2026-10-18:

| Variant | LUT4 | CCU2C | Flip-flops | EBR | PFUMX | L6MUX21 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current RTL | 845 | 121 | 622 | 3 | 159 | 11 |
| Remove unused H_TOTAL | 845 | 121 | 622 | 3 | 159 | 11 |
| Remove both totals and vertical wrap mux | 834 | 121 | 622 | 3 | 159 | 11 |
| Also count rows only while frame_active | 835 | 121 | 622 | 3 | 160 | 11 |

All four variants passed simulation. The free-running variant resets its row
counter on HDMI's frame request; it increments through blanking without a
total-height comparison. The active-row variant stops at V_ACTIVE instead.
The measured baseline RTG SHA-256 is
`14932943e3da87e5a9aa4f0e8ca103d58775d7677fdc07bfeae91b8bb8e81661`.
These are isolated synthesis counts, not Diamond routed slice/timing results.

## Programmable viewport assessment

`assess_viewport.py` compares the fixed-canvas controller at Git revision
`f92112f5b5781ab970e09cd74922b3e14cc703c0` with the current working controller.
It includes both asynchronous FIFOs and palette RAM, and writes source snapshots,
hashes, tool version, netlists and logs to `/tmp/rtg-viewport-assessment`.

```sh
python3 bench/rtg_area/assess_viewport.py
```

Measured with Yosys 0.69 for ECP5, 2026-10-19:

| Variant | LUT4 | CCU2C | Flip-flops | EBR | PFUMX | L6MUX21 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Fixed canvas | 834 | 121 | 622 | 3 | 159 | 11 |
| Viewport with two wide configuration stages | 972 | 138 | 768 | 3 | 185 | 11 |
| Viewport with direct held configuration | 966 | 138 | 686 | 3 | 182 | 11 |
| Direct configuration and fixed prefill | 913 | 127 | 666 | 3 | 152 | 11 |
| Direct split/format/repeat, no pixel format copies | 908 | 124 | 649 | 3 | 174 | 11 |
| Current delta from fixed canvas | +74 | +3 | +27 | 0 | +15 | 0 |

The additional geometry registers, frame snapshots and variable section budgets
increase area. Low coordinate bits are excluded from viewport comparisons;
registered window decisions keep boundary arithmetic out of FIFO enables. The
driver supplies row fetch length, avoiding hardware division.

The current controller uses its held `config_sys_*` frame snapshots directly;
only the one-bit readiness signal is synchronized. Split, pixel format and
horizontal repetition use these snapshots directly, including RGB decode.
SDC/LPF false-path the `config_sys_*` sources. This prefix feeds only pixel
logic; DMA vertical repetition is stored separately in `vertical_repeat` and
stays timed. `horizontal_window` and `vertical_window` are dynamic scan-position
state, rather than copied mode settings. Removing the two 41-bit
configuration transfer banks saved 82 flip-flops. Temporary mode-change artifacts
are acceptable; FIFO-pointer, reset, event and readiness synchronizers remain.

The initial register increase was dominated by geometry copies: 26 MMIO bits,
27 snapshot bits (including H-start-zero), and 54 additional transfer bits.
The direct-configuration variant removes all 82 transfer registers, including
28 that existed in the fixed-canvas controller.

With the driver enforcing a minimum source viewport of 320x192 and maximal
fitting repetition, each indexed row meets the fixed 32/16/11/8-burst prefill
for H=1x/2x/3x/4x. This remains true for a one-line split section. Consequently,
the short-section accumulator, counters and two preparation states have been
removed. Both banks now share one registered prefill target. The final design
saves 64 LUT4s and 119 flip-flops versus the initial viewport implementation,
with BRAM unchanged. The final step removes the 14-bit split/format/repeat copy
and three pixel-format pipeline bits. Removing them does not change pixel
latency; transient mode-change artifacts are accepted.

Temporary ablations of the original two-stage viewport variant measured:

| Feature disabled for measurement | LUT4 saved | Flip-flops saved |
| --- | ---: | ---: |
| Bounded short-section prefill calculation | 62 | 20 |
| Programmable H/V bounds (tie to full raster) | 42 | 104 |
| Readback of five new configuration registers | 22 | 0 |
| Horizontal 4x support | 11 | 4 |
| Driver-programmable row length (derive fixed-profile lengths) | 4 | 10 |

These are independent ablations of the initial implementation, not additive
savings: shared logic and mapping change between variants. They are not all
feature-equivalent implementations. In particular, arbitrary narrow rows would
need bounded prefill; the production driver now excludes those cases instead.

Check the safety of the configuration false-path prefix with:

```sh
python3 bench/rtg_area/check_config_paths.py
```

This traverses a flattened logical netlist to the first sequential endpoints
and rejects any config_sys_* path into clk_sys registers or RAM write ports.
It does not establish that Synplify/Diamond retained every wildcard cell name;
that must be checked in the next board build report.

These are standalone synthesis counts. No FPGA build or routed timing closure
is established by this assessment. Run `video repeat viewport priority` in the
RTG runner for pixels/borders/repetition/splits and `contention addresses integrated`
for SDRAM/HDMI integration; driver simulations are under `amiga_sw/rtg/tests/`.

## Packed viewport register assessment

Run this while the working core still has separate start/stop registers:

```sh
python3 bench/rtg_area/assess_viewport_packing.py
```

The script writes temporary RTL, adapted register benches, source hash, mapped
netlists and logs to `/tmp/rtg-viewport-packing`. Production RTL and driver
register maps are not changed. It requires Yosys and Icarus Verilog.

Measured against the direct-configuration/fixed-prefill controller, Yosys 0.69
for ECP5, 2026-10-19. Register write/extraction/readback benches passed for every
variant. EBR remains three and L6MUX21 remains eleven.

| Layout | LUT4 | CCU2C | Flip-flops | PFUMX |
| --- | ---: | ---: | ---: | ---: |
| Separate H/V start/stop (current) | 908 | 124 | 649 | 174 |
| Packed bytes, keep H/V/row offsets | 905 | 124 | 651 | 177 |
| Dense bits, keep H/V/row offsets | 901 | 124 | 651 | 182 |
| Packed bytes, compact offsets | 906 | 124 | 651 | 178 |
| Dense bits, compact offsets | 899 | 127 | 651 | 178 |

Byte layouts put start in the low byte and stop in the high byte, retaining
seven significant bits per H bound and six per V bound. Dense layouts put H
start/stop at bits 6:0/13:7 and V start/stop at bits 5:0/11:6. Unused bits read
zero. Existing-offset variants use H at $18, V at $1c and row length at $20;
compact variants use $18/$1a/$1c respectively, relative to $B80100.

Packing reduces configuration writes from four to two, but retains all 26
geometry storage bits. Readback distributes values across more output bits,
adding two flip-flops after optimization. Byte packing saves two to three
LUT4s, depending on offsets. Compact dense packing saves nine LUT4s but adds
three carry cells and four PFUMX cells. These results were refreshed after
removing the remaining pixel-domain configuration copies; the changed mapping
also changes the relative layout costs. None establishes a routed slice saving.
No packed register layout has been applied to production RTL or the driver.

## HDMI audio packet LUTRAM queue reference experiment

Production has been restored to the original register-based capture banks and
packet-copy implementation after the Diamond build failed to route at
12,143/12,144 occupied slices. The LUTRAM candidate remains in the user-saved
`rtl/hdmi/packet_picker.sv.bak`; the measurements below describe that experiment.

The candidate stores up to twelve stereo samples in three circular
packet banks. Four separate distributed memories provide the four sample
positions in parallel, with synchronous writes and asynchronous reads. The
active packet reads its bank directly; there is no separate packet copy.
For 16-bit audio, each memory is 16x32, with only bank addresses 0..2 used.
The inferred ECP5 implementation uses 32 DPR16X4 primitives in total.

The committed-bank count includes the transmitting bank until its last pixel.
This prevents capture from overwriting queued or active data. Field-end aborts
retain the head for retry; reset flushes queue metadata without clearing RAM.
When full, the picker rejects the incoming sample and sets its sticky
`audio_overflow` output, cleared by reset. The reference tests monitor this
diagnostic directly; the restored production picker has no such output.

Run the resource comparison with Yosys and the Slang frontend installed:

```sh
python3 bench/rtg_area/assess_hdmi_audio.py --baseline-ref HEAD \
    --candidate-picker rtl/hdmi/packet_picker.sv.bak
```

Choose a Git revision containing the original packet picker. The script takes
the baseline picker from that revision and the candidate from the supplied
file; all other HDL comes from the working tree. Omitting `--candidate-picker`
measures the production picker instead. Source hashes, Git revision, synthesis scripts, optimized
generic netlists, mapped netlists and logs go to `/tmp/hdmi-audio-area`.
Each variant uses the same relative source names to keep mapping comparable.

Measured with Yosys 0.69, `opt -full; wreduce; opt -full; synth_ecp5`, default
HDMI parameters except 16-bit audio:

| Resource | Packet-copy baseline | LUTRAM queue | Difference |
| --- | ---: | ---: | ---: |
| Ordinary LUT4 | 982 | 999 | +17 |
| CCU2C | 186 | 186 | 0 |
| Flip-flops | 425 | 301 | -124 |
| DPR16X4 | 32 | 32 | 0 |
| PFUMX | 180 | 203 | +23 |
| L6MUX21 | 51 | 50 | -1 |
| EBR | 0 | 0 | 0 |

These are whole-HDMI estimates excluding the serializer, which is black-boxed
equally in both variants. For Slang/Yosys compatibility, the temporary sources
combine an existing pair of asynchronous reset signals and remove the existing
`mode` initialization that conflicts with ECP5 FF legalization. Production
reset/initialization RTL is unchanged. Distributed RAM consumes LUT positions;
its unchanged count matters alongside ordinary LUT4 counts. This change trades
additional control/mux logic for fewer registers. The later Diamond build
allocated 96 RAM slices to the audio storage and failed routing; these Yosys
estimates do not establish board timing closure.

Validation commands:

```sh
python3 bench/rtg_hdmi/run.py audio_queue # Requires the saved .bak candidate
python3 bench/rtg_hdmi/run.py audio_stream
python3 bench/rtg_hdmi/run.py
```

The reference queue bench checks 16/24-bit ordering, stable packet contents, serialized
payload/header BCH and IEC frame numbering, consecutive packets, simultaneous
capture/completion, overrun protection, field-end retry, reset and pointer wrap.
The stream bench uses the actual HDMI scheduler at native wide and both RTG
profiles for two frames, checking continuous 48 kHz delivery without sample loss
using the production picker.
