"""Audit this timing repair without overwriting any previous delivery."""
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
import shutil

import report_layout_textfix as audit
from report_downscale_implementation import physical, verify_build, warning_lines

ROOT = Path(__file__).resolve().parents[1]
BASE = 'lyricspace_r1_congestion_seed3_phy'
SYN = 'timingclean_r4_syn'
PHY = 'timingclean_r4_congestion_seed3_phy'
OUT = ROOT / 'output/timing_cleanup_20261030'
SELECTED = 4


def palette_check():
    path = ROOT / 'rtl/gfx/osd_blend_palette.dath'
    rom = [int(x, 16) for x in path.read_text().split()]
    backgrounds = [0x070e13, 0x48636a, 0x49ded4, 0x405258, 0x24303b,
                   0x070b10, 0x35d0c4, 0xb8893c, 0xffb347] + [0x070e13]*7
    foregrounds = [0xe7f0f0, 0x49ded4, 0xffb347, 0xb6c6c9]
    assert len(rom) == 1024
    for address, got in enumerate(rom):
        bg, fg, alpha = backgrounds[address >> 6], foregrounds[(address >> 4) & 3], address & 15
        # Dividing the convex sum by 15 and rounding to nearest is exact here;
        # denominator 15 cannot have a half-integer tie.
        expected = sum(round((((bg >> s) & 255)*(15-alpha) +
                              ((fg >> s) & 255)*alpha)/15) << s for s in (0, 8, 16))
        assert got == expected, (address, got, expected)
    return dict(status='PASS', words=1024, sha256=audit.sha(path))


def descriptor_check():
    path = ROOT / ('sim/timing_descriptors_r4_sim_result.json' if SELECTED == 4
                   else 'sim/timing_descriptors_selected_r1_sim_result.json')
    result = audit.read(path)
    assert result['status'] == 'PASS'
    assert result['compile_exit_code'] == result['sim_exit_code'] == 0
    for p, digest in result['input_hashes'].items():
        assert audit.sha(Path(p)) == digest.lower(), p
    log = (ROOT / result['sim_log']).read_text(errors='replace')
    scenarios = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
    assert sorted(scenarios) == sorted(result['expected_scenarios'])
    assert len(scenarios) == len(set(scenarios)) == 3
    assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log
    commits = int(re.search(r'Descriptor commits checked: (\d+)', log)[1])
    assert commits == 1342
    return dict(status='PASS', evidence=path.relative_to(ROOT).as_posix(),
                scenarios=scenarios, commits=commits, source_pixel_phases=4,
                input_hashes_current=True, warning_lines=result.get('warning_lines', []))


def arb_check():
    path = ROOT / ('sim/timing_arb_r4_sim_result.json' if SELECTED == 4
                   else 'sim/timing_arb_selected_r1_sim_result.json')
    result = audit.read(path)
    assert result['status'] == 'PASS'
    assert result['compile_exit_code'] == result['sim_exit_code'] == 0
    for p, digest in result['input_hashes'].items():
        assert audit.sha(Path(p)) == digest.lower(), p
    # The reference must be the preserved pre-R2 implementation, apart from its name.
    reference = (ROOT / 'tb/timing_sdram_arb_reference.v').read_text(encoding='utf-8')
    original = (OUT / 'source_before_r2/rtl/mem/sdram_arb.v').read_text(encoding='utf-8')
    assert reference == original.replace('module sdram_arb #(', 'module timing_sdram_arb_reference #(')
    log = (ROOT / result['sim_log']).read_text(errors='replace')
    scenarios = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
    assert sorted(scenarios) == sorted(result['expected_scenarios'])
    assert len(scenarios) == len(set(scenarios)) == 3
    assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log
    cases = [dict(cap=int(c), cycles=int(n), transactions=int(t)) for c, n, t in
             re.findall(r'Arb reference cycles CAP=(\d+) cycles=(\d+) transactions=(\d+)', log)]
    assert len(cases) == 3 and sum(c['transactions'] for c in cases) == 129
    return dict(status='PASS', evidence=path.relative_to(ROOT).as_posix(),
                scenarios=scenarios, cases=cases, input_hashes_current=True,
                warning_lines=result.get('warning_lines', []))


