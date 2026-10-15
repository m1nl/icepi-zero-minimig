#!/usr/bin/env python3
"""Run actual .card callbacks on the TG68K CPU with behavioral RAM/MMIO.

Requires driver headers in amiga_sw/rtg/.deps, vasm, GHDL and Icarus.
An existing GHDL-generated TG68K netlist can be reused with --cpu-netlist.
This verifies callback behavior, not Picasso96Mode's own code or SDRAM timing.
"""
import argparse
import os
from pathlib import Path
import tempfile

from sim_core import assemble_rom, build_cpu, run_rom

DRIVER = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cpu-netlist', type=Path)
    parser.add_argument('--rtg-720p', action='store_true')
    parser.add_argument('--vasm', default=os.environ.get(
        'VASM', str(Path(os.environ.get('VBCC', Path.home() / 'vbcc')) / 'bin/vasmm68k_mot')))
    parser.add_argument('--inc-asm', type=Path, default=DRIVER / '.deps/NDK_3.9/Include/include_i')
    parser.add_argument('--p96-private', type=Path, default=DRIVER / '.deps/Picasso96Develop/PrivateInclude')
    parser.add_argument('--p96-public', type=Path, default=DRIVER / '.deps/Picasso96Develop/Include')
    args = parser.parse_args()
    source = (DRIVER / 'minimig.card.asm').read_text()
    # Expectations are independent of the assembly tables.
    if args.rtg_720p:
        widths, heights = (1280, 640, 416), (720, 360, 240)
        htotals, vtotals = (1650, 825, 550), (750, 375, 250)
        hstarts, vstarts = (110, 55, 42), (5, 3, 2)
        hsizes, vsizes = (40, 20, 13), (5, 3, 2)
        clocks = (74250000, 37125000, 24750000, 37125000, 18562500,
                  12375000, 24750000, 12375000, 8250000)
    else:
        widths, heights = (1024, 512, 320), (768, 384, 256)
        htotals, vtotals = (1344, 672, 448), (806, 403, 269)
        hstarts, vstarts = (24, 12, 19), (3, 2, 1)
        hsizes, vsizes = (136, 68, 45), (6, 3, 2)
        clocks = (66000000, 33000000, 22000000, 33000000, 16500000,
                  11000000, 22027295, 11013648, 7342432)
    dimensions = [(w, h) for w in widths for h in heights]
    dimensions += [
        (320, 240), (800, 600), (960, 384), (640, 480), (1, 1),
        (widths[2]-1, heights[2]-1), (widths[2]+1, heights[2]+1),
        (widths[1]-1, heights[1]-1), (widths[1]+1, heights[1]+1),
        (widths[0], 1), (1, heights[0]),
        (0, heights[0]), (widths[0], 0), (0, 0),
        (widths[0]+1, heights[0]), (widths[0], heights[0]+1),
        (65535, 65535),
    ]
    cases = []
    for w, h in dimensions:
        if w == 0 or h == 0 or w > widths[0] or h > heights[0]:
            hx, vy = 0, 0
        else:
            hx = 3 if w <= widths[2] else 2 if w <= widths[1] else 1
            vy = 3 if h <= heights[2] else 2 if h <= heights[1] else 1
        cases.append((w, h, hx, vy))
    records = []
    for w, h, hx, vy in cases:
        if hx:
            index = hx - 1 + 3 * (vy - 1)
            encoding = hx - 1 + 4 * (vy - 1)
            canvas_w = widths[hx - 1]
            canvas_h = heights[vy - 1]
            ht = htotals[hx - 1]
            vt = vtotals[vy - 1]
            hs = hstarts[hx - 1] + canvas_w - w
            vs = vstarts[vy - 1] + canvas_h - h
            hb, vb = ht - w, vt - h
        else:
            encoding, index = 65535, 0
            ht, vt = htotals[0], vtotals[0]
            hb, vb = ht - widths[0], vt - heights[0]
            hs, vs = hstarts[0], vstarts[0]
        records.append(f'    dc.w {w},{h},{encoding},{index}\n'
                       f'    dc.l {clocks[index]}\n'
                       f'    dc.w {ht},{vt},{hb},{vb},{hs},{vs}\n'
                       f'    dc.w {hsizes[hx-1] if hx else hsizes[0]},'
                       f'{vsizes[vy-1] if vy else vsizes[0]}\n')
    rom = '''    machine 68020
    include libraries/Picasso96.i
    include boardinfo.i
    include settings.i
CardData_ModeValid = gbi_CardData+26
CardData_VRepeat = gbi_CardData+28
RTG_DISPLAY_SWITCH = $10
RTG_REPEAT = $14
RTG_STRIDE = $16
RTG_SPLIT_ROW = $12
RTG_RGB_FORMATS EQU (RGBFF_CLUT|RGBFF_R5G6B5|RGBFF_R5G5B5)
BUG macro
    endm
    org 0
    dc.l $2000,$100
    dcb.b $100-*,0
start:
    lea $1400,a0
    lea $1800,a4
    lea cases(pc),a3
    move.l #$b80100,gbi_RegisterBase(a0)
    move.l #$800000,gbi_MemoryBase(a0)
'''
    for factor in (1, 2, 3):
        last = heights[factor - 1] - 1
        rom += f'''    move.w #{factor},CardData_VRepeat(a0)
    move.w #{last},d0
    bsr SetSplitPosition
    cmpi.w #{last * factor},$b80112
    bne fail
    move.w #{last+1},d0
    bsr SetSplitPosition
    cmpi.w #$7ff,$b80112
    bne fail
'''
    rom += f'    move.w #{len(cases)-1},d4\n'
    rom += '''case_loop:
    moveq #0,d6
format_loop:
    moveq #RGBFB_CLUT,d7
    tst.w d6
    beq .format_ready
    moveq #RGBFB_R5G6B5,d7
    cmpi.w #1,d6
    beq .format_ready
    moveq #RGBFB_R5G5B5,d7
.format_ready:
    movea.l a4,a1
    move.w (a3),gmi_Width(a1)
    move.w 2(a3),gmi_Height(a1)
    bsr ModeRepeat
    cmp.w 4(a3),d0
    bne fail
    move.l #25000000,d0
    bsr ResolvePixelClock
    cmp.w 6(a3),d0
    bne fail
    move.l 8(a3),d3
    cmp.l gmi_PixelClock(a1),d3
    bne fail
    move.w 12(a3),d3
    cmp.w gmi_HorTotal(a1),d3
    bne fail
    move.w 14(a3),d3
    cmp.w gmi_VerTotal(a1),d3
    bne fail
    move.w 16(a3),d3
    cmp.w gmi_HorBlankSize(a1),d3
    bne fail
    move.w 18(a3),d3
    cmp.w gmi_VerBlankSize(a1),d3
    bne fail
    move.w 20(a3),d3
    cmp.w gmi_HorSyncStart(a1),d3
    bne fail
    move.w 22(a3),d3
    cmp.w gmi_VerSyncStart(a1),d3
    bne fail
    move.w 24(a3),d3
    cmp.w gmi_HorSyncSize(a1),d3
    bne fail
    move.w 26(a3),d3
    cmp.w gmi_VerSyncSize(a1),d3
    bne fail
    bsr GetPixelClock
    cmp.l 8(a3),d0
    bne fail
    moveq #0,d0
    bsr SetGC
    moveq #1,d0
    bsr SetSwitch
    cmpi.w #$ffff,4(a3)
    beq .invalid
    cmpi.w #1,CardData_ModeValid(a0)
    bne fail
    move.w $b80110,d0
    cmpi.w #1,d0
    bne fail
    move.w $b80114,d0
    cmp.w 4(a3),d0
    bne fail
    moveq #0,d0
    move.w (a3),d0
    moveq #0,d1
    moveq #0,d2
    movea.l #$800000,a1
    bsr SetPanning
    move.w (a3),d3
    tst.w d6
    beq .row_bytes
    add.w d3,d3
.row_bytes:
    addi.w #15,d3
    andi.w #$fff0,d3
    lsr.w #4,d3
    move.w $b80116,d0
    cmp.w d3,d0
    bne fail
    moveq #0,d0
    bsr SetSwitch
    bra .next
.invalid:
    tst.w CardData_ModeValid(a0)
    bne fail
    move.w $b80110,d0
    tst.w d0
    bne fail
.next:
    addq.w #1,d6
    cmpi.w #3,d6
    bne format_loop
    adda.w #28,a3
    dbra d4,case_loop
    move.w #$600d,$1000
loop:
    bra loop
fail:
    move.w #$dead,$1000
    bra fail
cases:
'''
    rom += ''.join(records)
    rom += source[source.index('; Build-time physical raster.'):source.index('; Define RTG_DEBUG')]
    rom += source[source.index('SetSwitch:'):source.index('SetDAC:')]
    rom += source[source.index('SetGC:'):source.index('CalculateMemory:')]
    rom += source[source.index('ResolvePixelClock:'):source.index('SetInterrupt:')]
    rom += source[source.index('SetSplitPosition:'):source.index('ProgEnd:')]
    with tempfile.TemporaryDirectory(prefix='rtg-driver-fallback-') as name:
        folder = Path(name)
        asm = folder / 'rom.asm'
        asm.write_text(rom)
        binary = assemble_rom(asm, folder, args.vasm, (
            *(['-DRTG_720P=1'] if args.rtg_720p else []),
            '-I', str(args.inc_asm.resolve()) + '/',
            '-I', str(args.p96_private.resolve()) + '/',
            '-I', str(args.p96_public.resolve()) + '/'))
        if binary.stat().st_size >= 0x1000:
            raise RuntimeError('ROM overlaps test status/BoardInfo RAM')
        cpu = args.cpu_netlist.resolve() if args.cpu_netlist else build_cpu(folder)
        raster = (1280, 720, 1650, 750) if args.rtg_720p else (1024, 768, 1344, 806)
        run_rom(binary, folder, cpu, driver=True, raster=raster)
        print(f'PASS: {len(cases)} mode cases, three formats, clocks, timing, '
              'RTG switch, stride and split bounds', flush=True)



if __name__ == '__main__':
    main()
