from pathlib import Path
import os,sys,json,argparse,subprocess
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('check',choices=['spectrum','core','board','startup','system','text_sdram','legacy_core']);p.add_argument('--suffix',required=True);a=p.parse_args()
prefix='capsule_'+a.check+'_'+a.suffix
if list((root/'sim').glob(prefix+'_*')):raise SystemExit('Preserve existing evidence')
family='capsule' if a.check in ['spectrum','core','startup'] else 'circular'
expected={'system':'integration','legacy_core':'visual_core'}.get(a.check,family+'_'+a.check)
env=os.environ.copy();env.update(SIMULATOR='modelsim',MODELSIM_CONFIG=f'sim/modelsim_{family}_{a.check}.json',SIM_OUTPUT=prefix,ENABLE_VCD='0',TIMEOUT_SECONDS='1200',RUN_SIM='0' if a.check=='board' else '1',ICCODER_VSIM=r'D:\modeltech64_10.6e\win64\vsim.exe')
if a.check!='board':env['EXPECTED_SCENARIOS']='tb/expected_'+expected+'.json'
else:env.pop('EXPECTED_SCENARIOS',None)
raise SystemExit(subprocess.call([sys.executable,'sim/run.py'],cwd=root,env=env))