def fft_check():
    evidence = {}
    for prefix, count in [('timing_fft_r4', 3), ('layer_fft64_r4', 7)]:
        path = ROOT / f'sim/{prefix}_sim_result.json'
        result = audit.read(path)
        assert result['status'] == 'PASS'
        assert result['compile_exit_code'] == result['sim_exit_code'] == 0
        for p, digest in result['input_hashes'].items():
            assert audit.sha(Path(p)) == digest.lower(), p
        log = (ROOT / result['sim_log']).read_text(errors='replace')
        scenarios = re.findall(r'SCENARIO_PASS\s+(\S+)', log)
        assert sorted(scenarios) == sorted(result['expected_scenarios'])
        assert len(scenarios) == len(set(scenarios)) == count
        assert len(re.findall(r'\bTEST_PASS\b', log)) == 1 and 'TEST_FAIL' not in log
        evidence[prefix] = dict(status='PASS', evidence=path.relative_to(ROOT).as_posix(),
            scenarios=scenarios, input_hashes_current=True,
            warning_lines=result.get('warning_lines', []))
        if prefix == 'timing_fft_r4':
            checks = int(re.search(r'FFT exact output comparisons: (\d+)', log)[1])
            assert checks == 1709568
            evidence[prefix]['exact_pixel_comparisons'] = checks
    reference = (ROOT / 'tb/timing_fft_reference.v').read_text(encoding='utf-8')
    original = (OUT / 'source_before_r4/rtl/gfx/layer_fft64.v').read_text(encoding='utf-8')
    assert reference == original.replace('module layer_fft64 (', 'module timing_fft_reference (')
    return evidence


def remaining_paths(tag):
    text = (ROOT / f'prj/td_build/{tag}/final_timing.rpt').read_text()
    result = []
    for section in re.split(r'(?=\nPath Group\s*:)', text):
        group = re.search(r'Path Group\s*:\s*(.+)', section)
        if not group or 'sdr_clk_sft' in group[1]:
            continue
        # Only max/setup paths; the tool limits the detailed list to 10/group.
        section = section.split('Min Paths')[0]
        for path in re.split(r'(?=^Slack\s*:)', section, flags=re.M):
            slack = re.search(r'^Slack\s*:\s*(-?[\d.]+)ns', path, re.M)
            if not slack or float(slack[1]) >= 0:
                continue
            def item(pattern):
                return re.search(pattern, path, re.M)[1]
            result.append(dict(group=group[1].strip(), slack_ns=float(slack[1]),
                start=item(r'^Begin Point\s*:\s*(.+?) \('),
                end=item(r'^End Point\s*:\s*(.+?) \('),
                delay=item(r'^Data Path Delay\s*:\s*(.+)')))
    return result


