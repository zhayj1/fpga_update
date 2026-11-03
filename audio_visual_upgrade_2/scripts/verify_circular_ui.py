"""Run one isolated circular-layout check, preserving prior evidence."""
from pathlib import Path
import os,sys,json,argparse,subprocess
ROOT=Path(__file__).resolve().parents[1]
CHECKS=('spectrum','text','text_sdram','core','board','legacy_core','system')
def main():
    p=argparse.ArgumentParser();p.add_argument('check',choices=CHECKS);p.add_argument('--suffix',required=True)
    a=p.parse_args();prefix=f'circular_{a.check}_{a.suffix}'
    if list((ROOT/'sim').glob(prefix+'_*')):p.error('Existing evidence; choose a new suffix')
    env=os.environ.copy();env.update(SIMULATOR='modelsim',MODELSIM_CONFIG=f'sim/modelsim_circular_{a.check}.json',
        SIM_OUTPUT=prefix,ENABLE_VCD='0',TIMEOUT_SECONDS='600',RUN_SIM='0' if a.check=='board' else '1',
        ICCODER_VSIM=r'D:\modeltech64_10.6e\win64\vsim.exe')
    if a.check!='board':
        expected={'legacy_core':'visual_core','system':'integration'}.get(a.check,'circular_'+a.check)
        env['EXPECTED_SCENARIOS']=f'tb/expected_{expected}.json'
    else:env.pop('EXPECTED_SCENARIOS',None)
    return subprocess.call([sys.executable,'sim/run.py'],cwd=ROOT,env=env)
if __name__=='__main__':raise SystemExit(main())
