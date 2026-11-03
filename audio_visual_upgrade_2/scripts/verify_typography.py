"""Run one typography check using the project's isolated ModelSim runner."""
from pathlib import Path
import argparse
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
CHECKS={
    'numeric':('osd_numeric','osd_numeric',180),
    'font_pixel':('font_pixel','font_pixel',180),
    'geometry':('geometry_equivalence','geometry_equivalence',300),
    'catalog':('catalog_matrix','catalog_matrix',300),
    'catalog_legacy':('catalog_legacy','catalog_legacy',180),
    'visual_osd':('visual_osd','visual_osd',300),
    'visual_core':('visual_core','visual_core',300),
    'visual':('visual_controls','visual_controls',300),
    'layout_sdram':('layout_sdram','layout_sdram',300),
    'layout':('layout_five','layout_five',300),
    'layout_pick':('layout_five_pick','layout_five_pick',180),
    'layout_rings':('layout_five_rings','layout_five_rings',180),
    'full_sdram':('full_font_sdram','full_font_sdram',300),
    'full_rows':('full_font_rows','full_font_rows',300),
    'full_load':('full_font_load','full_font_load',300),
    'bmp_writeback':('bmp_downscale_writeback','bmp_downscale_writeback',180),
    'font_legacy':('font_countshare','font_countshare',300),
    'blend':('typography_blend','typography_blend',180),
    'row':('typography_row','typography_row',180),
    'layer':('typography_layer','typography_layer',300),
    'osd':('typography_osd','typography_osd',180),
    'core':('typography_core','typography_core',180),
    'assets':('typography_assets','typography_assets',180),
    'controls':('osd_stage5','osd_stage5',180),
    'legacy_system':('downscale_integration','integration',600),
    'board':('board_compile',None,180),
}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('check',choices=CHECKS)
    parser.add_argument('--compile-only',action='store_true')
    parser.add_argument('--suffix',required=True,help='New evidence suffix; preserve previous logs')
    args=parser.parse_args()
    config,expected,timeout=CHECKS[args.check]
    prefix=f'typography_{args.check}_{args.suffix}'
    if any((ROOT/'sim').glob(prefix+'_*')):
        parser.error('Evidence prefix exists; choose a new suffix')
    env=os.environ.copy()
    env.update(SIMULATOR='modelsim',MODELSIM_CONFIG=f'sim/modelsim_{config}.json',
               SIM_OUTPUT=prefix,ENABLE_VCD='0',TIMEOUT_SECONDS=str(timeout),
               RUN_SIM='0' if args.compile_only or expected is None else '1')
    env.setdefault('ICCODER_VSIM',r'D:\modeltech64_10.6e\win64\vsim.exe')
    if expected: env['EXPECTED_SCENARIOS']=f'tb/expected_{expected}.json'
    else: env.pop('EXPECTED_SCENARIOS',None)
    return subprocess.call([sys.executable,'sim/run.py'],cwd=ROOT,env=env)


if __name__=='__main__': raise SystemExit(main())
