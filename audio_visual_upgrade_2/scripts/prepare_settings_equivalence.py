"""Build a cycle comparator against the immutable pre-optimization mailbox."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
reference = (ROOT / 'output/transitions_round2/visual_settings_r5.v').read_text()
(ROOT / 'output/transitions_round2/visual_settings_reference.v').write_text(
    reference.replace('module visual_settings #', 'module visual_settings_reference #'))
cfg = json.loads((ROOT / 'sim/modelsim_visual_controls.json').read_text())
cfg['dut_top'] = cfg['tb_top'] = 'work.tb_settings_equivalence'
cfg['libraries'][0]['sources'] = [s for s in cfg['libraries'][0]['sources']
    if s['path'] in ('rtl/gfx/visual_palette.v', 'rtl/gfx/visual_settings.v')
    or s['path'].startswith('sim/vendor/')]
cfg['libraries'][0]['sources'] += [dict(path=p, language='verilog') for p in (
    'output/transitions_round2/visual_settings_reference.v', 'tb/tb_settings_equivalence.v')]
(ROOT / 'sim/modelsim_settings_equivalence.json').write_text(json.dumps(cfg, indent=2)+'\n')
