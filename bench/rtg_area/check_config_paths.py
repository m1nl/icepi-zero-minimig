#!/usr/bin/env python3
"""Check that the config_sys_* false-path prefix cannot hide clk_sys DMA paths."""
from collections import defaultdict, deque
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    with tempfile.TemporaryDirectory(prefix='rtg-config-paths-') as work:
        output = Path(work) / 'logical.json'
        script = ('read_verilog rtl/rtg/rtg_video.v rtl/rtg/rtg_async_fifo.v; '
                  'hierarchy -top rtg_video; proc; flatten; opt; memory_collect; '
                  f'write_json "{output}"')
        with (Path(work) / 'yosys.log').open('w+') as log:
            result = subprocess.run(['yosys', '-Q', '-T', '-p', script], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                log.seek(0)
                raise RuntimeError(log.read())
        module = json.loads(output.read_text())['modules']['rtg_video']
    cells = module['cells']
    clk_rtg = module['ports']['clk_rtg']['bits']
    sinks = defaultdict(list)
    for name, cell in cells.items():
        for port, direction in cell['port_directions'].items():
            if direction == 'input':
                for bit in cell['connections'][port]:
                    if isinstance(bit, int):
                        sinks[bit].append(name)
    sources = {bit for name, net in module['netnames'].items()
               if name.startswith('config_sys_') for bit in net['bits']
               if isinstance(bit, int)}
    if not sources:
        raise RuntimeError('config_sys_* matches no configuration nets')
    queue = deque(sources)
    visited = set(sources)
    endpoints = set()
    while queue:
        for name in sinks[queue.popleft()]:
            cell = cells[name]
            if 'dff' in cell['type'].lower() or cell['type'].startswith('$mem'):
                endpoints.add(name)
                continue
            for port, direction in cell['port_directions'].items():
                if direction == 'output':
                    for bit in cell['connections'][port]:
                        if isinstance(bit, int) and bit not in visited:
                            visited.add(bit)
                            queue.append(bit)
    registers = [cells[name] for name in endpoints if 'dff' in cells[name]['type'].lower()]
    if not registers or any(cell['connections']['CLK'] != clk_rtg for cell in registers):
        raise RuntimeError('Configuration prefix reaches a register outside clk_rtg')
    for name in endpoints:
        cell = cells[name]
        if cell['type'].startswith('$mem'):
            for port, bits in cell['connections'].items():
                if port.startswith('WR_') and any(bit in visited for bit in bits):
                    raise RuntimeError('Configuration prefix reaches a RAM write port: ' + name)
    print(f'PASS: config_sys_* reaches {len(registers)} clk_rtg register groups; '
          'no clk_sys register or RAM-write endpoints')


if __name__ == '__main__':
    main()
