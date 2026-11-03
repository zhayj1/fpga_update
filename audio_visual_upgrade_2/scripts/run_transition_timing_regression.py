"""Re-run checks consuming the optimized AA layer, preserving earlier evidence."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--tag', default='transitions_r8')
parser.add_argument('--group', choices=('core', 'system', 'text'), required=True)
args = parser.parse_args()
assert args.tag.replace('_', '').isalnum()
checks = {
    'core': [('color_luma_equivalence', 'transitions_r7_color_luma_equivalence'),
             ('color_envelope', 'transitions_r7_color_envelope'),
             ('split_core', 'transitions_r7_split_core'),
             ('circular_board', 'transitions_r7_circular_board')],
    'system': [('circular_system', 'transitions_r7_circular_system')],
    'text': [('typography_layer', None), ('circular_text_sdram', None), ('split_text_sdram', None)],
}[args.group]
for name, prior_prefix in checks:
    env = os.environ.copy()
    env.pop('MODELSIM_PROFILE', None)
    env.update(SIM_OUTPUT=args.tag+'_'+name, RUN_SIM='1', ENABLE_VCD='0', TIMEOUT_SECONDS='1200')
    if prior_prefix:
        prior = json.loads((ROOT / 'sim' / (prior_prefix+'_sim_result.json')).read_text())
        files = [Path(p) for p in prior['input_hashes']]
        configs = [p for p in files if p.name.startswith('modelsim') and p.suffix == '.json']
        expected = [p for p in files if p.name.startswith('expected') and p.suffix == '.json']
        assert len(configs) == 1
        env['MODELSIM_CONFIG'] = str(configs[0])
        if prior['status'] == 'COMPILE_PASS':
            env['RUN_SIM'] = '0'
            env.pop('EXPECTED_SCENARIOS', None)
        else:
            assert len(expected) == 1
            env['EXPECTED_SCENARIOS'] = str(expected[0])
    else:
        env['MODELSIM_CONFIG'] = 'sim/modelsim_'+name+'.json'
        env['EXPECTED_SCENARIOS'] = 'tb/expected_'+name+'.json'
    print('RUN', name, flush=True)
    subprocess.run([sys.executable, '-B', 'sim/run.py'], cwd=ROOT, env=env, check=True)
