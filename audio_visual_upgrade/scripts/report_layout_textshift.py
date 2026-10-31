"""Audit and package the 29px text-group translation without replacing old releases."""
from datetime import datetime
from pathlib import Path
import json
import shutil

import report_layout_textfix as audit
from report_downscale_implementation import physical, verify_build, warning_lines

ROOT = Path(__file__).resolve().parents[1]
SYN = 'textshift_r1_syn'
PHY = 'textshift_r1_congestion_seed3_phy'
OUT = ROOT / 'output/layout_textshift_20261030'


def main():
    audit.RUNS = {name: 'textshift_r1' for name in ('layout', 'layout_sdram', 'core', 'board')}
    tests = audit.audit_tests()
    assert all(t['input_hashes_current'] for t in tests.values()), 'Stale test inputs'
    syn_inputs, syn_result = verify_build(SYN)
    phy_inputs, phy_result = verify_build(PHY)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == SYN
    assert all(i['script_sha256'].lower() == audit.sha(ROOT / 'scripts/build.ps1')
               for i in (syn_inputs, phy_inputs))
    old = audit.read(ROOT / 'prj/td_build/textfix_r4_syn/inputs.json')
    old_hashes = {v['path']: v['sha256'].lower() for v in old['sources']}
    changed = sorted({Path(v['path']).relative_to(ROOT).as_posix()
                      for v in syn_inputs['sources']
                      if v['sha256'].lower() != old_hashes.get(v['path'])})
    assert changed == ['rtl/top/skeleton_core.v'], changed
    result = physical(PHY)
    limits = dict(slices=9800, lut=19600, registers=19600, bram9k=64,
                  bram32k=16, dsp=29, pll=4, gclk=16)
    assert all(result['resources'][k] <= v for k, v in limits.items())
    clean = result['setup_violations'] == result['hold_violations'] == 0
    OUT.mkdir(exist_ok=True)
    target = OUT / 'audio_visual_layout_textshift.bit'
    assert not target.exists(), 'Preserve previous package'
    shutil.copy2(phy_result['bitstream']['path'], target)
    assert audit.sha(target) == phy_result['bitstream']['sha256'].lower()
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        scope='Translate title, singer and lyrics down 29px; title top aligns with static cover y=45.',
        synthesis=SYN, physical=PHY, synthesis_result=syn_result,
        changed_build_sources=changed, tests=tests,
        simulation_scenario_count=sum(len(t['scenarios']) for t in tests.values()),
        all_test_inputs_current=True, all_build_inputs_current=True,
        current=result, baseline=physical('textfix_r4_congestion_seed3_phy'),
        bitstream=dict(path=str(target), bytes=target.stat().st_size, sha256=audit.sha(target)),
        timing_clean=clean, board_validation='not_run',
        validation_limits=['Targeted layer/core regressions; no full new-layout SD boot or post-route simulation.',
                           'Previous text-repair structural retry budget remains exhausted; this run changes coordinates only.'],
        warnings={tag: warning_lines(tag) for tag in (SYN, PHY)})
    audit.write(OUT / 'verification_and_build.json', evidence)
    r = result['resources']
    lines = ['# 文字整体下移29像素', '',
        '歌名上沿y=45，与中心(160,165)、240×240封面的静态上沿对齐。歌手y=77；五行歌词顶部118/150/182/214/246，裁剪118..269。间距、横坐标、字体和滚动参数保持。', '',
        f"本次{evidence['simulation_scenario_count']}个功能场景及板级编译展开通过，输入哈希与当前源码一致。",
        '快速模型17帧和真实SDRAM争用4帧逐像素比对，覆盖标题/歌手/歌词、纵移0/16/32px、横滚、句子迁移及迟到取消。核心检查实际实例坐标及混色/OSD/HDMI行尾。', '',
        f"Slice {r['slices']}/9800，LUT {r['lut']}/19600，FF {r['registers']}/19600；BRAM9K {r['bram9k']}/64、BRAM32K {r['bram32k']}/16，DSP {r['dsp']}/29。", '',
        '|路径组|setup/ns|setup违例|hold/ns|', '|---|---:|---:|---:|']
    for name, g in result['groups'].items():
        lines.append(f"|{name}|{g['setup_ns']:+.3f}|{g['setup_violations']}|{g['hold_ns']:+.3f}|")
    lines += ['', f"全局setup WNS {result['setup_wns_ns']:+.3f}ns，{result['setup_violations']}个违例；hold {result['hold_violations']}个违例。",
        'bit已生成，未上板；时序是否收敛以以上结果为准。此前文字花屏修复仍需实板验证。', '',
        f'- bit：{target.relative_to(ROOT).as_posix()}',
        f'- SHA256：{audit.sha(target)}',
        '- SD卡字库及素材无需更新。',
        f'- 综合/布局布线：prj/td_build/{SYN}、prj/td_build/{PHY}。',
        '- 本次仅一次综合和一次布局布线，无额外结构修复或种子重试。', '']
    report = ROOT / 'doc/compile/layout_textshift_report.md'
    report.write_text('\n'.join(lines), encoding='utf-8')
    state_path = ROOT / 'doc/workflow/state.json'
    state = audit.read(state_path)
    status = 'completed_implementation' if clean else 'completed_implementation_timing_unmet'
    state.update(status=status, board_validation='not_run_for_text_shift',
                 limitations=evidence['validation_limits'] + ([] if clean else ['Setup timing is not closed.']))
    state['layout_text_shift'].update(status=status,
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix(),
        bitstream=evidence['bitstream'], timing_clean=clean)
    audit.write(state_path, state)
    audit.write(ROOT / 'doc/workflow/quality_reports/layout_text_shift.json', dict(
        skill='fpga-workflow', status='passed' if clean else 'partial',
        files_written=['rtl/top/skeleton_core.v', 'tb/tb_layout_five.v', 'tb/tb_typography_core.v',
                       'doc/spec/layout_five_behavior_spec.md', str(report.relative_to(ROOT)),
                       str(target.relative_to(ROOT))], missing_files=[],
        verification_level='functional_simulation_and_routed_bitstream',
        timing_clean=clean, board_validated=False,
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix(),
        reason='Coordinate regressions and build passed; board validation pending; STA recorded.'))
    print(json.dumps(dict(bitstream=evidence['bitstream'], resources=r,
                         setup_violations=result['setup_violations'], timing_clean=clean), indent=2))


if __name__ == '__main__':
    main()
