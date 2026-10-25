"""Shared real TG68K/RTG simulation with behavioral ROM and RAM."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BENCH = ROOT / 'bench/rtg_hdmi'


def run(*args, **kwargs):
    subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def build_cpu(folder):
    """Translate the current VHDL CPU wrapper/kernel, not a cached snapshot."""
    run('ghdl', '-a', '--std=08', '-fsynopsys', f'--workdir={folder}',
        'fpga/icepi-zero/board_config.vhd',
        'rtl/tg68k/TG68K_Pack.vhd', 'rtl/tg68k/TG68K_ALU.vhd',
        'rtl/tg68k/TG68KdotC_Kernel.vhd', 'rtl/soc/TG68K.vhd')
    cpu = folder / 'cpu.v'
    with cpu.open('w') as output:
        run('ghdl', '--synth', '--std=08', '-fsynopsys',
            f'--workdir={folder}', '--latches', '--out=verilog',
            '-ghavertg=1', '-ghavec2p=1', '-ghavecart=0',
            '-ghaveaudio=0', '-ghaveamigahost=0', 'TG68K', stdout=output)
    return cpu


def assemble_rom(asm, folder, vasm, extra_args=()):
    binary = folder / 'rom.bin'
    run(vasm, str(asm), '-o', str(binary), '-quiet',
        '-m68020', '-Fbin', '-no-opt', *extra_args)
    return binary


def run_rom(binary, folder, cpu, *, driver=False, cached=False, legacy_write_combine=False,
            overclock=False, data_cache=True, akiko=False):
    data = binary.read_bytes()
    if len(data) > 8192:
        raise RuntimeError('test ROM exceeds behavioral memory')
    data = data.ljust(8192, b'\0')
    image = folder / 'rom.hex'
    image.write_text(''.join(
        f'{int.from_bytes(data[i:i+2], "big"):04x}\n'
        for i in range(0, len(data), 2)))
    top = 'rtg_cpu_mmio_tb'
    parameters = {
        'CHECK_MMIO': int(not driver and not akiko),
        'CHECK_AKIKO': int(akiko),
        'CACHE_RAM': int(cached),
        'DATA_CACHE': int(data_cache),
        'LEGACY_WRITE_COMBINE': int(legacy_write_combine),
        'OVERCLOCK': int(overclock),
        'VERBOSE': 0,
        'TIMEOUT_NS': 20000000 if driver else 2000000,
    }
    run('iverilog', '-g2012', '-s', top, '-o', str(folder / 'test'),
        *(f'-P{top}.{key}={value}' for key, value in parameters.items()),
        '-DSOC_SIM', str(BENCH / 'rtg_cpu_mmio_tb.v'),
        'rtl/sdram/cpu_cache_small.v', 'rtl/sdram/dpram_inf_256x32.v',
        'rtl/sdram/dpram_inf_be_1024x32.v',
        str(cpu), 'rtl/soc/akiko.v',
        'rtl/rtg/rtg_video.v', 'rtl/rtg/rtg_async_fifo.v')
    run('vvp', str(folder / 'test'), f'+image={image}')
