#!/usr/bin/env python3
"""Check production cfide timing using the current firmware divider values."""
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BUILD = Path(os.environ.get('BUILD_DIR', '/tmp/minimig-sd-tests')).resolve()
GHDL = os.environ.get('GHDL', 'ghdl')


def run(*args):
    subprocess.run([GHDL, *map(str, args)], cwd=BUILD, check=True)


def main():
    header = (ROOT / 'fw/ctrl_832/hardware.h').read_text()
    slow = int(re.search(r'#define SPI_SLOW_DIVIDER\s+(0x[0-9a-fA-F]+)', header)[1], 0)
    fast = int(re.search(r'#define SPI_fast\(\).*?=\s*(0x[0-9a-fA-F]+)', header)[1], 0)
    BUILD.mkdir(parents=True, exist_ok=True)
    run('-a', '--std=08', HERE / 'fifo_stub.vhd', ROOT / 'rtl/host/cfide.vhd', HERE / 'spi_timing_tb.vhd')
    run('-e', '--std=08', 'spi_timing_tb')
    headers = [("runtime", slow, fast), ("bootstrap", *[
        int(re.search(r'#define SPI_' + mode + r'\(\).*?=\s*(0x[0-9a-fA-F]+)',
                      (ROOT / 'fw/ctrl_boot_832/spi.h').read_text())[1], 0)
        for mode in ('slow', 'fast')])]
    for name, slow, fast in headers:
        binary = BUILD / f'{name}_trace'
        cc = [os.environ.get('CC', 'cc'), '-std=c99', '-O1', '-Wno-format',
              '-I' + str(ROOT / 'fw/ctrl_832'), '-I' + str(ROOT / 'EightThirtyTwo/lib832'),
              f'-DTRACE_SLOW_DIVIDER={slow}', f'-DTRACE_FAST_DIVIDER={fast}']
        if name == 'bootstrap':
            cc.append('-DBOOT_TRACE')
        subprocess.run([*cc, str(HERE / 'fw_trace.c'), '-o', str(binary)], check=True)
        trace = BUILD / f'{name}.txt'
        with trace.open('w') as output:
            subprocess.run([str(binary)], stdout=output, check=True)
        for rtc in (0, 1):
            for enabled in (0, 1):
                print(f"Checking {name} firmware, sd_free_running={enabled}, havespirtc={rtc}", flush=True)
                run('-r', '--std=08', 'spi_timing_tb', f'-gslow_divider={slow}',
                    f'-gfast_divider={fast}', f'-gfree_running={enabled}',
                    f'-grtc_enabled={rtc}', f'-gtrace_path={trace}', '--assert-level=error')



if __name__ == '__main__':
    main()
