from pathlib import Path
import subprocess,concurrent.futures,json,collections
src=Path('rtl/rtg/rtg_video.v').read_text()
variants={}
variants['narrow_counters']=src.replace('reg [ 3:0] reset_count;', 'reg [ 2:0] reset_count;').replace('reg [15:0] prepare_count;', 'reg [$clog2(PREPARE_DELAY+1)-1:0] prepare_count;').replace('reg [10:0] scan_column;', 'reg [$clog2(H_ACTIVE)-1:0] scan_column;')
variants['row_priority']=src.replace('remaining_top > 4 && row_left_top > 4','row_left_top > 4').replace('remaining_bottom > 4 && row_left_bottom > 4','row_left_bottom > 4')
variants['constant_prefill']=src.replace('initial_top_bursts < prefill_limit ? initial_top_bursts : prefill_limit', 'prefill_limit').replace('initial_bottom_bursts < prefill_limit ? initial_bottom_bursts : prefill_limit', 'prefill_limit')
row=variants['constant_prefill'].replace('$clog2(H_ACTIVE * V_ACTIVE / 8 + 1)', '$clog2(V_ACTIVE + 1)')
row=row.replace('remaining_top > 4 && row_left_top > 4','row_left_top > 4').replace('remaining_bottom > 4 && row_left_bottom > 4','row_left_bottom > 4')
row=row.replace('remaining_top <= initial_top_bursts;', 'remaining_top <= split_valid ? split_line : V_ACTIVE;')
row=row.replace('remaining_bottom <= initial_bottom_bursts;', 'remaining_bottom <= split_valid ? V_ACTIVE-split_line : 0;')
row=row.replace('if (remaining_top != 0) remaining_top <= next_remaining;', 'if (row_left_top == 1 && remaining_top != 0) remaining_top <= next_remaining;')
row=row.replace('if (remaining_bottom != 0) remaining_bottom <= next_remaining;', 'if (row_left_bottom == 1 && remaining_bottom != 0) remaining_bottom <= next_remaining;')
variants['remaining_rows']=row
# Derived limits avoid wide stored thresholds; compare before selecting banks.
lim=src.replace('reg [9:0] fetch_limit;','wire [9:0] fetch_limit = pixel_repeat[1:0] == 1 ? 240 : pixel_repeat[1:0] == 2 ? 160 : 480;').replace('reg [8:0] priority_limit;','wire [8:0] priority_limit = pixel_repeat[1:0] == 1 ? 128 : pixel_repeat[1:0] == 2 ? 88 : 256;')
import re
lim=re.sub(r'^\s*(?:fetch_limit|priority_limit) <= \d+;\n','\n',lim,flags=re.M)
variants['derived_limits']=lim
# Diagnostic counter is not used by the current .card or rtgcheck.
diag=src.replace('      11\'h110: reg_q <= frame_sequence;', "      11'h110: reg_q <= 16'd0;")
variants['no_frame_sequence']=diag
out=Path('/tmp/rtg-optimization-assessment');out.mkdir(exist_ok=True)
def synth(item):
 name,source=item
 path=out/(name+'.v');path.write_text(source)
 with (out/(name+'.log')).open('w') as log:
  subprocess.run(['yosys','-Q','-T','-p',f'read_verilog {path} rtl/rtg/rtg_async_fifo.v; synth_ecp5 -top rtg_video; write_json {out}/{name}.json'],stdout=log,stderr=subprocess.STDOUT,check=True)
 return name
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
 for name in pool.map(synth,variants.items()): print(name,'synthesized',flush=True)
for name,path in [('baseline',Path('/tmp/rtg_current_optimization.json'))]+[(n,out/(n+'.json')) for n in variants]:
 cells=json.loads(path.read_text())['modules']['rtg_video']['cells']
 counts=collections.Counter(c['type'] for c in cells.values())
 print(name,dict(sorted(counts.items())),flush=True)
