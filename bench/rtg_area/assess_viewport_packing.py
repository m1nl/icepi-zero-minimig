#!/usr/bin/env python3
"""Assess packed viewport bounds in temporary RTL, without changing the MMIO ABI."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
METRICS = ('LUT4', 'CCU2C', 'TRELLIS_FF', 'DP16KD', 'PFUMX', 'L6MUX21')


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Working RTL no longer has the unpacked layout: ' + old)
    return text.replace(old, new, 1)


def packed(source, *, compact, dense):
    hshift, vshift = (7, 6) if dense else (8, 8)
    va, ra = (0x11a, 0x11c) if compact else (0x11c, 0x120)
    source = replace_once(source, "      11'h118: h_start <= reg_d[6:0];\n"
                          "      11'h11a: h_stop <= reg_d[6:0];\n"
                          "      11'h11c: v_start <= reg_d[5:0];\n"
                          "      11'h11e: v_stop <= reg_d[5:0];\n"
                          "      11'h120: source_bursts <= reg_d[7:0];", f"""      11'h118: begin
        h_start <= reg_d[6:0];
        h_stop <= reg_d[{hshift+6}:{hshift}];
      end
      11'h{va:03x}: begin
        v_start <= reg_d[5:0];
        v_stop <= reg_d[{vshift+5}:{vshift}];
      end
      11'h{ra:03x}: source_bursts <= reg_d[7:0];""")
    return source, hshift, vshift, va, ra


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/rtg-viewport-packing'))
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'rtl/rtg/rtg_video.v').read_text()
    fifo = (ROOT / 'rtl/rtg/rtg_async_fifo.v').read_text()
    bench = (ROOT / 'bench/rtg_hdmi/rtg_register_tb.v').read_text()
    variants = {'separate': (source, None)}
    for compact in (False, True):
        for dense in (False, True):
            name = ('compact_' if compact else 'keep_offsets_') + ('dense' if dense else 'bytes')
            result = packed(source, compact=compact, dense=dense)
            variants[name] = (result[0], result[1:])

    def assess(item):
        name, (rtl, layout) = item
        target = folder / name
        target.mkdir(exist_ok=True)
        video = target / 'rtg_video.v'
        video.write_text(rtl)
        (target / 'rtg_async_fifo.v').write_text(fifo)
        test = bench
        if layout:
            hs, vs, va, ra = layout
            a = test.index('        // Write-only controls must not alias the bases;')
            b = test.index('        if({dut.rtg_base', a)
            hvalue, vvalue = 2 | (80 << hs), 1 | (45 << vs)
            test = test[:a] + f"""        // One word writes both bounds; verify write-only reads and field extraction.
        access(11'h118,1,16'h{hvalue:04x});
        access(11'h{va:03x},1,16'h{vvalue:04x});
        access(11'h{ra:03x},1,120);
        read_id(11'h118,16'h8321);
        read_id(11'h{va:03x},16'h8321);read_id(11'h{ra:03x},16'h8321);
        if(dut.h_start!==2 || dut.h_stop!==80 || dut.v_start!==1 || dut.v_stop!==45 || dut.source_bursts!==120)
            $fatal(1,"packed viewport extraction");
""" + test[b:]
        testfile = target / 'rtg_register_tb.v'
        testfile.write_text(test)
        commands = [
            ['iverilog', '-g2012', '-s', 'rtg_register_tb', '-o', str(target/'test'),
             str(testfile), str(video), str(target/'rtg_async_fifo.v')],
            ['vvp', str(target/'test')],
            ['yosys', '-Q', '-T', '-p',
             f'read_verilog "{video}" "{target / "rtg_async_fifo.v"}"; '
             f'synth_ecp5 -top rtg_video -json "{target / "netlist.json"}"; stat'],
        ]
        for i, command in enumerate(commands):
            with (target / ('step' + str(i) + '.log')).open('w') as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        cells = json.loads((target/'netlist.json').read_text())['modules']['rtg_video']['cells']
        counts = Counter(c['type'] for c in cells.values())
        result = {k: counts[k] for k in METRICS}
        result['mmio'] = 'PASS'
        print(name + ': ' + json.dumps(result), flush=True)
        return name, result

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = dict(pool.map(assess, variants.items()))
    report = dict(results=results, source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                  yosys=subprocess.check_output(['yosys', '-V'], text=True).strip())
    (folder/'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
