#!/usr/bin/env python3
"""Compare an HDMI packet picker with a baseline Git revision using Yosys."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
METRICS = ('LUT4', 'CCU2C', 'TRELLIS_FF', 'TRELLIS_DPR16X4',
           'PFUMX', 'L6MUX21', 'DP16KD', 'PDPW16KD')


def synthesis_sources(sources):
    result = dict(sources)
    hdmi = result['hdmi.sv']
    # The old picker has no overflow diagnostic port. Leave it unconnected in
    # both variants, as in production, without passing it to the old interface.
    hdmi = hdmi.replace('.sub_3(sub_3),\n            .audio_overflow()',
                        '.sub_3(sub_3)')
    # Slang cannot lower this existing multiple-asynchronous-reset construct.
    hdmi = hdmi.replace(
        'always_ff @(posedge clk_pixel, posedge reset, posedge video_mode_changed)',
        'wire packet_reset = reset || video_mode_changed;\n'
        '        always_ff @(posedge clk_pixel, posedge packet_reset)')
    hdmi = hdmi.replace('if (reset || video_mode_changed)', 'if (packet_reset)')
    # Serialization is outside this comparison. Its real-valued frequency is
    # unused by the black box and unsupported as Slang black-box metadata.
    hdmi = hdmi.replace('RTG_VIDEO_RATE / 1000000.0', 'RTG_VIDEO_RATE / 1000000')
    result['hdmi.sv'] = hdmi
    result['serializer.sv'] = '''(* blackbox *) module serializer #(
    parameter NUM_CHANNELS=3, parameter VIDEO_RATE=0
)(input clk_pixel, clk_pixel_x5, reset,
  input [9:0] tmds_internal [NUM_CHANNELS-1:0],
  output [2:0] tmds, output tmds_clock);
endmodule
'''
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', default='HEAD',
                        help='Git revision with the packet-copy picker')
    parser.add_argument('--candidate-picker', type=Path,
                        help='optional candidate source, such as packet_picker.sv.bak')
    parser.add_argument('--output', type=Path, default=Path('/tmp/hdmi-audio-area'))
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    current = {p.name: p.read_text() for p in sorted((ROOT/'rtl/hdmi').glob('*.sv'))}
    if args.candidate_picker is not None:
        current['packet_picker.sv'] = args.candidate_picker.read_text()
    before = dict(current)
    before['packet_picker.sv'] = subprocess.check_output(
        ['git', 'show', args.baseline_ref + ':rtl/hdmi/packet_picker.sv'],
        cwd=ROOT, text=True)

    def assess(item):
        name, sources = item
        target = out/name
        target.mkdir(exist_ok=True)
        hashes = {name: hashlib.sha256(source.encode()).hexdigest()
                  for name, source in sources.items()}
        for filename, source in synthesis_sources(sources).items():
            (target/filename).write_text(source)
        script = ('read_slang --top hdmi -G AUDIO_BIT_WIDTH=16 '
                  '--blackboxed-module serializer ' + ' '.join(sorted(sources)) + '; '
                  'opt -full; wreduce; opt -full; write_json generic.json; '
                  # Existing mode init/reset values conflict in Yosys ECP5 FF
                  # legalization. Remove only its init, equally in both variants.
                  'setattr -unset init w:mode; '
                  'setparam -unset NUM_CHANNELS -unset VIDEO_RATE t:serializer; '
                  'synth_ecp5 -top hdmi -json netlist.json; stat\n')
        (target/'synth.ys').write_text(script)
        with (target/'yosys.log').open('w') as log:
            subprocess.run(['yosys', '-Q', '-T', '-m', 'slang', '-s', 'synth.ys'],
                           cwd=target, stdout=log, stderr=subprocess.STDOUT, check=True)
        cells = json.loads((target/'netlist.json').read_text())['modules']['hdmi']['cells']
        counts = Counter(cell['type'] for cell in cells.values())
        result = {metric: counts[metric] for metric in METRICS}
        (target/'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
        print(name + ': ' + json.dumps(result), flush=True)
        return name, result

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = dict(pool.map(assess, [('before', before), ('after', current)]))
    metadata = dict(
        results=results, baseline_ref=args.baseline_ref,
        candidate_picker=str(args.candidate_picker.resolve()) if args.candidate_picker else None,
        baseline_commit=subprocess.check_output(
            ['git', 'rev-parse', args.baseline_ref], cwd=ROOT, text=True).strip(),
        yosys=subprocess.check_output(['yosys', '-V'], text=True).strip(),
        profile='Default HDMI parameters except AUDIO_BIT_WIDTH=16',
        limitations='Serializer black-boxed; equivalent combined async reset; '
                    'existing mode init removed for FF legalization; '
                    'no place/route or board timing validation')
    (out/'results.json').write_text(json.dumps(metadata, indent=2) + '\n')


if __name__ == '__main__':
    main()
