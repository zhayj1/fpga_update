from pathlib import Path
import os,sys,json,argparse,subprocess
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('checks',nargs='+',choices=['pick','text','text_sdram','core','spectrum','board','system','legacy_text','legacy_pick']);p.add_argument('--suffix',required=True);a=p.parse_args()
for check in a.checks:
 prefix='split_'+check+'_'+a.suffix
 if list((root/'sim').glob(prefix+'_*')):raise SystemExit('Preserve existing evidence: '+prefix)
 config={'board':'circular_board','system':'circular_system','legacy_text':'layout_five','legacy_pick':'layout_five_pick'}.get(check,'split_'+check)
 expected={'system':'integration','legacy_text':'layout_five','legacy_pick':'layout_five_pick'}.get(check,'split_'+check)
 env=os.environ.copy();env.update(SIMULATOR='modelsim',MODELSIM_CONFIG='sim/modelsim_'+config+'.json',SIM_OUTPUT=prefix,ENABLE_VCD='0',TIMEOUT_SECONDS='1200',RUN_SIM='0' if check=='board' else '1',ICCODER_VSIM=r'D:\modeltech64_10.6e\win64\vsim.exe')
 if check!='board':env['EXPECTED_SCENARIOS']='tb/expected_'+expected+'.json'
 else:env.pop('EXPECTED_SCENARIOS',None)
 result=subprocess.call([sys.executable,'-B','sim/run.py'],cwd=root,env=env)
 if result:raise SystemExit(result)
 print('Completed '+prefix,flush=True)
