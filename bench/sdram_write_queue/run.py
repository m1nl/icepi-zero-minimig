#!/usr/bin/env python3
"""Queue, 114 MHz command timing, and production-cache readback regressions."""
from pathlib import Path
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
RTL = ROOT / 'rtl/sdram'

with tempfile.TemporaryDirectory(prefix='sdram-write-queue-') as folder:
    def run(top, sources, **parameters):
        executable = Path(folder) / top
        subprocess.run(['iverilog', '-g2012', '-DSOC_SIM', '-s', top,
                        '-o', str(executable),
                        *[f'-P{top}.{key}={value}' for key, value in parameters.items()],
                        str(HERE / f'{top}.v'), *map(str, sources)], check=True)
        subprocess.run(['vvp', str(executable)], check=True)

    run('sdram_write_queue_tb', [RTL / 'sdram_write_queue.v'])
    controller = [RTL / 'sdram_ctrl.v', RTL / 'sdram_write_queue.v']
    for parameters in ({'QUEUED': 0}, {'QUEUED': 1}, {'QUEUED': 1, 'FAST': 1},
                       {'QUEUED': 1, 'SHORTCUT': 1}):
        run('sdram_queued_ctrl_tb', [*controller, HERE / 'cache_source_stub.v'], **parameters)
    for enabled in (0, 1):
        run('sdram_readback_tb', [*controller, RTL / 'cpu_cache_small.v',
                                RTL / 'dpram_inf_256x32.v', RTL / 'dpram_inf_be_1024x32.v'],
            QUEUED=enabled)
    for board in ('icepi-zero', 'icepi-zero-xl', 'fleaohm'):
        preprocessed = Path(folder) / f'{board}.v'
        subprocess.run(['iverilog', '-g2012', '-E', '-I', str(ROOT / 'fpga' / board),
                        '-I', str(ROOT / 'rtl/soc'), '-o', str(preprocessed),
                        str(ROOT / 'rtl/soc/minimig_virtual_top.v')], check=True)
        instance = re.search(r'sdram_ctrl\s*#\((.*?)\)\s*sdram\s*\(',
                             preprocessed.read_text(), re.S)
        assert instance is not None, f'{board}: controller instance missing'
        enabled = '.cpu_write_queue(1)' in instance[1]
        assert enabled == (board == 'icepi-zero-xl'), f'{board}: wrong queue setting'
    print('PASS: board preprocessing enables the queue only on IcePi Zero XL')
