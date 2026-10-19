#!/usr/bin/env python3
"""Run RTG/HDMI regressions from any working directory."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
RTG = ['rtl/rtg/rtg_video.v', 'rtl/rtg/rtg_async_fifo.v']
SDRAM = ['rtl/sdram/sdram_ctrl.v', 'rtl/sdram/cpu_cache_new.v',
         'rtl/sdram/dpram_inf_256x32.v', 'rtl/sdram/dpram_inf_be_1024x32.v',
         'rtl/sdram/dpram_inf_generic.v']
HDMI = [str(p.relative_to(ROOT)) for p in (ROOT / 'rtl/hdmi').glob('*.sv')
        if p.name not in ('serializer.sv', 'tmds_channel.sv')]
HDMI += ['bench/rtg_hdmi/tmds_stubs.v']
TESTS = {
    'fifo': ('rtg_fifo_reset_tb', ['rtl/rtg/rtg_async_fifo.v']),
    'registers': ('rtg_register_tb', RTG),
    'vblank': ('rtg_vblank_tb', RTG + ['rtl/minimig/paula_intcontroller.v']),
    'osd': ('rtg_osd_tb', ['rtl/rtg/rtg_osd.v']),
    'audio': ('audio_cdc_tb', ['rtl/hdmi/audio_cdc.v']),
    'audio_counter': ('hdmi_audio_counter_tb', HDMI),
    # Explicit reference experiment; production uses the register-based picker.
    'audio_queue': ('hdmi_audio_queue_tb', [
        'rtl/hdmi/packet_picker.sv.bak' if p == 'rtl/hdmi/packet_picker.sv' else p
        for p in HDMI]),
    'audio_stream': ('hdmi_audio_stream_tb', HDMI),
    'avi_checksum': ('avi_checksum_tb', ['rtl/hdmi/auxiliary_video_information_info_frame.sv']),
    'reset': ('hdmi_reset_tb', HDMI),
    'config': ('hdmi_config_tb', HDMI + ['bench/rtg_hdmi/hdmi_reset_tb.sv']),
    'top_config': ('rtg_top_config_tb', RTG + ['rtl/soc/minimig_virtual_top.v',
                                            'rtl/rtg/rtg_osd.v']),
    'video': ('rtg_video_tb', RTG),
    'contention': ('rtg_sdram_contention_tb', RTG + SDRAM),
    'addresses': ('rtg_sdram_address_tb', RTG + SDRAM),
    'integrated': ('hdmi_rtg_tb', RTG + SDRAM + HDMI),
    'repeat': ('rtg_repeat_tb', RTG),
    'repeat720': ('rtg_repeat_tb', RTG),
    'viewport': ('rtg_viewport_tb', RTG),
    'priority': ('rtg_priority_stress_tb', RTG),
    'serializer': ('serializer_lattice_tb', ['rtl/hdmi/serializer.sv']),
    'clocks': ('video_clock_control_tb', ['rtl/hdmi/video_clock_control.v']),
}
QUICK = ('fifo', 'registers', 'vblank', 'audio', 'audio_counter', 'avi_checksum', 'osd', 'reset', 'config', 'top_config', 'video')
LONG = ('config', 'reset', 'video', 'repeat', 'repeat720', 'viewport', 'priority', 'contention', 'addresses', 'integrated', 'audio_stream')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tests', nargs='*', choices=tuple(TESTS))
    parser.add_argument('--sim', choices=('auto', 'iverilog', 'verilator'), default='auto',
                        help='auto uses Verilator for full-frame and SDRAM tests')
    parser.add_argument('--lattice-models', type=Path,
                        default=os.environ.get('LATTICE_MODELS'),
                        help='Diamond cae_library/simulation/verilog/ecp5u directory')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rtg-hdmi-tests-') as folder:
        for name in args.tests or QUICK:
            if name == 'audio_queue' and not (ROOT/'rtl/hdmi/packet_picker.sv.bak').exists():
                parser.error('audio_queue tests the LUTRAM reference and requires rtl/hdmi/packet_picker.sv.bak')
            top, sources = TESTS[name]
            source = next(HERE.glob(top + '.*'))
            simulator = args.sim
            if simulator == 'auto':
                simulator = 'verilator' if name in LONG else 'iverilog'
            print(name + ':', flush=True)
            if simulator == 'verilator':
                if name in ('serializer', 'clocks'):
                    parser.error('Lattice model tests require --sim iverilog')
                build = Path(folder) / name
                command = ['verilator', '--binary', '--timing', '-Wno-fatal', '-DSOC_SIM',
                           '--output-split', '0', '--output-split-cfuncs', '0',
                           '--top-module', top, '--Mdir', str(build), str(source), *sources]
                if name == 'repeat720':
                    command += ['-GW=1280', '-GHT=1650']
                env = dict(os.environ, CCACHE_DISABLE='1')
                with (Path(folder) / (name + '.log')).open('w+') as log:
                    result = subprocess.run(command, cwd=ROOT, env=env,
                                            stdout=log, stderr=subprocess.STDOUT)
                    if result.returncode:
                        log.seek(0)
                        print(log.read())
                        result.check_returncode()
                subprocess.run([str(build / ('V' + top))], cwd=ROOT, check=True)
                continue
            command = ['iverilog', '-g2012', '-DSOC_SIM', '-s', top,
                       '-o', str(Path(folder) / name)]
            if name == 'repeat720':
                command += ['-P' + top + '.W=1280', '-P' + top + '.HT=1650']
            if name == 'top_config':
                command += ['-i', '-I', 'fpga/icepi-zero', '-I', 'rtl/soc']
            if name in ('serializer', 'clocks'):
                if args.lattice_models is None:
                    parser.error(name + ' requires --lattice-models or LATTICE_MODELS')
                model = 'ODDRX1F.v' if name == 'serializer' else 'DCSC.v'
                command += ['-DLATTICE', str(args.lattice_models / model)]
                if name == 'serializer':
                    command += ['-s', 'GSR_INST', '-s', 'PUR_INST']
            command += [str(source), *sources]
            subprocess.run(command, cwd=ROOT, check=True)
            subprocess.run(['vvp', str(Path(folder) / name)], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
