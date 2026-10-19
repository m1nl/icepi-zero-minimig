#!/usr/bin/env python3
"""Measure the programmable viewport against the fixed-canvas ECP5 baseline."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE = 'f92112f5b5781ab970e09cd74922b3e14cc703c0'
METRICS = ('LUT4', 'CCU2C', 'TRELLIS_FF', 'DP16KD', 'PFUMX', 'L6MUX21')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/rtg-viewport-assessment'))
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    hashes = {}
    for variant in ('baseline', 'viewport'):
        folder = out / variant
        folder.mkdir(exist_ok=True)
        sources = []
        hashes[variant] = {}
        for name in ('rtg_video.v', 'rtg_async_fifo.v'):
            relative = 'rtl/rtg/' + name
            data = (subprocess.check_output(['git', 'show', BASELINE + ':' + relative], cwd=ROOT)
                    if variant == 'baseline' else (ROOT / relative).read_bytes())
            target = folder / name
            target.write_bytes(data)
            hashes[variant][name] = hashlib.sha256(data).hexdigest()
            sources.append(str(target))
        netlist = folder / 'netlist.json'
        script = ('read_verilog ' + ' '.join('"' + s + '"' for s in sources) +
                  '; synth_ecp5 -top rtg_video -json "' + str(netlist) + '"; stat')
        with (folder / 'yosys.log').open('w') as log:
            subprocess.run(['yosys', '-Q', '-T', '-p', script], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        cells = json.loads(netlist.read_text())['modules']['rtg_video']['cells']
        counts = Counter(cell['type'] for cell in cells.values())
        results[variant] = {key: counts[key] for key in METRICS}
        print(variant + ': ' + json.dumps(results[variant]), flush=True)
    results['delta'] = {key: results['viewport'][key] - results['baseline'][key]
                        for key in METRICS}
    report = dict(baseline_ref=BASELINE, hashes=hashes, results=results,
                  yosys=subprocess.check_output(['yosys', '-V'], text=True).strip())
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('delta: ' + json.dumps(results['delta']), flush=True)


if __name__ == '__main__':
    main()
