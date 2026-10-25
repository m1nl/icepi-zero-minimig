#!/usr/bin/env python3
"""Run RTG bus and driver regressions on the real simulated TG68K/RTG core."""
import argparse
import os
from pathlib import Path
import sys
import tempfile

from sim_core import BENCH, assemble_rom, build_cpu, run, run_rom


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('all', '1024x768', '1280x720'), default='all')
    parser.add_argument('--mmio-only', action='store_true')
    parser.add_argument('--cpu-netlist', type=Path,
                        help='optionally reuse an existing GHDL-generated TG68K model')
    parser.add_argument('--vasm', default=os.environ.get(
        'VASM', str(Path(os.environ.get('VBCC', Path.home() / 'vbcc')) / 'bin/vasmm68k_mot')))
    for option in ('inc-asm', 'p96-private', 'p96-public'):
        parser.add_argument('--' + option, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rtg-driver-suite-') as name:
        folder = Path(name)
        cpu = args.cpu_netlist.resolve() if args.cpu_netlist else build_cpu(folder)
        print('Testing TG68K MMIO decode, longword writes and readback', flush=True)
        binary = assemble_rom(BENCH / 'rtg_cpu_mmio.asm', folder, args.vasm)
        run_rom(binary, folder, cpu)
        print('Testing TG68K paired SDRAM/cache transfers with narrow MMIO', flush=True)
        run_rom(binary, folder, cpu, cached=True)
        print('Testing optional legacy narrow-write combining', flush=True)
        run_rom(binary, folder, cpu, cached=True, legacy_write_combine=True)
        for legacy in (False, True):
            print('Testing TG68K overclock with legacy combining ' +
                  ('enabled' if legacy else 'disabled'), flush=True)
            run_rom(binary, folder, cpu, cached=True,
                    legacy_write_combine=legacy, overclock=True)
        for overclock in (False, True):
            for legacy in (False, True):
                print('Testing TG68K with D-cache disabled, overclock=' + str(overclock) +
                      ', legacy combining=' + str(legacy), flush=True)
                run_rom(binary, folder, cpu, cached=True, data_cache=False,
                        legacy_write_combine=legacy, overclock=overclock)
        if args.mmio_only:
            return
        for profile in ('1024x768', '1280x720'):
            if args.profile not in ('all', profile):
                continue
            print('Testing driver profile ' + profile, flush=True)
            command = [sys.executable, str(Path(__file__).with_name('test_driver_fallback.py')),
                       '--cpu-netlist', str(cpu), '--vasm', args.vasm]
            if profile == '1280x720':
                command.append('--rtg-720p')
            for option in ('inc_asm', 'p96_private', 'p96_public'):
                value = getattr(args, option)
                if value is not None:
                    command += ['--' + option.replace('_', '-'), str(value.resolve())]
            run(*command)
    print('PASS: RTG simulated-core test suite', flush=True)


if __name__ == '__main__':
    main()
