"""Register the independent capacity oracle without changing legacy fixtures."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
for name in ['split_text', 'split_text_sdram']:
    path = root / f'sim/modelsim_{name}.json'
    value = json.loads(path.read_text(encoding='utf-8-sig'))
    for file in ['sim/split14_gold.mem', 'sim/split14_widths.mem']:
        if file not in value['data_files']:
            value['data_files'].append(file)
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    path = root / f'tb/expected_{name}.json'
    value = json.loads(path.read_text(encoding='utf-8-sig'))
    if 'CAP-14-stationary-15-marquee' not in value:
        value.append('CAP-14-stationary-15-marquee')
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
