"""Audit the OSD placement change and package its single physical build."""
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil

from report_downscale_implementation import physical, verify_build, warning_lines

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/osd_bottom_right_20261030'
SYN = 'osdcorner_r1_syn'
PHY = 'osdcorner_r1_congestion_seed3_phy'
BASE = 'timingclean_r1_congestion_seed3_phy'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def main():
    bit = OUT / 'audio_visual_osd_bottom_right.bit'
    assert not bit.exists(), 'Preserve existing delivery'
    tests = {}
    for name, prefix, expected in [
        ('osd', 'osd_bottom_right_r1', 'PASS'),
        ('core', 'osd_bottom_right_core_r1', 'PASS'),
        ('board', 'osd_bottom_right_board_r1', 'COMPILE_PASS'),
    ]:
        path = ROOT / f'sim/{prefix}_sim_result.json'
        result = read(path)
        assert result['status'] == expected and result['compile_exit_code'] == 0, name
        assert result['input_hashes']
        for filename, digest in result['input_hashes'].items():
            assert sha(Path(filename)) == digest.lower(), filename
        scenarios = []
        if expected == 'PASS':
            assert result['sim_exit_code'] == 0
            log = (ROOT / result['sim_log']).read_text(errors='replace')
            scenarios = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
            assert sorted(scenarios) == sorted(result['expected_scenarios'])
            assert len(set(scenarios)) == len(scenarios) == 4
            assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log
        tests[name] = dict(status=expected, scenarios=scenarios, evidence=path.relative_to(ROOT).as_posix(),
                           all_inputs_current=True, warnings=result.get('warning_lines', []))

    syn_inputs, syn_result = verify_build(SYN)
    phy_inputs, phy_result = verify_build(PHY)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == SYN
    for inputs in (syn_inputs, phy_inputs):
        assert inputs['script_sha256'].lower() == sha(ROOT / 'scripts/build.ps1')
    old_inputs = read(ROOT / 'prj/td_build/timingclean_r1_syn/inputs.json')
    old_sources = {v['path']: v['sha256'].lower() for v in old_inputs['sources']}
    new_sources = {v['path']: v['sha256'].lower() for v in syn_inputs['sources']}
    assert old_sources.keys() == new_sources.keys()
    changed = sorted(Path(p).relative_to(ROOT).as_posix() for p in new_sources
                     if new_sources[p] != old_sources[p])
    assert changed == ['rtl/gfx/osd_layer_small.v'], changed
    baseline, current = physical(BASE), physical(PHY)
    normal = sum(v['setup_violations'] for k, v in current['groups'].items() if 'sdr_clk_sft' not in k)
    timing_clean = current['setup_violations'] == current['hold_violations'] == 0
    warnings = {}
    for stage, before, after in [('syn', 'timingclean_r1_syn', SYN), ('phy', BASE, PHY)]:
        old, new = Counter(warning_lines(before)), Counter(warning_lines(after))
        warnings[stage] = dict(unchanged=old == new, added=list((new-old).elements()),
                               removed=list((old-new).elements()), current=list(new.elements()))
    shutil.copy2(Path(phy_result['bitstream']['path']), bit)
    assert sha(bit) == phy_result['bitstream']['sha256'].lower()
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        status='completed_implementation' if timing_clean else 'completed_implementation_timing_unmet',
        panel_xywh=[440, 256, 200, 224], translation=[16, 240],
        baseline_user_board_validation='User confirmed previous timing-cleanup bit works on board',
        changed_build_inputs=changed, tests=tests, baseline=baseline, current=current,
        synthesis_result=syn_result, physical_result=phy_result, warnings=warnings,
        ordinary_setup_endpoints=normal, timing_clean=timing_clean,
        bitstream=dict(path=bit.relative_to(ROOT).as_posix(), bytes=bit.stat().st_size, sha256=sha(bit)),
        board_validation='not_run', card_update_required=False,
        attempts=1, automatic_retries=0,
        scope='New OSD position request; no further timing-cleanup retry or constraint changes')
    write(OUT / 'verification_and_build.json', evidence)
    files = ('rtl/gfx/osd_layer_small.v', 'tb/tb_osd_typography.v', 'tb/tb_typography_core.v')
    write(OUT / 'change_inputs.json', dict(
        before_sha256={p: sha(OUT / 'source_before' / p) for p in files},
        after_sha256={p: sha(ROOT / p) for p in files},
        panel_xywh=[440,256,200,224], translation=[16,240],
        oracle='Original independent six-frame reference, inverse-translated by checkers'))

    lines = ['# OSD 右下角贴边', '',
        'OSD 从 x=424..623、y=16..239 移到 x=440..639、y=256..479，保持 200×224 像素。右边框与下边框贴住有效画面最后一列、最后一行。', '',
        '仅修改 osd_layer_small.v 的绝对几何常量。三个页面、字体与抗锯齿、色值、曲线与数值、三拍延迟保持。歌词、歌名、歌手和封面代码未变；OSD 显示时仍按原优先级覆盖下层。', '',
        '8 个自检场景及板级编译展开通过：六个完整 640×480 帧共 1,843,200 个光栅位置，独立原图反向平移对照；动态历史曲线；隐藏/消隐及历史状态；完整合成链路 307,200 像素、480 行和 AX 行尾核对。', '',
        '综合、布局布线、bit 生成完成，一次实现，seed=3、routability。未下载或上板，SD 卡无需更新。', '',
        '|资源|上一版|本版|', '|---|---:|---:|']
    for label, key, total in [('Slice','slices',9800),('LUT','lut',19600),('FF','registers',19600),
                              ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f'|{label}|{baseline["resources"][key]}/{total}|{current["resources"][key]}/{total}|')
    lines.extend(['', f'Setup 违例 {baseline["setup_violations"]} → {current["setup_violations"]}，'
        f'本版非移相组 {normal}，Hold 违例 {current["hold_violations"]}；'
        f'全局 WNS {current["setup_wns_ns"]} ns、TNS {current["setup_tns_ns"]} ns。', '',
        '时序尚未闭合。用户确认上一版实板正常不等于本版时序通过。没有添加 false path/multicycle，没有改变 PLL、频率、管脚和 SDC。本次只完成布局调整，不继续上一轮已停止的时序优化。', '',
        '|路径组|本版 Setup/ns|违例端点|', '|---|---:|---:|'])
    for name, group in current['groups'].items():
        lines.append(f'|{name}|{group["setup_ns"]:+.3f}|{group["setup_violations"]}|')
    lines.extend(['', '综合、物理与仿真告警保留于 verification_and_build.json 及原始日志；'
        f'综合告警与上一版{"一致" if warnings["syn"]["unchanged"] else "存在差异，见证据"}，'
        f'物理告警{"一致" if warnings["phy"]["unchanged"] else "存在差异，见证据"}。', '',
        f'bit：{bit.relative_to(ROOT).as_posix()}', f'SHA256：{sha(bit)}',
        f'物理报告：prj/td_build/{PHY}/final_timing.rpt',
        '证据：output/osd_bottom_right_20261030/verification_and_build.json',
        '源文件备份：output/osd_bottom_right_20261030/source_before/', ''])
    report = ROOT / 'doc/compile/osd_bottom_right_report.md'
    report.write_text('\n'.join(lines), encoding='utf-8')
    state_path = ROOT / 'doc/workflow/state.json'
    state = read(state_path)
    state['osd_bottom_right'] = dict(status=evidence['status'],
        specification='doc/spec/osd_bottom_right_behavior_spec.md',
        report=report.relative_to(ROOT).as_posix(), evidence='output/osd_bottom_right_20261030/verification_and_build.json',
        stages=dict(rtl='completed', simulation='completed', synthesis='completed', physical='completed', board='pending'),
        timing_clean=timing_clean, previous_implementation_evidence='historical_before_osd_translation',
        bitstream=evidence['bitstream'], board_validation='not_run')
    write(state_path, state)
    write(ROOT / 'doc/workflow/quality_reports/osd_bottom_right.json', dict(status='completed',
        files_written=list(files)+[report.relative_to(ROOT).as_posix(),bit.relative_to(ROOT).as_posix()],
        missing_files=[], reason='OSD translation verified; routed bit generated; timing closure not claimed',
        verification_level='simulation_and_physical_implementation', timing_clean=timing_clean,
        evidence='output/osd_bottom_right_20261030/verification_and_build.json'))
    print(json.dumps(dict(bit=evidence['bitstream'], current=current), indent=2))


if __name__ == '__main__':
    main()
