# Isolated ECP5 RTG resource assessment

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
