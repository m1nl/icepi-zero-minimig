#!/usr/bin/env python3
"""Measure independent RTG LUT optimizations in temporary RTL copies."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
METRICS = ('LUT4', 'CCU2C', 'TRELLIS_FF', 'DP16KD', 'PFUMX', 'L6MUX21')


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('Working RTL no longer matches: ' + old)
    return source.replace(old, new, 1)


def variants(source):
    result = {'current': source}
    geometry = r"^ *11'h(?:118|11a|11c|11e|120): reg_q <= .*;\n"
    controls = r"^ *11'h(?:112|114|116|118|11a|11c|11e|120): reg_q <= .*;\n"
    result['geometry_write_only'] = re.sub(geometry, '', source, flags=re.M)
    result['controls_write_only'] = re.sub(controls, '', source, flags=re.M)
    stride = "wire [11:0] initial_stride = stride != 0 ? stride : {4'd0, source_bursts};"
    def explicit_stride(rtl):
        if stride in rtl:
            return replace_once(rtl, stride, 'wire [11:0] initial_stride = stride;')
        if 'frame_stride <= stride;' in rtl:
            return rtl  # Optimization already applied to the working tree.
        raise ValueError('Unrecognized stride implementation')
    result['explicit_stride'] = explicit_stride(source)
    result['write_only_explicit_stride'] = explicit_stride(result['controls_write_only'])
    shared = replace_once(source, 'wire  [7:0] selected_row_left = owner ? row_left_bottom : row_left_top;',
                          '''wire  [7:0] selected_row_left = owner ? row_left_bottom : row_left_top;
wire  [7:0] next_row_left = selected_row_left - 1'b1;''')
    shared = replace_once(shared, "row_left_bottom <= row_left_bottom - 1'b1;",
                          'row_left_bottom <= next_row_left;')
    shared = replace_once(shared, "row_left_top <= row_left_top - 1'b1;",
                          'row_left_top <= next_row_left;')
    result['shared_row_decrement'] = shared
    result['one_hot_fsm'] = replace_once(source, 'reg [3:0] state;',
                                        '(* fsm_encoding = "one-hot" *) reg [3:0] state;')
    # Capability removal: the driver would need to stop advertising RGB555.
    rgb = replace_once(source, 'reg config_sys_rgb565;', "wire config_sys_rgb565 = 1'b1;")
    rgb = re.sub(r'^ *config_sys_rgb565 <= .*;\n', '', rgb, flags=re.M)
    result['rgb565_only'] = rgb
    # Keep pixel latency, but move RGB bit expansion after its stage-2 register.
    late = replace_once(source, 'reg [23:0] palette_rgb, direct_rgb;',
                         'reg [23:0] palette_rgb;\nreg [15:0] direct_word;')
    direct = '''  direct_rgb  <= config_sys_rgb565 ?
          {word_1[15:11], word_1[15:13], word_1[10:5], word_1[10:9], word_1[4:0], word_1[4:2]} :
          {word_1[14:10], word_1[14:12], word_1[ 9:5], word_1[ 9:7], word_1[4:0], word_1[4:2]};'''
    expression = direct.replace('  direct_rgb  <=', 'wire [23:0] direct_rgb =').replace('word_1', 'direct_word')
    late = replace_once(late, direct, '  direct_word <= word_1;')
    late = replace_once(late, '// Stage 1: FIFO synchronous read.', expression + '\n\n// Stage 1: FIFO synchronous read.')
    result['late_rgb_expansion'] = late
    # Share linear increment and stride addition. Extra input muxes may outweigh
    # the removed carry chain, and their timing would need separate assessment.
    addr = replace_once(source, "wire [21:0] linear_addr = (owner ? addr_bottom : addr_top) + 1'b1;\n", '')
    addr = replace_once(addr, '''wire [21:0] next_row_base = selected_row_base + frame_stride;
wire [21:0] next_addr     = selected_row_left != 1 ? linear_addr :
  repeat_row ? selected_row_base : next_row_base;''', '''wire advance_row = selected_row_left == 1 && !repeat_row;
wire [21:0] add_base = advance_row ? selected_row_base : fetch_raw[25:4];
wire [11:0] add_step = advance_row ? frame_stride : 12'd1;
wire [21:0] next_row_base = add_base + add_step;
wire [21:0] next_addr = selected_row_left == 1 && repeat_row ? selected_row_base : next_row_base;''')
    result['shared_address_adder'] = addr
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/rtg-lut-options'))
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--variants', nargs='+', help='assess only the named variants')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'rtl/rtg/rtg_video.v').read_text()
    fifo = (ROOT / 'rtl/rtg/rtg_async_fifo.v').read_text()

    def assess(item):
        name, rtl = item
        target = out / name
        target.mkdir(exist_ok=True)
        (target/'rtg_video.v').write_text(rtl)
        (target/'rtg_async_fifo.v').write_text(fifo)
        script = (f'read_verilog "{target / "rtg_video.v"}" "{target / "rtg_async_fifo.v"}"; '
                  f'synth_ecp5 -top rtg_video -json "{target / "netlist.json"}"; stat')
        with (target/'yosys.log').open('w') as log:
            subprocess.run(['yosys', '-Q', '-T', '-p', script], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        cells = json.loads((target/'netlist.json').read_text())['modules']['rtg_video']['cells']
        counts = Counter(c['type'] for c in cells.values())
        result = {k: counts[k] for k in METRICS}
        print(name + ': ' + json.dumps(result), flush=True)
        return name, result

    choices = variants(source)
    if args.variants:
        choices = {name: choices[name] for name in args.variants}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = dict(pool.map(assess, choices.items()))
    report = dict(source_sha256=hashlib.sha256(source.encode()).hexdigest(), results=results,
                  yosys=subprocess.check_output(['yosys', '-V'], text=True).strip())
    (out/'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
