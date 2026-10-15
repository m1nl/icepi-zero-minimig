from pathlib import Path
import subprocess, sys, json, collections
root=Path('/home/mnalewajski/dev/icepi-zero-minimig')
work=Path(__file__).resolve().parent

def run(name,args,expected_failure=False):
    result=subprocess.run(args,cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (work/(name+'.log')).write_text(result.stdout)
    print(name+':',result.stdout.strip() if name.startswith('simulation') or name=='integration' else 'exit '+str(result.returncode))
    if bool(result.returncode) != expected_failure:
        raise SystemExit('Unexpected result in '+name+'; see '+str(work/(name+'.log')))

run('generate',['python3',str(work/'run.py')])
memories=[str(root/'rtl/sdram/dpram_inf_256x32.v'),str(root/'rtl/sdram/dpram_inf_be_1024x32.v')]
# The main scoreboard deliberately excludes combined long writes across line boundaries,
# matching sdram_ctrl.v's longword_en restriction. The boundary bench checks that case separately.
for name,tb in [('equivalence','tb.v'),('scoreboard','tb_scoreboard.v'),('boundary','tb_boundary.v')]:
    out=work/('sim_'+name)
    run('compile_'+name,['iverilog','-g2012','-DSOC_SIM','-s','tb','-o',str(out),str(work/tb),str(work/'reference.v'),str(work/'candidate.v'),*memories])
    run('simulation_'+name,['vvp',str(out)],expected_failure=name=='boundary')
# Check the proposed reset fix in a temporary copy, without editing the user's source.
s=(work/'candidate.v').read_text().replace('  case (cpu_sm_state)','  if (!rst) case (cpu_sm_state)',1)
(work/'candidate_reset_gated.v').write_text(s)
run('compile_reset_fix',['iverilog','-g2012','-DSOC_SIM','-s','tb','-o',str(work/'sim_reset_fix'),str(work/'tb_scoreboard.v'),str(work/'reference.v'),str(work/'candidate_reset_gated.v'),*memories])
run('simulation_reset_fix',['vvp',str(work/'sim_reset_fix')])
for name,source in [('original_full',root/'rtl/sdram/cpu_cache_new.v'),('full',root/'cpu_cache_new.v')]:
    run('synth_'+name,['yosys','-Q','-T','-p',f'read_verilog -lib rtl/sdram/dpram_256x32.v rtl/sdram/dpram_be_1024x32.v; read_verilog {source}; synth_ecp5 -top cpu_cache_new; write_json {work}/{name}.json; stat'])
    cells=json.loads((work/(name+'.json')).read_text())['modules']['cpu_cache_new']['cells']
    print(name,dict(collections.Counter(c['type'] for c in cells.values())))
run('integration',['iverilog','-g2012','-DSOC_SIM','-s','sdram_ctrl','-o',str(work/'controller'),str(work/'candidate.v'),str(root/'rtl/sdram/sdram_ctrl.v'),*memories,str(root/'rtl/sdram/dpram_inf_generic.v')])
run('lint',['verilator','--lint-only','--timing','-Wno-fatal','-DSOC_SIM','--top-module','cpu_cache_new',str(root/'cpu_cache_new.v'),*memories])
