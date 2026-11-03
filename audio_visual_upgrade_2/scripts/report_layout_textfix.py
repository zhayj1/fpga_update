"""Audit current text-repair evidence and package the selected routed candidate."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re
import shutil

from report_downscale_implementation import physical, verify_build, warning_lines

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/layout_textfix_20261030'
FAILED = 'layout_five_r6_congestion_seed3_phy'
RUNS = {'row': 'textfix_r7', 'full_rows': 'textfix_r8', 'full_sdram': 'textfix_r8',
        'layout': 'textfix_r8', 'layout_sdram': 'textfix_r8', 'layer': 'textfix_r7',
        'core': 'textfix_r8', 'board': 'textfix_r8', 'osd': 'textfix_r8',
        'layout_pick': 'r2', 'layout_rings': 'r3', 'full_load': 'textfix_r8',
        'assets': 'textfix_r8', 'bmp_writeback': 'textfix_r7', 'font_legacy': 'textfix_r8',
        'legacy_system': 'textfix_r8'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_tests():
    tests = {}
    for name, suffix in RUNS.items():
        path = ROOT / f'sim/typography_{name}_{suffix}_sim_result.json'
        result = read(path)
        status = 'COMPILE_PASS' if name == 'board' else 'PASS'
        stale = [p for p, digest in result['input_hashes'].items()
                 if not Path(p).is_file() or sha(Path(p)) != digest.lower()]
        assert result['status'] == status, (name, result['status'])
        assert result['compile_exit_code'] == 0
        passed = []
        if result.get('sim_log'):
            log = (ROOT / result['sim_log']).read_text(errors='replace')
            passed = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
            assert result['sim_exit_code'] == 0
            assert sorted(passed) == sorted(result['expected_scenarios']) and passed, name
            assert len(passed) == len(set(passed)), name
            assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log, name
        tests[name] = dict(status=result['status'], evidence=path.relative_to(ROOT).as_posix(),
                           compile_log=result['compile_log'], sim_log=result.get('sim_log'),
                           scenarios=passed, input_hashes_current=not stale, changed_inputs=stale,
                           warning_lines=sorted(set(result.get('warning_lines', []))),
                           elapsed_seconds=round(result['finished_at'] - result['started_at'], 2))
    return tests


def verify_rom():
    """Check the stored ROM, without regenerating any build input."""
    rom = [int(v, 16) for v in (ROOT / 'rtl/gfx/glyph_blocks.dath').read_text().split()]
    assert len(rom) == 512
    font_path = ROOT / 'output/typography_full_20261030/sd_card/FONT.HZK'
    font = font_path.read_bytes()
    assert len(font) == 3856960
    count = 0
    for hi in range(256):
        for lo in range(256):
            if hi == 0:
                valid = 32 <= lo <= 126
                index = 8178 + lo - 32
            else:
                try:
                    bytes((hi, lo)).decode('gb2312')
                    valid = 161 <= hi <= 247 and 161 <= lo <= 254
                except UnicodeDecodeError:
                    valid = False
                index = (hi - 161) * 94 + lo - 161
            if valid:
                offset = 16 + index * 4
                expected = int.from_bytes(font[offset:offset + 4], 'little') & 0x3ffff
                assert (rom[hi] + rom[256 + lo]) & 0x3ffff == expected, (hi, lo)
                count += 1
    assert count == 7540
    return dict(status='PASS', glyphs=count, rom_words=512,
                sha256=sha(ROOT / 'rtl/gfx/glyph_blocks.dath'),
                unchanged_font=dict(path=str(font_path), bytes=len(font), sha256=sha(font_path)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tests-only', action='store_true')
    parser.add_argument('--synthesis', default='textfix_r4_syn')
    parser.add_argument('--physical', default='textfix_r4_congestion_seed3_phy')
    args = parser.parse_args()
    tests = audit_tests()
    rom = verify_rom()
    write(ROOT / 'doc/compile/layout_textfix_test_audit.json', dict(tests=tests, rom=rom))
    if args.tests_only:
        print(json.dumps(dict(tests=tests, rom=rom), ensure_ascii=False, indent=2))
        return
    assert all(t['input_hashes_current'] for t in tests.values()), 'Stale test evidence'
    syn_inputs, syn_result = verify_build(args.synthesis)
    phy_inputs, phy_result = verify_build(args.physical)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == args.synthesis
    for inputs in (syn_inputs, phy_inputs):
        assert inputs['script_sha256'].lower() == sha(ROOT / 'scripts/build.ps1')
    old_inputs = read(ROOT / f'prj/td_build/{FAILED}/inputs.json')
    old_sources = {v['path'].lower(): v['sha256'].lower() for v in old_inputs['sources']}
    changed = [Path(v['path']).relative_to(ROOT).as_posix() for v in syn_inputs['sources']
               if v['sha256'].lower() != old_sources.get(v['path'].lower())]
    for v in syn_inputs['sources']:
        if Path(v['path']).suffix in ('.adc', '.sdc'):
            assert v['sha256'].lower() == old_sources[v['path'].lower()], 'Changed constraints'
    baseline = physical(FAILED)
    current = physical(args.physical)
    console = (ROOT / f'prj/td_build/{args.physical}/console.log').read_text(errors='replace')
    packed = re.findall(r'(\d+) mslices, (\d+) lslices', console)
    assert packed
    mslice, lslice = map(int, packed[-1])
    assert max(mslice, lslice) <= 4900
    assert mslice + lslice == current['resources']['slices']
    current['slice_types'] = dict(mslice=mslice, lslice=lslice, each_limit=4900)
    limits = dict(slices=9800, lut=19600, registers=19600, bram9k=64, bram32k=16,
                  dsp=29, pll=4, gclk=16)
    assert all(current['resources'][k] <= v for k, v in limits.items())
    clean = current['setup_violations'] == current['hold_violations'] == 0
    additional = sum(g['setup_violations'] for name, g in current['groups'].items()
                     if 'sdr_clk_sft' not in name)
    old_bit = ROOT / 'output/layout_five_20261030/audio_visual_layout_five.bit'
    assert sha(old_bit) == '9e39b03509230278a673821e00415f2a654375a4601716745e11cd8b4d9534f9'
    assert sha(ROOT / 'output/typography_full_20261030/audio_visual_full_font.bit') == \
        '4be042262fad8a3f725dbcebdacdcf2abc33ece789cd9ced601be105cb08c9b0'
    sdram_log = (ROOT / tests['full_sdram']['sim_log']).read_text()
    cycles = int(re.search(r'FULL_ROW_MAX_CYCLES (\d+)', sdram_log)[1])
    assert cycles < 3200
    OUT.mkdir(exist_ok=True)
    target = OUT / 'audio_visual_layout_textfix.bit'
    bit = phy_result['bitstream']
    shutil.copy2(bit['path'], target)
    assert sha(target) == bit['sha256'].lower()
    state_path = ROOT / 'doc/workflow/state.json'
    state = read(state_path)
    limitations = [
        'Board symptoms have not been re-tested with this candidate.',
        'No post-route timing simulation, new-layout SD/FAT-to-HDMI boot or board download performed.',
        'The real SDRAM contention tests cover the simulated arbitration phases, not all possible phases.',
        'The core composition test drives controlled layer pixels; storage and full-layer checks are separate.',
        'Legacy SD/FAT/audio integration uses TYPOGRAPHY=0 and reduced image targets; complete-font and new layout checked separately.',
        'Existing LRC1 limits remain: 64 lines, 488 records, 19 characters per sentence and 24 for title/singer.']
    if not clean:
        limitations.append('Global setup timing is not closed; see clock-group results.')
    if additional:
        limitations.append(f'{additional} setup endpoints remain outside the pre-existing shifted-SDRAM groups, including the text data capture and title descriptor paths.')
    repair = state['layout_text_repair']
    retry_exhausted = (repair['repair_attempts_used'] >= repair['maximum_automatic_repairs']
                       and not clean)
    if retry_exhausted:
        limitations.append('The three automatic structural repairs are exhausted; further RTL/route retries are stopped pending a new authorized repair round or materially new evidence.')
    evidence = dict(status='BUILD_COMPLETE', generated=datetime.now().astimezone().isoformat(),
        synthesis=args.synthesis, physical=args.physical, synthesis_result=syn_result,
        baseline_physical=FAILED, baseline=baseline, current=current,
        original_build_bitstream=bit,
        bitstream=dict(path=str(target), bytes=target.stat().st_size, sha256=sha(target)),
        changed_sources=changed, all_build_inputs_current=True, all_test_inputs_current=True,
        timing_clean=clean, tests=tests, rom_check=rom, max_contended_row_cycles_100MHz=cycles,
        additional_non_shifted_setup_endpoints=additional,
        automatic_repairs_exhausted=retry_exhausted,
        simulation_scenario_count=sum(len(t['scenarios']) for t in tests.values()),
        board_validation='not_run', symptoms=state['layout_text_repair']['symptoms'],
        repairs=state['layout_text_repair']['attempts'], validation_limits=limitations,
        warnings={tag: warning_lines(tag) for tag in (args.synthesis, args.physical)})
    write(OUT / 'verification_and_build.json', evidence)
    r = current['resources']
    lines = ['# 歌词/歌名花屏修复：验证与实现', '', '2026-10-30；EG4S20BG256；TD 6.2.168116；ModelSim 10.6e。', '',
        '用户报告歌词和歌名稳定错误叠加闪烁，歌手与OSD正常。此次修复针对已确认的取字长组合路径、换字控制和视频混色时序。',
        '功能仿真及构建结果不能直接证明上板症状已消失；新版尚未上板。', '',
        '## 修改', '',
        '- 高/低字节ROM分解完整字库地址运算；7540个目录地址逐项核对实际FONT.HZK。',
        '- 简化末像素与32位字切换控制；时间戳按字节比较后寄存合并。',
        '- 行截止使用SDR域捕获的坐标；描述符/相位迁移控制在像素域提前寄存。',
        '- 色彩处理与精确16级文字混色分拍；文字、OSD、DE、VS、行尾同步对齐。',
        '- OSD归一化乘积与绘图拆拍，复用外部对齐级；图片写回操作数和地址提前寄存。',
        '- 字体、字号、字库、五行布局、14字窗口、平滑滚动、逐字变色及其他视觉效果保持。', '',
        '## 验证', '',
        f"当前输入哈希一致的{evidence['simulation_scenario_count']}个功能场景及板级编译展开通过。",
        '真实SDRAM及四图像客户端争用下，四个640×480帧逐像素比较；覆盖纵移0/16/32px、切句和横滚。',
        f'完整字库7540字、两字号；争用最慢{cycles}拍@100MHz（{cycles/100:.2f}μs），小于32μs。',
        'OSD六帧逐像素比对及变化幅度历史检查通过；原有SD/FAT、切歌和PCM/视频回归通过。',
        '核心混色覆盖全部16级alpha与淡入淡出端点；OSD帧163840像素、256个640像素行尾逐项核对。', '',
        '## 资源与时序', '', '|资源|上板失败版|当前|变化|', '|---|---:|---:|---:|']
    for label, key in [('Slice','slices'),('LUT','lut'),('寄存器','registers'),
                       ('BRAM9K','bram9k'),('BRAM32K','bram32k'),('DSP','dsp')]:
        old, new = baseline['resources'][key], r[key]
        lines.append(f'|{label}|{old}/{limits[key]}|{new}/{limits[key]}|{new-old:+d}|')
    lines += ['', f'MSlice {mslice}/4900，LSlice {lslice}/4900。', '',
        '|路径组|失败版setup/ns|当前setup/ns|当前setup违例|当前hold/ns|', '|---|---:|---:|---:|---:|']
    for name, g in current['groups'].items():
        lines.append(f"|{name}|{baseline['groups'][name]['setup_ns']:+.3f}|{g['setup_ns']:+.3f}|{g['setup_violations']}|{g['hold_ns']:+.3f}|")
    lines += ['', f"全局setup WNS {current['setup_wns_ns']:+.3f}ns，TNS {current['setup_tns_ns']:.3f}ns，"
        f"{current['setup_violations']}个违例；hold WNS {current['hold_wns_ns']:+.3f}ns，{current['hold_violations']}个违例。",
        f"STA coverage {current['sta_coverage_percent']:.2f}%。未修改时钟、管脚和时序例外。", '']
    if additional:
        lines += [f'既有移相SDRAM组以外还剩{additional}个setup违例，不能称文字问题已修复：', '']
        for name, g in current['groups'].items():
            if 'sdr_clk_sft' not in name and g['setup_violations']:
                lines += [f"- `{name}`：{g['setup_violations']}个，最差{g['setup_ns']:+.3f}ns；"
                          f"`{g['worst_start']}` → `{g['worst_end']}`。"]
        lines += ['', '完整端点与下一轮结构修复建议见doc/compile/repair_report.md；当前候选仅供验证。', '']
    if retry_exhausted:
        lines += ['三次自动结构修复已用尽，当前停止继续修改RTL或换种子；后续需新信息或用户明确授权新一轮。', '']
    lines += [
        '## 交付与限制', '', f'- bit：`{target.relative_to(ROOT).as_posix()}`。',
        '- SD卡完整FONT.HZK及其他素材无需更新；旧正常版和旧失败版bit均保留。',
        f'- 综合/物理：`prj/td_build/{args.synthesis}`、`prj/td_build/{args.physical}`。',
        '- 完整日志、输入哈希、警告和物理结果见同包verification_and_build.json。',
        f'- SHA256：`{sha(target)}`。', ''] + ['- '+s for s in limitations] + ['']
    report = ROOT / 'doc/compile/layout_textfix_report.md'
    report.write_text('\n'.join(lines), encoding='utf-8')
    (OUT / 'README.md').write_text('\n'.join([
        '# 歌词/歌名文字修复验证包', '', '烧录audio_visual_layout_textfix.bit，SD卡文件无需更换。',
        '保留当前五行布局、字体、16级抗锯齿和全部显示效果。', '',
        f"Slice {r['slices']}/9800；LUT {r['lut']}/19600；BRAM9K {r['bram9k']}/64；DSP {r['dsp']}/29。",
        f"功能自检及综合/布局布线完成；全局setup WNS {current['setup_wns_ns']:+.3f}ns，"
        f"{current['setup_violations']}个setup违例。新版尚未上板。",
        f'其中{additional}个setup端点在既有移相SDRAM路径组以外，文字相关路径仍有违例；此文件为待验证候选。',
        '详细路径组、验证范围与限制见verification_and_build.json及doc/compile/layout_textfix_report.md。',
        '', f'SHA256：{sha(target)}', '']), encoding='utf-8')
    state.update(active_stage='layout_text_repair', status='completed' if clean else 'completed_implementation_timing_unmet',
                 board_validation='repair_not_board_tested', report='doc/compile/layout_textfix_report.md',
                 limitations=limitations)
    state['layout_text_repair'].update(status=state['status'],
        stages={key:'completed' for key in ('analysis','rtl','verification','implementation')},
        evidence='output/layout_textfix_20261030/verification_and_build.json',
        timing_clean=clean, board_validation='not_run',
        additional_non_shifted_setup_endpoints=additional,
        automatic_repairs_exhausted=retry_exhausted,
        next_step=('等待新一轮结构修复授权或实质新信息，处理取字接收使能、描述符校验跨域路径和仲裁器计数比较；当前bit仅为验证候选。'
                   if retry_exhausted else '用户上板验证；剩余时序问题见报告。'))
    write(state_path, state)
    write(ROOT / 'doc/workflow/quality_reports/layout_text_repair.json', dict(
        skill='fpga-workflow', status='completed' if clean else 'partial',
        files_written=changed + ['tb/text_sdram_environment.v','tb/tb_layout_five.v',
            'tb/tb_typography_core.v','scripts/generate_glyph_blocks.py',
            'scripts/report_layout_textfix.py','doc/spec/layout_five_behavior_spec.md',
            'doc/compile/layout_textfix_report.md',target.relative_to(ROOT).as_posix()],
        missing_files=[], verification_level='functional_simulation_and_routed_bitstream',
        timing_clean=clean, board_validated=False,
        evidence='output/layout_textfix_20261030/verification_and_build.json',
        reason='Functional and build checks pass; board validation pending; remaining STA limits recorded.'))
    print(json.dumps(dict(bitstream=evidence['bitstream'], current=current,
                         scenarios=evidence['simulation_scenario_count']), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
