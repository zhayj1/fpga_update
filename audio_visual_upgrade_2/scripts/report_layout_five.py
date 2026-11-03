"""Validate current-source evidence and package the routed five-line layout."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import importlib.util
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/layout_five_20261030'
BASELINE = 'typography_full_r1_congestion_seed3_phy'
RUNS = {'layout': 'r9', 'layout_pick': 'r2', 'layout_rings': 'r3',
        'row': 'layout_r2', 'full_rows': 'layout_r2', 'full_sdram': 'layout_r2',
        'layer': 'layout_r5', 'core': 'layout_r5', 'board': 'layout_r6',
        'full_load': 'full_r5', 'assets': 'full_r3',
        'bmp_writeback': 'full_r2', 'font_legacy': 'full_r2'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--synthesis', default='layout_five_r6_syn')
    parser.add_argument('--physical', default='layout_five_r6_congestion_seed3_phy')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('physical_report', ROOT / 'scripts/report_downscale_implementation.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    syn_inputs, syn_result = helper.verify_build(args.synthesis)
    phy_inputs, phy_result = helper.verify_build(args.physical)
    for inputs in (syn_inputs, phy_inputs):
        assert sha(ROOT / 'scripts/build.ps1') == inputs['script_sha256'].lower()
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == args.synthesis
    measured = helper.physical(args.physical)
    baseline = helper.physical(BASELINE)
    console = (ROOT / f'prj/td_build/{args.physical}/console.log').read_text(errors='replace')
    packed = re.findall(r'(\d+) mslices, (\d+) lslices', console)
    assert packed, 'Missing physical slice type counts'
    mslice, lslice = map(int, packed[-1])
    assert max(mslice, lslice) <= 4900
    assert mslice + lslice == measured['resources']['slices']
    measured['slice_types'] = {'mslice': mslice, 'lslice': lslice, 'each_limit': 4900}
    bit = phy_result['bitstream']
    assert bit and bit['bytes'] > 0
    limits = {'slices': 9800, 'lut': 19600, 'registers': 19600,
              'bram9k': 64, 'bram32k': 16, 'dsp': 29, 'pll': 4, 'gclk': 16}
    assert all(measured['resources'][key] <= limit for key, limit in limits.items())
    tests = {}
    all_scenarios = []
    for name, suffix in RUNS.items():
        path = ROOT / f'sim/typography_{name}_{suffix}_sim_result.json'
        result = read(path)
        expected_status = 'COMPILE_PASS' if name == 'board' else 'PASS'
        assert result['status'] == expected_status, (name, result['status'])
        for path_string, digest in result['input_hashes'].items():
            assert sha(Path(path_string)) == digest.lower(), (name, path_string)
        assert result['compile_exit_code'] == 0
        passed = []
        if result.get('sim_log'):
            assert result['sim_exit_code'] == 0
            log = (ROOT / result['sim_log']).read_text(errors='replace')
            passed = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
            expected = result['expected_scenarios']
            assert expected and len(expected) == len(set(expected))
            assert sorted(passed) == sorted(expected), (name, passed)
            assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log
            all_scenarios.extend(f'{name}:{scenario}' for scenario in passed)
        tests[name] = {'status': result['status'], 'evidence': path.relative_to(ROOT).as_posix(),
                       'compile_log': result['compile_log'], 'sim_log': result.get('sim_log'),
                       'scenarios': passed, 'input_hashes_current': True,
                       'warning_lines': sorted(set(result.get('warning_lines', []))),
                       'elapsed_seconds': round(result['finished_at'] - result['started_at'], 2)}
    sdram_log = (ROOT / tests['full_sdram']['sim_log']).read_text()
    max_cycles = int(re.search(r'FULL_ROW_MAX_CYCLES (\d+)', sdram_log)[1])
    assert max_cycles < 3200
    old_inputs = read(ROOT / f'prj/td_build/{BASELINE}/inputs.json')
    old_sources = {item['path'].lower(): item['sha256'].lower() for item in old_inputs['sources']}
    changed = [Path(item['path']).relative_to(ROOT).as_posix() for item in syn_inputs['sources']
               if item['sha256'].lower() != old_sources.get(item['path'].lower())]
    assert set(changed) == {'rtl/gfx/lyric_pick.v', 'rtl/gfx/attack_rings.v',
                            'rtl/gfx/text_row_aa.v', 'rtl/gfx/layer_text_aa.v',
                            'rtl/top/skeleton_core.v'}, changed
    # The previous packaged bit and complete font are retained unchanged.
    old_bit = ROOT / 'output/typography_full_20261030/audio_visual_full_font.bit'
    assert sha(old_bit) == '4be042262fad8a3f725dbcebdacdcf2abc33ece789cd9ced601be105cb08c9b0'
    assets = read(ROOT / 'output/typography_full_20261030/asset_check.json')
    assert assets['status'] == 'PASS'
    for path_string, digest in assets['input_hashes'].items():
        assert sha(Path(path_string)) == digest.lower(), path_string
    font = ROOT / 'output/typography_full_20261030/sd_card/FONT.HZK'
    assert font.stat().st_size == 3856960
    target = OUT / 'audio_visual_layout_five.bit'
    shutil.copy2(bit['path'], target)
    assert sha(target) == bit['sha256'].lower()
    clean = measured['setup_violations'] == measured['hold_violations'] == 0
    state_path = ROOT / 'doc/workflow/state.json'
    state = read(state_path)
    repairs = state['layout_five']['repairs']
    evidence = {'status': 'BUILD_COMPLETE', 'generated': datetime.now().astimezone().isoformat(),
                'synthesis': args.synthesis, 'physical': args.physical,
                'bitstream': {'path': str(target), 'bytes': target.stat().st_size, 'sha256': sha(target)},
                'original_build_bitstream': bit,
                'synthesis_result': syn_result, 'current': measured, 'baseline': baseline,
                'baseline_physical': BASELINE, 'baseline_board_validation': 'passed_user_report',
                'changed_sources': changed, 'timing_clean': clean,
                'tests': tests, 'simulation_scenario_count': len(all_scenarios),
                'all_build_inputs_current': True, 'all_test_inputs_current': True,
                'max_contended_row_cycles_100MHz': max_cycles,
                'unchanged_font': {'path': str(font), 'bytes': font.stat().st_size, 'sha256': sha(font)},
                'free_sdram_bytes': 145152, 'repairs': repairs,
                'warnings': {tag: helper.warning_lines(tag) for tag in (args.synthesis, args.physical)},
                'synthesis_warning_lines_unchanged': helper.warning_lines(args.synthesis) == helper.warning_lines('typography_full_r1_syn'),
                'board_validation': 'not_run_for_layout_five',
                'validation_limits': [
                    'New-layout pixel, picker, ring and row tests are separate from core composition tests; core forces layer pixels.',
                    'Real SDRAM model deadline result covers the tested contention patterns, not every possible arbitration alignment.',
                    'No new-layout SD/FAT-to-HDMI boot simulation, post-route simulation, download or board test performed.',
                    'Legacy whole-system test is historical and stale after this change; current default text mode, full font loader, BMP writeback, core and board elaboration are checked separately.',
                    'Existing LRC1 limits remain: 64 lines, 488 records, 19 characters per lyric sentence and 24 for title/singer.']}
    write(OUT / 'verification_and_build.json', evidence)
    r = measured['resources']
    lines = ['# 左封面、右侧五行歌词：实现与验证', '',
             '日期：2026-10-30。EG4S20BG256；Tang Dynasty 6.2.168116；ModelSim 10.6e。', '',
             '新布局已通过功能回归、综合、布局布线并生成bit；新版尚未上板。'
             + (' 全工程setup/hold通过。' if clean else ' 全工程setup时序未收敛，bit为待上板验证的功能候选。'),
             '修改前完整字库版本已由用户确认上板正常；该事实不代表本次新布局已经上板。', '',
             '## 交付与显示', '',
             '- bit：`output/layout_five_20261030/audio_visual_layout_five.bit`。',
             '- 沿用当前完整TYP2字库FONT.HZK（3,856,960字节），无需重新生成或更换卡素材。',
             '- 封面中心移至(160,165)，歌名/歌手窗口x=336..623、y=16/48。',
             '- 歌词窗口x=296..631，宽336px，容14个24px汉字；短句居中，超宽句横滚，保留19字行格式上限。',
             '- 五行顶部y=89/121/153/185/217；静止当前句第三行，上下各两句；首尾不足留空。',
             '- 原提前0.3s上移32px保留，切句后新当前句落第三行；横滚相位跟随句子。',
             '- 华文琥珀/幼圆、字号、16级覆盖率、逐字变色、背景、频谱、封面弹跳及圆环保持。', '',
             '## 资源与省资源措施', '',
             '|资源|修改前|新布局|变化|', '|---|---:|---:|---:|']
    for label, key in [('Slice', 'slices'), ('LUT', 'lut'), ('寄存器', 'registers'),
                       ('BRAM9K', 'bram9k'), ('BRAM32K', 'bram32k'), ('DSP', 'dsp')]:
        before = baseline['resources'][key]
        lines.append(f'|{label}|{before}/{limits[key]}|{r[key]}/{limits[key]}|{r[key]-before:+d}|')
    lines += ['', f'MSlice {mslice}/4900，LSlice {lslice}/4900；总Slice余量{9800-r["slices"]}个。', '',
              '共用一个逐行取字引擎和原2048×8双bank RAM；时间轴仍每帧一次136word读取。'
              '描述符、坐标与看门狗按真实范围定宽；六句相位共用加法比较；32px行距共用选行坐标；'
              '像素地址和裁剪mask共用源坐标并与同步RAM对齐；相位与行宽采用循环起点映射，'
              '正常切句仅推进起点、清空尾槽，省去114位寄存器搬移。未降低字体覆盖率或删减显示效果。',
              '封面左移后距离平方扩为24位，防止远右侧溢出伪环。SDRAM布局与完整字库不变，仍剩145,152字节。', '',
              '首轮物理打包4935个MSlice，超过4900上限；首轮结构压缩后4934，仍超限。'
              '失败日志保留在layout_five_r2及layout_five_r4对应phy目录；未以更换种子代替结构优化。', '',
              '## 验证与时序', '',
              f'{len(all_scenarios)}个功能自检场景及板级编译展开通过；逐项核对输入哈希与当前文件一致。',
              '五行测试对17帧逐像素比较alpha和颜色，覆盖14/15/19字、居中、横滚停留/环回、'
              '0/16/32px纵移、第六句进入、相位迁移、连续8句跨循环起点环回、迟到取消/恢复、双bank保护、换歌及首尾空行；另验证右侧标题/歌手位置与横滚。',
              '歌词扫描覆盖64句、重复时间戳、坏表、截短和复位；圆环覆盖中心160/260及age0/10全帧。',
              f'真实SDRAM控制器和器件模型争用测试最慢{max_cycles}拍@100MHz，即{max_cycles/100:.2f}μs，小于32μs行周期。'
              '这是模型场景结果，不是上板或STA证明。',
              '全字库两字号、取字引擎错误/取消、旧显示模式、字库装载、BMP写回、核心混色及OSD对齐分别通过；'
              '旧整机SD/FAT回归为历史结果，源码已变，未计入本次当前源码通过数。', '',
              f"setup WNS {measured['setup_wns_ns']:+.3f}ns，TNS {measured['setup_tns_ns']:.3f}ns，"
              f"违例端点{measured['setup_violations']}；hold WNS {measured['hold_wns_ns']:+.3f}ns，"
              f"违例端点{measured['hold_violations']}。STA coverage {measured['sta_coverage_percent']:.2f}%。", '',
              f"原完整字库版setup违例{baseline['setup_violations']}个，本版{measured['setup_violations']}个；"
              '视频同域与取字同域裕量较原版变差，不能把全部负裕量归为既有移相SDRAM路径。'
              '当前bit为功能候选，尚未完成时序收敛和新版上板验证。', '',
              '|时钟组|原setup/ns|新setup/ns|新setup违例|新hold/ns|', '|---|---:|---:|---:|---:|']
    for group, values in measured['groups'].items():
        lines.append(f"|{group}|{baseline['groups'][group]['setup_ns']:+.3f}|{values['setup_ns']:+.3f}|"
                     f"{values['setup_violations']}|{values['hold_ns']:+.3f}|")
    lines += ['', '未更改时钟、管脚或时序例外约束；未做新布局SD/FAT整机启动、布局后时序仿真、下载或上板。', '',
              '## 证据', '', f'- 综合：`prj/td_build/{args.synthesis}/`。',
              f'- 物理与时序：`prj/td_build/{args.physical}/route.qor`、`skeleton_phy.area`、`final_timing.rpt`。',
              '- 每项日志与哈希：`output/layout_five_20261030/verification_and_build.json`。',
              '- 需求与场景映射：`doc/spec/layout_five_behavior_spec.md`。',
              f'- bit SHA256：`{sha(target)}`。', '']
    report_path = ROOT / 'doc/compile/layout_five_report.md'
    report_path.write_text('\n'.join(lines), encoding='utf-8')
    readme = ['# 五行歌词布局上板包', '',
              '烧录本目录audio_visual_layout_five.bit；沿用已上板通过版本的完整FONT.HZK和其他SD卡文件。', '',
              '左封面，右歌名/歌手与五行歌词；静止当前句第三行，保留平滑切句；14个汉字窗口，超宽横滚。',
              '字体、字号、16级抗锯齿与其他显示效果保持。', '',
              f"Slice {r['slices']}/9800；LUT {r['lut']}/19600；BRAM9K {r['bram9k']}/64；"
              f"BRAM32K {r['bram32k']}/16；DSP {r['dsp']}/29。", '',
              f"功能回归、综合、布局布线完成；setup WNS {measured['setup_wns_ns']:+.3f}ns，"
              + ('时序通过。' if clean else f"{measured['setup_violations']}个setup违例端点，时序未收敛。"),
              '新版尚待上板；详细验证范围与限制见verification_and_build.json和doc/compile/layout_five_report.md。', '',
              f'bit SHA256：{sha(target)}', '']
    (OUT / 'README.md').write_text('\n'.join(readme), encoding='utf-8')
    state['task_history'].append({key: state[key] for key in ('active_stage', 'scope', 'status', 'board_validation', 'report', 'limitations')})
    state.update(active_stage='layout_five', scope=state['layout_five']['scope'],
                 status='completed' if clean else 'completed_implementation_timing_unmet',
                 board_validation='not_run_for_layout_five', report='doc/compile/layout_five_report.md',
                 limitations=evidence['validation_limits'] + ([] if clean else ['Global setup timing is not closed.']))
    state['layout_five'].update(status='completed', stages={key: 'completed' for key in
                               ('architecture', 'rtl', 'verification', 'implementation')},
                               evidence='output/layout_five_20261030/verification_and_build.json',
                               sources={name: sha(ROOT / name) for name in changed},
                               evidence_current_at_last_update=True, timing_clean=clean,
                               next_step='用户上板验证新布局；全工程setup优化仍待后续处理。' if not clean else '用户上板验证新布局。')
    write(state_path, state)
    write(ROOT / 'doc/workflow/quality_reports/layout_five.json', {
        'skill': 'fpga-workflow', 'status': 'completed',
        'verification_level': 'functional_simulation_and_routed_bitstream',
        'files_written': changed + ['doc/spec/layout_five_behavior_spec.md', 'doc/compile/layout_five_report.md',
                                   'output/layout_five_20261030/audio_visual_layout_five.bit',
                                   'output/layout_five_20261030/README.md',
                                   'output/layout_five_20261030/verification_and_build.json'],
        'missing_files': [], 'timing_clean': clean, 'board_validated': False,
        'reason': 'Current-source behavior checks and routed bit generated; STA and board limits explicitly recorded.',
        'evidence': 'output/layout_five_20261030/verification_and_build.json'})
    print(json.dumps({'resources': r, 'timing_clean': clean, 'setup_wns_ns': measured['setup_wns_ns'],
                      'setup_violations': measured['setup_violations'],
                      'scenarios': len(all_scenarios), 'bitstream': evidence['bitstream']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