def main():
    global SELECTED, SYN, PHY
    selection = audit.read(OUT / 'selection.json')
    SELECTED = selection['selected_attempt']
    assert SELECTED in (1, 4), 'Review alternate selection before packaging'
    SYN = f'timingclean_r{SELECTED}_syn'
    PHY = f'timingclean_r{SELECTED}_congestion_seed3_phy'
    audit.RUNS = {}
    # Reuse only completed runs whose complete input hashes still match.
    for name in ('row', 'full_rows', 'core', 'layer', 'full_sdram',
                 'layout', 'layout_sdram', 'board', 'layout_pick', 'osd'):
        prefix = f'typography_{name}_'
        paths = sorted((ROOT / 'sim').glob(prefix+'*_sim_result.json'),
                       key=lambda p: p.stat().st_mtime, reverse=True)
        for path in paths:
            suffix = path.name[len(prefix):-len('_sim_result.json')]
            # Names such as layout and layout_sdram share a filename prefix.
            # Only explicit evidence suffixes may follow the complete check name.
            if suffix not in ['timingclean_selected_r1'] + [f'timingclean_r{i}' for i in range(1,5)]:
                continue
            result = audit.read(path)
            if (result.get('status') == ('COMPILE_PASS' if name == 'board' else 'PASS') and
                result.get('input_hashes') and all(
                    Path(p).is_file() and audit.sha(Path(p)) == digest.lower()
                    for p, digest in result['input_hashes'].items())):
                audit.RUNS[name] = suffix
                break
        assert name in audit.RUNS, f'No current evidence for {name}; run it before packaging'
    tests = audit.audit_tests()
    assert all(t['input_hashes_current'] for t in tests.values())
    palette, descriptors, arb = palette_check(), descriptor_check(), arb_check()
    fft = fft_check() if SELECTED == 4 else {}
    syn_inputs, syn_result = verify_build(SYN)
    phy_inputs, phy_result = verify_build(PHY)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] + '_syn' == SYN
    assert all(i['script_sha256'].lower() == audit.sha(ROOT / 'scripts/build.ps1')
               for i in (syn_inputs, phy_inputs))
    old_inputs = audit.read(ROOT / 'prj/td_build/lyricspace_r1_syn/inputs.json')
    old_hashes = {v['path']: v['sha256'].lower() for v in old_inputs['sources']}
    changed = sorted(Path(v['path']).relative_to(ROOT).as_posix()
                     for v in syn_inputs['sources']
                     if v['sha256'].lower() != old_hashes.get(v['path']))
    expected = ['rtl/gfx/layer_text_aa.v', 'rtl/gfx/osd_blend_palette.dath',
                'rtl/gfx/osd_layer_small.v', 'rtl/gfx/text_row_aa.v']
    if SELECTED == 4:
        expected += ['rtl/gfx/layer_fft64.v', 'rtl/gfx/lyric_pick.v', 'rtl/mem/sdram_arb.v']
    assert changed == sorted(expected), changed
    for v in syn_inputs['sources']:
        if Path(v['path']).suffix in ('.sdc', '.adc'):
            assert v['sha256'].lower() == old_hashes[v['path']], v['path']
    baseline, current = physical(BASE), physical(PHY)
    clean = current['setup_violations'] == current['hold_violations'] == 0
    regular = sum(g['setup_violations'] for n, g in current['groups'].items()
                  if 'sdr_clk_sft' not in n)
    paths = remaining_paths(PHY)
    assert len(paths) == regular, 'Detailed report must cover all remaining ordinary endpoints'
    raw = (ROOT / f'prj/td_build/{PHY}/console.log').read_bytes()
    console = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff'))
                         else 'utf-8', errors='replace')
    mslice, lslice = map(int, re.findall(r'(\d+) mslices, (\d+) lslices', console)[-1])
    assert max(mslice, lslice) <= 4900
    assert mslice + lslice == current['resources']['slices']
    current['slice_types'] = dict(mslice=mslice, lslice=lslice, each_limit=4900)
    target = OUT / 'audio_visual_timing_cleanup.bit'
    assert not target.exists(), 'Preserve existing delivery'
    shutil.copy2(phy_result['bitstream']['path'], target)
    assert audit.sha(target) == phy_result['bitstream']['sha256'].lower()
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        authorization='用户：违例太多了，消除一下', baseline_tag=BASE,
        synthesis_tag=SYN, physical_tag=PHY, synthesis_result=syn_result,
        tests=tests, palette=palette, descriptors=descriptors, arb=arb, fft=fft,
        simulation_scenario_count=sum(len(t['scenarios']) for t in tests.values())+(16 if fft else 6),
        selection=selection,
        attempts=[dict(tag=f'timingclean_r{i}_congestion_seed3_phy', selected=i==SELECTED,
                       result=physical(f'timingclean_r{i}_congestion_seed3_phy')) for i in range(1,5)],
        all_build_inputs_current=True, all_test_inputs_current=True,
        changed_build_sources=changed, constraints_unchanged=True,
        baseline=baseline, current=current, timing_clean=clean,
        non_shifted_setup_endpoints=regular,
        remaining_ordinary_paths=paths,
        bitstream=dict(path=str(target), bytes=target.stat().st_size, sha256=audit.sha(target)),
        warnings={tag: warning_lines(tag) for tag in (SYN, PHY)},
        synthesis_warning_added=list((Counter(warning_lines(SYN))-
                                      Counter(warning_lines('lyricspace_r1_syn'))).elements()),
        board_validation='not_run',
        limits=['Functional simulation is not post-route or analog CDC verification.',
                'SDRAM hard-IP shifted-clock paths remain checked and are not waived.'] if not clean else [])
    audit.write(OUT / 'verification_and_build.json', evidence)
    r, b = current['resources'], baseline['resources']
    extra_changes = [
        '选句槽校验改为全宽高位拒绝及10位有界加法；仲裁器发出字数计数器按MAX_BURST缩为最小位宽，'
        '保留请求接受、使能、地址和done时刻；高亮时间比较每拍登记，保留原消费拍。',
        '字库头四个32位合法性检查提前并行登记，利用RX→CHECK已有时钟，在HEADER消费，不增加取字周期。'
        '频谱将两次边界减法改为从固定底边计算坐标距离，保留原像素周期、柱高、颜色、亮边与爆点衰减。'
    ] if SELECTED == 4 else [
        '最终选择R1；已精确恢复R1综合manifest中的源码并逐项核对SHA256。'
        'R2/R3/R4的选句、仲裁器、字库头、频谱改动均保存在候选备份，不进入最终bit。'
    ]
    lines = ['# 时序优化结果', '',
        f'最终选择R{SELECTED}。', '',
        f"本轮综合、布局布线及bit生成完成。Setup违例端点 {baseline['setup_violations']} → {current['setup_violations']}，"
        f"hold违例 {current['hold_violations']}；非移相组剩余setup端点 {regular}。",
        '全局时序' + ('通过。' if clean else '仍未闭合，不能把bit生成或功能仿真通过写成时序通过。'), '',
        '## 修改与功能验证', '',
        'OSD末级实时RGB混色改为1024×32同步色表；保持三拍输出延迟、全部16级覆盖率、'
        '各层优先级以及逐通道精确颜色值。色表全1024项独立算式检查通过。',
        'GB2312合法性拆为高低字节并行登记，在原ADDRESS拍合并，不增加取字周期。'
        '描述符合法性在SDR源域登记后随原toggle稳定采样，保留全宽非法输入检查。',
        *extra_changes,
        '五行位置118/154/190/226/261、36/36/36/35行距、平滑滚动、横滚、完整7540字库及抗锯齿效果保持。',
        f"{evidence['simulation_scenario_count']}个自检场景及板级编译展开通过，源码/ROM/config哈希均为当前。",
        '包括OSD逐像素及延迟、全7540字、异常和恢复、五行快速像素参考、真实SDRAM争用；'
        '追加1342次描述符提交，覆盖四种源/像素相位、488字符边界、19/24长度上限、高位非法、vld=0及复位恢复。', '',
        '仲裁器与保存的R1 RTL对照129笔事务、三种MAX_BURST参数，逐拍核对全部输出；'
        '覆盖0..7及65535等长度、clamp、暂停恢复、地址回绕和同时请求。选句追加385组全宽边界及六槽验证。', '',
        ('最终频谱和保存的原RTL完成1,709,568次颜色/有效信号精确对照：全部256种level、全部256种strength分别扫描，'
        '覆盖距离分段和饱和边界、所有64×64柱号/中心组合、全部相位和使能、屏外坐标；'
        '另有7个非force场景验证bank交换、未初始化遮蔽、爆点和衰减。' if fft else
        'R4候选另通过1,709,568次频谱输出对照及7个bank/爆点场景；该候选未选中，'
        '其记录保留在sim/timing_fft_r4_sim_result.json和sim/layer_fft64_r4_sim_result.json，不算作当前源码测试。'), '',
        '## 实际布局资源', '', '|资源|修改前|本轮|变化|', '|---|---:|---:|---:|']
    for label, key, total in [('Slice','slices',9800),('LUT','lut',19600),('FF','registers',19600),
                             ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f'|{label}|{b[key]}/{total}|{r[key]}/{total}|{r[key]-b[key]:+d}|')
    lines += ['', f'MSlice {mslice}/4900、LSlice {lslice}/4900。以上均取最终物理报告，同一统计口径。', '',
              '## 布线后时序', '', '|路径组|原setup/ns|本轮setup/ns|原违例|本轮违例|本轮hold/ns|',
              '|---|---:|---:|---:|---:|---:|']
    for n, g in current['groups'].items():
        old = baseline['groups'][n]
        lines.append(f"|{n}|{old['setup_ns']:+.3f}|{g['setup_ns']:+.3f}|{old['setup_violations']}|{g['setup_violations']}|{g['hold_ns']:+.3f}|")
    lines += ['', f"全局setup WNS {current['setup_wns_ns']:+.3f}ns、TNS {current['setup_tns_ns']:.3f}ns；"
              f"hold WNS {current['hold_wns_ns']:+.3f}ns，STA覆盖率 {current['sta_coverage_percent']:.2f}%。",
              '控制50MHz、像素25MHz、SDRAM100MHz、HDMI串行125MHz。PLL、管脚和SDC均未改，未新增false path或multicycle。', '',
              '## 剩余负裕量路径', '']
    for n, g in current['groups'].items():
        if g['setup_violations']:
            lines += [f"- {n}：{g['setup_violations']}端点，最差 {g['setup_ns']:+.3f}ns；"
                      f"`{g['worst_start']}` → `{g['worst_end']}`。"]
    if paths:
        lines += ['', '全部剩余普通setup端点（含同一寄存器不同内部端点）：', '',
                  '|Slack/ns|起点|终点|数据路径|', '|---:|---|---|---|',
                  *[f"|{p['slack_ns']:.3f}|{p['start']}|{p['end']}|{p['delay']}|" for p in paths], '',
                  '后续普通路径优化应先降低拥塞与关键控制网扇出，释放布局空间；'
                  '本轮仅缩短局部算术链的三种尝试均引入了其他路径回退，不能继续盲目累加修改。']
    if not clean:
        lines += ['', '移相接口读取路径经过EG_PHY_SDRAM_2M_32硬宏及IO输入寄存器；'
                  '写入路径经过加密sdr_wrrd及IO三态驱动。这部分不是OSD或文字普通组合逻辑，'
                  '不能用同样的拆分方法直接改写。厂商参考也存在同类64端点只作对照，不构成时序豁免或稳定性证明。',
                  '保留板上已验证的100MHz/5ns相移；历史2.5ns曾出现整块读错，不能为报告好看盲扫相位。'
                  '后续须核实厂商SIP时序模型和加密控制器的实际DQ采样/输出使能关系，或更换可审计控制器再做接口验证。',
                  '本轮没有硬件电压/温度长期验证，没有下载或上板。']
    lines += ['', '## 产物和证据', '',
              f'- bit：{target.relative_to(ROOT).as_posix()}', f'- SHA256：{audit.sha(target)}',
              '- SD卡字库、歌词和图片无需更新。',
              f'- 布线报告：prj/td_build/{PHY}/final_timing.rpt',
              '- 结构化证据：output/timing_cleanup_20261030/verification_and_build.json',
              '- 修改前源码：output/timing_cleanup_20261030/source_before_r1/',
              '- 修改前R2源码：output/timing_cleanup_20261030/source_before_r2/',
              '- 修改前R3源码：output/timing_cleanup_20261030/source_before_r3/',
              '- 修改前R4源码：output/timing_cleanup_20261030/source_before_r4/',
              '- 所有旧bit和修复预算记录保留，本轮完成四次结构修改和四次物理实现，未盲扫种子或改相位。',
              '- 各轮结果以以下最终物理报告对照为准：', '',
              '|轮次|Setup端点|普通路径端点|TNS/ns|Slice|选择|', '|---|---:|---:|---:|---:|---|',
              *[f"|R{i}|{c['result']['setup_violations']}|{c['ordinary_endpoints']}|"
                f"{c['result']['setup_tns_ns']:.3f}|{c['result']['resources']['slices']}|"
                f"{'保留' if int(i)==SELECTED else '未选中'}|" for i,c in selection['candidates'].items()], '',
              '综合/物理告警完整记录于结构化证据。保留厂商SDRAM未驱动脚、FFT初始化及既有放置告警；'
              '新增u_palette bea/beb告警：RTL均接常量0，BYTE_ENABLE=0且双口写使能为0，'
              '属于只读ROM不使用的字节写掩码；综合将未驱动项置0。独立色表和逐像素仿真均已核对。', '']
    report = ROOT / 'doc/compile/timing_cleanup_report.md'
    report.write_text('\n'.join(lines), encoding='utf-8')
    if not clean:
        # Append to the historical repair log; preserve prior problem records.
        repair = ROOT / 'doc/compile/repair_report.md'
        marker = '## 2026-10-30 时序违例专项收敛'
        old = repair.read_text(encoding='utf-8') if repair.exists() else ''
        assert marker not in old
        repair.write_text(old+'\n\n'+marker+'\n\n'+
            f'最终选择R{SELECTED}；setup端点152→{current["setup_violations"]}，hold为0。'
            f'普通路径剩{regular}端点；全局WNS {current["setup_wns_ns"]:.3f}ns。\n\n'+
            '\n'.join(lines[lines.index('|轮次|Setup端点|普通路径端点|TNS/ns|Slice|选择|'):])+
            '\n\n本轮初次结构修改及3次自动重试已用尽。依据'
            '`C:/Users/Lenovo/.codex/skills/fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md`：'
            '“预算用尽写 doc/compile/repair_report.md，说明尝试、剩余错误、证据和下一步，停止自动重试。”'
            '\n\n停止自动修改/实现；没有新增例外、降低频率、调整PLL或下载。'
            '剩余普通路径按本轮timing_cleanup_report中的实际端点处理；'
            'SDRAM移相路径须核实厂商硬宏模型与DQ读/写/三态采样契约，再决定控制器结构，'
            '不能仅凭实板正常或厂商参考也报错予以豁免。'
            '\n\n完整报告：doc/compile/timing_cleanup_report.md；'
            '证据：output/timing_cleanup_20261030/verification_and_build.json。\n', encoding='utf-8')
    state_path = ROOT / 'doc/workflow/state.json'
    state = audit.read(state_path)
    status = 'completed_implementation' if clean else 'completed_implementation_timing_unmet'
    state.update(active_stage='timing_cleanup', status=status)
    state['timing_cleanup'].update(status=status, synthesis=SYN, physical=PHY,
        timing_clean=clean, setup_violations=current['setup_violations'],
        non_shifted_setup_endpoints=regular, hold_violations=current['hold_violations'],
        report=report.relative_to(ROOT).as_posix(),
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix(),
        bitstream=evidence['bitstream'], board_validation='not_run',
        stage='finished', selected_attempt=SELECTED, automatic_retry_budget_exhausted=not clean,
        next_step='Review remaining paths in timing_cleanup_report; verify SDRAM hard-IP interface timing model and sampling contract. Automatic retry budget exhausted.' if not clean
                  else 'Board verification.')
    audit.write(state_path, state)
    audit.write(ROOT / 'doc/workflow/quality_reports/timing_cleanup.json', dict(
        skill='fpga-workflow', status='completed' if clean else 'partial',
        files_written=changed+[report.relative_to(ROOT).as_posix(), target.relative_to(ROOT).as_posix()],
        missing_files=[], timing_clean=clean,
        verification_level='functional_simulation_and_routed_bitstream',
        reason=f"Setup endpoints {baseline['setup_violations']} -> {current['setup_violations']}; hold {current['hold_violations']}; board not run.",
        evidence=(OUT / 'verification_and_build.json').relative_to(ROOT).as_posix()))
    print(json.dumps(dict(resources=r, current=current, bitstream=evidence['bitstream'],
                          synthesis_warning_added=evidence['synthesis_warning_added']), indent=2))


if __name__ == '__main__':
    main()
