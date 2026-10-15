from pathlib import Path
import subprocess, sys, json
root=Path('/home/mnalewajski/dev/icepi-zero-minimig')
work=Path('/tmp/cpu-cache-review')
old=(root/'rtl/sdram/cpu_cache_new.v').read_text().replace('module cpu_cache_new ', 'module cpu_cache_reference ', 1)
new=(root/'cpu_cache_new.v').read_text()
(work/'reference.v').write_text('`timescale 1ns/1ps\n'+old)
(work/'candidate.v').write_text('`timescale 1ns/1ps\n'+new)
# Separate the line memories to measure their mapping without unrelated cache logic.
start=new.index('// cache line cache - instruction')
end=new.index('reg  [addr_max_bits-1:4] cpu_cacheline_i_adr;')
mem=new[start:end]
ports='module line_ram(input clk, input [2:0] cpu_adr_blk, input [1:0] waddr, input [31:0] din, input [3:0] we, output [15:0] dout);\n'
mini=ports+mem+'\nalways @* begin cpu_cacheline_i_waddr=waddr; cpu_cacheline_i_din=din; cpu_cacheline_i_we=we; end\nassign dout=cpu_cacheline_i_cpu_out;\nendmodule\n'
(work/'line_ram.v').write_text(mini)
(work/'line_ram_forced.v').write_text(mini.replace('reg   [32-1:0] cpu_cacheline_i', '(* ram_style="distributed", syn_ramstyle="distributed" *) reg   [32-1:0] cpu_cacheline_i'))
for variant in ('line_ram','line_ram_forced'):
    log=work/(variant+'.log')
    with log.open('w') as f:
        subprocess.run(['yosys','-Q','-T','-p',f'read_verilog {work}/{variant}.v; synth_ecp5 -top line_ram; write_json {work}/{variant}.json; stat'],stdout=f,stderr=subprocess.STDOUT,check=True)
    data=json.loads((work/(variant+'.json')).read_text())
    counts={}
    for cell in data['modules']['line_ram']['cells'].values(): counts[cell['type']]=counts.get(cell['type'],0)+1
    print(variant,counts)
