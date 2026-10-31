"""Audit the expanded lyric spacing and package its routed candidate."""
from datetime import datetime
import json
from pathlib import Path
import re
import shutil

import report_layout_textfix as audit
from report_downscale_implementation import physical, verify_build, warning_lines

ROOT = Path(__file__).resolve().parents[1]
SYN = 'lyricspace_r1_syn'
PHY = 'lyricspace_r1_congestion_seed3_phy'
OUT = ROOT / 'output/lyric_spacing_20261030'


def main():
    audit.RUNS = {n: 'lyricspace_r1' for n in
                  ('layout', 'layout_sdram', 'layout_pick', 'core', 'board', 'layer')}
    tests = audit.audit_tests()
    assert all(t['input_hashes_current'] for t in tests.values())
    syn_inputs, syn_result = verify_build(SYN)
    phy_inputs, phy_result = verify_build(PHY)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == SYN
    assert all(i['script_sha256'].lower() == audit.sha(ROOT / 'scripts/build.ps1')
               for i in (syn_inputs, phy_inputs))
    old = audit.read(ROOT / 'prj/td_build/textshift_r1_syn/inputs.json')
    old_hashes = {v['path']: v['sha256'].lower() for v in old['sources']}
    changed = sorted({Path(v['path']).relative_to(ROOT).as_posix()
                      for v in syn_inputs['sources']
                      if v['sha256'].lower() != old_hashes.get(v['path'])})
    assert changed == ['rtl/gfx/layer_text_aa.v', 'rtl/top/skeleton_core.v'], changed
    current = physical(PHY)
    baseline = physical('textshift_r1_congestion_seed3_phy')
    timing_comparison = {
        name: dict(previous_setup_ns=baseline['groups'][name]['setup_ns'],
                   current_setup_ns=g['setup_ns'],
                   previous_setup_violations=baseline['groups'][name]['setup_violations'],
                   current_setup_violations=g['setup_violations'],
                   worst_start=g['worst_start'], worst_end=g['worst_end'])
        for name, g in current['groups'].items()}
    limits = dict(slices=9800, lut=19600, registers=19600, bram9k=64,
                  bram32k=16, dsp=29, pll=4, gclk=16)
    assert all(current['resources'][k] <= v for k, v in limits.items())
    console_raw = (ROOT / f'prj/td_build/{PHY}/console.log').read_bytes()
    console = console_raw.decode('utf-16' if console_raw.startswith((b'\xff\xfe', b'\xfe\xff'))
                                 else 'utf-8', errors='replace')
    packed = re.findall(r'(\d+) mslices, (\d+) lslices', console)
    mslice, lslice = map(int, packed[-1])
    assert max(mslice, lslice) <= 4900
    assert mslice + lslice == current['resources']['slices']
    current['slice_types'] = dict(mslice=mslice, lslice=lslice, each_limit=4900)
    clean = current['setup_violations'] == current['hold_violations'] == 0
    OUT.mkdir(exist_ok=True)
    target = OUT / 'audio_visual_lyric_spacing.bit'
    assert not target.exists(), 'Preserve existing package'
    shutil.copy2(phy_result['bitstream']['path'], target)
    assert audit.sha(target) == phy_result['bitstream']['sha256'].lower()
    limits_text = ['No board download, full new-layout SD boot or post-route simulation.',
                  'Previous text-repair structural retry budget is preserved.']
    if not clean:
        limits_text.append('Setup timing is not closed; see path groups.')
    if current['setup_violations'] > baseline['setup_violations']:
        limits_text.append('Timing regressed from the previous layout; this bitstream is a validation candidate.')
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        scope='Expand lyric gaps to 36/36/36/35px; first row y=118, fifth glyph bottom y=284.',
        synthesis=SYN, physical=PHY, synthesis_result=syn_result,
        changed_build_sources=changed, tests=tests,
        simulation_scenario_count=sum(len(t['scenarios']) for t in tests.values()),
        all_test_inputs_current=True, all_build_inputs_current=True,
        current=current, baseline=baseline, timing_comparison=timing_comparison,
        bitstream=dict(path=str(target), bytes=target.stat().st_size, sha256=audit.sha(target)),
        timing_clean=clean, board_validation='not_run', validation_limits=limits_text,
        warnings={tag: warning_lines(tag) for tag in (SYN, PHY)})
    audit.write(OUT / 'verification_and_build.json', evidence)
    r = current['resources']
    lines = ['# 歌词行距调整', '',
        '第一行顶部y=118保持，五行顶部118/154/190/226/261；字格高24px，间隔36/36/36/35px，第五行底部y=284与静态封面底部齐平。歌词裁剪范围118..284。歌名、歌手位置保持。',
        '滚动相位0..36：第五槽首相位停留1px，累计上移35px；其他槽上移36px。完整相位与切句后各槽严格衔接。使用比较、共用槽基址减法；无新增乘除法器、字库或帧缓存。', '',
        f"本次{evidence['simulation_scenario_count']}个功能场景与板级编译展开通过，全部输入哈希为当前源码。",
        '快速模型19帧逐像素比对，含相位0/1/18/35/36及切句、横滚、迟到/取消；真实SDRAM争用4帧；选句64行、相位生成、核心实际参数、混色/OSD/HDMI行尾及旧三行文字层回归通过。', '',
        f"Slice {r['slices']}/9800（MSlice {mslice}/4900、LSlice {lslice}/4900）；LUT {r['lut']}/19600，FF {r['registers']}/19600，BRAM9K {r['bram9k']}/64，BRAM32K {r['bram32k']}/16，DSP {r['dsp']}/29。", '',
        '|路径组|setup/ns|setup违例|hold/ns|', '|---|---:|---:|---:|']
    for name, g in current['groups'].items():
        lines.append(f"|{name}|{g['setup_ns']:+.3f}|{g['setup_violations']}|{g['hold_ns']:+.3f}|")
    lines += ['', f"全局setup WNS {current['setup_wns_ns']:+.3f}ns，{current['setup_violations']}个违例；hold {current['hold_violations']}个违例。",
        f"上一版setup {baseline['setup_violations']}个违例、WNS {baseline['setup_wns_ns']:+.3f}ns；本版增加{current['setup_violations']-baseline['setup_violations']}个违例，不能宣称时序通过或与上一版同等稳定。",
        '视频域最差仍是OSD normalize_product到rgb混色路径：上一版+2.094ns，本版-6.136ns；数据路径由37.763ns变45.993ns，其中布线由22.188ns变29.752ns。SDR最差是text_row_aa的code到symbol_ok_q（-5.826ns），跨域最差是ttl_fc到s_tv（-1.036ns）。这些报告的最差路径未经过本轮槽基址选择；两个RTL文件的变化也会改变整机映射与布局，不能由此证明所有新逻辑均满足时序。',
        '本轮完成行距功能和一次物理实现，未改OSD、取字、仲裁器及约束；未盲目更换布局种子，既有文字异常结构修复预算保持原记录。后续应按上述负裕量路径修复，当前候选不替代此前包。',
        'bit已生成，尚未上板；此前文字异常是否消失仍需实板验证。', '',
        f'- bit：{target.relative_to(ROOT).as_posix()}',
        f'- SHA256：{audit.sha(target)}', '- SD卡字库及素材无需更新。',
        f'- 综合/物理：prj/td_build/{SYN}、prj/td_build/{PHY}。', '']
    report = ROOT / 'doc/compile/lyric_spacing_report.md'
    report.write_text('\n'.join(lines), encoding='utf-8')
    state_path = ROOT / 'doc/workflow/state.json'
    state = audit.read(state_path)
    status = 'completed_implementation' if clean else 'completed_implementation_timing_unmet'
    state.update(status=status, limitations=limits_text)
    state['lyric_spacing'].update(status=status, timing_clean=clean,
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix(),
        bitstream=evidence['bitstream'], synthesis=SYN, physical=PHY,
        timing_regressed=current['setup_violations'] > baseline['setup_violations'],
        setup_violations=current['setup_violations'],
        setup_wns_ns=current['setup_wns_ns'], hold_violations=current['hold_violations'],
        board_validation='not_run',
        next_step='Candidate board validation; resolve reported OSD/glyph/descriptor negative-slack paths before timing acceptance.')
    audit.write(state_path, state)
    audit.write(ROOT / 'doc/workflow/quality_reports/lyric_spacing.json', dict(
        skill='fpga-workflow', status='completed' if clean else 'partial',
        files_written=changed + ['tb/tb_layout_five.v', 'tb/tb_layout_five_pick.v',
            'tb/tb_typography_core.v', 'doc/spec/layout_five_behavior_spec.md',
            str(report.relative_to(ROOT)), str(target.relative_to(ROOT))], missing_files=[],
        verification_level='functional_simulation_and_routed_bitstream',
        timing_clean=clean, board_validated=False,
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix(),
        reason='Spacing regressions and build passed; board validation pending; STA recorded.'))
    print(json.dumps(dict(bitstream=evidence['bitstream'], resources=r,
        setup_violations=current['setup_violations'], timing_clean=clean), indent=2))


if __name__ == '__main__':
    main()
