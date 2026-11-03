"""Select the measured timing candidate and recover its exact saved sources."""
import hashlib
import json
from pathlib import Path
import shutil

from report_downscale_implementation import physical, verify_build

root = Path(__file__).resolve().parents[1]
out = root / 'output/timing_cleanup_20261030'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    candidates = {}
    for attempt in range(1, 5):
        tag = f'timingclean_r{attempt}_congestion_seed3_phy'
        # physical() consumes final_timing and route.qor, never intermediate log estimates.
        result = json.loads((root / 'prj/td_build' / tag / 'build_result.json').read_text(encoding='utf-8-sig'))
        assert result['status'] == 'BUILD_COMPLETE'
        r = physical(tag)
        ordinary = [g for n, g in r['groups'].items() if 'sdr_clk_sft' not in n]
        candidates[attempt] = dict(result=r, tag=tag,
            ordinary_endpoints=sum(g['setup_violations'] for g in ordinary),
            ordinary_wns=min(g['setup_ns'] for g in ordinary))
    # Fewer violating ordinary endpoints first, then worst ordinary slack,
    # then global TNS and physical Slice use. Hold violations take precedence.
    def rank(attempt):
        c = candidates[attempt]
        r = c['result']
        return (r['hold_violations'], c['ordinary_endpoints'], -c['ordinary_wns'],
                -r['setup_tns_ns'], r['resources']['slices'])
    selected = min(candidates, key=rank)
    manifest = json.loads((root / f'prj/td_build/timingclean_r{selected}_syn/inputs.json').read_text(encoding='utf-8-sig'))
    restores = []
    for record in manifest['sources']:
        p = Path(record['path'])
        if sha(p) == record['sha256'].lower():
            continue
        relative = p.relative_to(root)
        matches = [b / relative for b in out.glob('source_before_r*')
                   if (b / relative).is_file() and sha(b / relative) == record['sha256'].lower()]
        assert matches, f'No exact preserved source for {relative}'
        restores.append((p, matches[0]))
    if restores:
        saved = out / 'source_before_final_selection'
        saved.mkdir()
        for p, _ in restores:
            target = saved / p.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)
        for p, source in restores:
            shutil.copy2(source, p)
    verify_build(f'timingclean_r{selected}_syn')
    verify_build(candidates[selected]['tag'])
    record = dict(selected_attempt=selected, candidates=candidates,
        restored_sources=[p.relative_to(root).as_posix() for p, _ in restores],
        reason='Prioritize hold count, ordinary endpoint count, ordinary WNS, global TNS, then Slice.')
    (out / 'selection.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(record, indent=2))


if __name__ == '__main__':
    main()
