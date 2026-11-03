"""Re-run affected round-one checks with their recorded configurations."""
from pathlib import Path
import json
import os
import subprocess
import sys
import argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--tag', default='transitions_r7')
args = parser.parse_args()
assert args.tag.replace('_', '').isalnum()
checks = [
    ('transitions_r4_final_visual_osd', 'visual_osd'),
    ('transitions_r4_osd_equivalence', 'osd_equivalence'),
    ('transitions_r4_color_luma_equivalence_fix1', 'color_luma_equivalence'),
    ('transitions_r4_final_color_envelope', 'color_envelope'),
    ('transitions_r4_split_core', 'split_core'),
    ('transitions_r4_circular_board', 'circular_board'),
]
for old, name in checks:
    prior = json.loads((ROOT / 'sim' / (old+'_sim_result.json')).read_text())
    files = [Path(p) for p in prior['input_hashes']]
    configs = [p for p in files if p.parent.name == 'sim' and p.name.startswith('modelsim')
               and p.suffix == '.json']
    expected = [p for p in files if p.name.startswith('expected') and p.suffix == '.json']
    assert len(configs) == 1, configs
    env = os.environ.copy()
    env.update(MODELSIM_CONFIG=str(configs[0]), SIM_OUTPUT=args.tag+'_'+name,
               RUN_SIM='0' if prior['status']=='COMPILE_PASS' else '1',
               ENABLE_VCD='0', TIMEOUT_SECONDS='1200')
    env.pop('MODELSIM_PROFILE', None)
    if env['RUN_SIM'] == '1':
        assert len(expected) == 1, expected
        env['EXPECTED_SCENARIOS'] = str(expected[0])
    print('RUN', name, flush=True)
    subprocess.run([sys.executable, '-B', 'sim/run.py'], cwd=ROOT, env=env, check=True)
