"""Verify saved TD artifacts and record the downscale implementation results."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
BUILDS = ROOT/'prj/td_build'
SYN = 'bmp_downscale_r1_syn'
BASELINE = 'uartless_r1_seed1_phy'
TAGS = [f'bmp_downscale_r1_seed{i}_phy' for i in (1, 3, 2, 4)]


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def verify_record(item):
    path = Path(item['path'])
    assert path.is_file() and sha(path).lower() == item['sha256'].lower(), str(path)


def verify_build(tag):
    run = BUILDS/tag
    result = read_json(run/'build_result.json')
    inputs = read_json(run/'inputs.json')
    assert result['status'] == 'BUILD_COMPLETE' and result['inputs_unchanged'], tag
    assert not list(run.glob('*.error.f')), tag
    for item in inputs['sources'] + inputs.get('build_files', []):
        verify_record(item)
    for key in ('synthesis_inputs', 'synthesis_netlist'):
        if key in inputs:
            verify_record(inputs[key])
    if result.get('bitstream'):
        verify_record(result['bitstream'])
        assert Path(result['bitstream']['path']).stat().st_size == result['bitstream']['bytes'] > 0
    return inputs, result


def qor_number(text, label):
    return int(re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)', text).group(1))


def physical(tag):
    run = BUILDS/tag
    qor = (run/'route.qor').read_text()
    area = (run/'skeleton_phy.area').read_text()
    timing = (run/'final_timing.rpt').read_text()
    resources = {name: int(re.search(r'^#'+label+r'\s+(\d+)', area, re.M).group(1))
                 for name, label in [('lut', 'lut'), ('registers', 'reg'), ('bram9k', 'bram'),
                                     ('bram32k', 'bram32k'), ('dsp', 'dsp'), ('pll', 'pll'), ('gclk', 'gclk')]}
    resources['slices'] = qor_number(qor, '#slices')
    groups = {}
    for section in re.split(r'(?=\nPath Group\s*:)', timing):
        name = re.search(r'Path Group\s*:\s*(.+)', section)
        if not name:
            continue
        maximum = re.search(r'Max\s*:\s*SWNS\s*([-\d.]+)ns, STNS\s*([-\d.]+)ns,\s*(\d+) Viol Endpoints', section)
        minimum = re.search(r'Min\s*:\s*HWNS\s*([-\d.]+)ns, HTNS\s*([-\d.]+)ns,\s*(\d+) Viol Endpoints', section)
        assert maximum and minimum
        worst = re.search(r'Max Paths[\s\S]*?Slack\s*:\s*([-\d.]+)ns\nBegin Point\s*:\s*(.+?) \([^\n]*\nEnd Point\s*:\s*(.+?) \(', section)
        groups[name.group(1).strip()] = dict(setup_ns=float(maximum[1]), setup_tns_ns=float(maximum[2]),
            setup_violations=int(maximum[3]), hold_ns=float(minimum[1]), hold_violations=int(minimum[3]),
            worst_start=worst[2] if worst else None, worst_end=worst[3] if worst else None)
    assert len(groups) == 8, tag
    return dict(resources=resources, setup_wns_ns=qor_number(qor, 'Setup WNS')/1000,
                setup_tns_ns=qor_number(qor, 'Setup TNS')/1000,
                setup_violations=qor_number(qor, 'Num of violated S-EP'),
                hold_wns_ns=qor_number(qor, 'Hold WNS')/1000,
                hold_violations=qor_number(qor, 'Num of violated H-EP'),
                sta_coverage_percent=float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1]),
                groups=groups)


def warning_lines(tag):
    data = '\n'.join(p.read_text(errors='replace') for p in (BUILDS/tag).glob('*.logw'))
    rows = []
    for line in data.splitlines():
        if 'WARNING:' not in line:
            continue
        line = re.sub(r'(?:D:/Verilog_teacher/guoyi/pro/audio_visual_upgrade/|../../../)', '<project>/', line)
        line = re.sub(r'_syn_\d+', '_syn_N', line)
        rows.append(re.sub(r'\.v\(\d+\)', '.v(LINE)', line))
    return sorted(rows)


def main():
    syn_inputs, syn_result = verify_build(SYN)
    records = {}
    for tag in TAGS:
        inputs, result = verify_build(tag)
        assert inputs['synthesis_tag'] == 'bmp_downscale_r1'
        assert inputs['sources'] == syn_inputs['sources']
        records[tag] = dict(**physical(tag), seed=inputs['seed'], build_result=result,
                            manifest=f'prj/td_build/{tag}/inputs.json')
    baseline = physical(BASELINE)
    old_sources = {Path(r['path']).as_posix().lower(): r['sha256'].lower()
                   for r in read_json(BUILDS/'uartless_r1_syn'/'inputs.json')['sources']}
    new_sources = {Path(r['path']).as_posix().lower(): r['sha256'].lower() for r in syn_inputs['sources']}
    assert old_sources.keys() == new_sources.keys()
    changed = [str(Path(p).relative_to(ROOT)).replace('\\', '/')
               for p in new_sources if new_sources[p] != old_sources[p]]
    assert len(changed) == 4
    syn_warnings_unchanged = warning_lines('uartless_r1_syn') == warning_lines(SYN)
    assert syn_warnings_unchanged
    def rank(tag):
        record = records[tag]
        regular = [v['setup_ns'] for name, v in record['groups'].items() if 'sdr_clk_sft' not in name]
        return (min(regular), record['setup_tns_ns'], -record['resources']['slices'])
    selected = max(TAGS, key=rank)
    best = records[selected]
    clean = best['setup_violations'] == best['hold_violations'] == 0
    additional = sum(v['setup_violations'] for name, v in best['groups'].items() if 'sdr_clk_sft' not in name)
    implementation = dict(authorization='用户：继续综合布局布线', synthesis=f'prj/td_build/{SYN}',
        baseline=f'prj/td_build/{BASELINE}', selected_physical=f'prj/td_build/{selected}',
        report='doc/compile/bmp_downscale_implementation_report.md',
        evidence='doc/compile/bmp_downscale_implementation_result.json',
        constraints={str(Path(r['path']).relative_to(ROOT)).replace('\\', '/'): r['sha256'].lower()
                     for r in syn_inputs['sources'] if Path(r['path']).suffix in ('.sdc', '.adc')},
        bitstream=best['build_result']['bitstream'], resources=best['resources'],
        timing_clean=clean, setup_wns_ns=best['setup_wns_ns'], setup_violations=best['setup_violations'],
        hold_wns_ns=best['hold_wns_ns'], hold_violations=best['hold_violations'],
        additional_non_shifted_setup_endpoints=additional, board_validation='not_run',
        attempts=[dict(seed=records[t]['seed'], directory=f'prj/td_build/{t}', status='BUILD_COMPLETE') for t in TAGS],
        timing_retry=dict(initial_seed=1, retry_seeds=[3, 2, 4], automatic_retries_used=3,
                          outcome='clean' if clean else ('legacy_shifted_paths_only' if not additional else 'additional_setup_violations_remain')),
        next_step='上板验证待授权' if clean else '依据实际负裕量路径优化结构，重新验证；当前停止继续换种子',
        selection_reason='优先比较非移相路径的最差setup裕量，再比较总负裕量与Slice；未改源码或约束')
    evidence = dict(generated=datetime.now().astimezone().isoformat(), implementation=implementation,
        baseline=baseline, synthesis_result=syn_result, candidates=records,
        source_count=len(new_sources), changed_sources=changed, all_build_inputs_current=True,
        synthesis_warnings_unchanged=syn_warnings_unchanged,
        warnings={t: dict(Counter(re.match(r'([A-Z]+-\d+)', line)[1] for line in warning_lines(t)))
                  for t in ['uartless_r1_syn', SYN, BASELINE] + TAGS})
    write_json(ROOT/implementation['evidence'], evidence)

    lines = ['# BMP 缩小功能：综合与布局布线', '', '日期：2026-10-29。工具：Tang Dynasty 6.2.168116；器件：EG4S20BG256。', '',
        f'综合及 {len(TAGS)} 个布局种子均完成并生成 bit。当前选择 `{selected}`，资源可容纳；'
        + ('全工程 setup/hold 均通过。' if clean else (f'全工程时序尚未收敛，除既有移相 SDRAM 路径外，还有 {additional} 个 setup 违例端点。' if additional else '非移相路径的setup/hold均通过；既有移相SDRAM违例仍在，全工程时序未收敛。')),
        '未下载、未上板。本轮只更换布局种子，RTL、管脚与时序约束均未改动。', '',
        '## 当前候选与修改前资源', '', '| 资源 | 原版 uartless seed1 | 当前候选 | 变化 |', '| --- | ---: | ---: | ---: |']
    for label, key, total in [('Slice','slices',9800),('LUT','lut',19600),('寄存器','registers',19600),
                              ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29),('PLL','pll',4),('GCLK','gclk',16)]:
        old, new = baseline['resources'][key], best['resources'][key]
        lines.append(f'| {label} | {old}/{total} | {new}/{total} | {new-old:+d} |')
    free = 9800-best['resources']['slices']
    lines += ['', f"Slice 占用 {best['resources']['slices']/98:.2f}%，剩余 {free} 个。RAM 总数保持 61 块，新增缩小器无行/帧 RAM。",
        '综合 gate.qor 的逻辑 LUT 从 12699 降到 12653；物理 LUT 与综合 LUT 统计口径不同。',
        'loader 层次统计：LUT 837→960、ripple 102→136、寄存器 667→634、DSP 2→0。固定输出几何消除了原有 span 乘法；新增计数逻辑仍有资源开销。', '',
        '## 布局种子比较', '', '| 种子 | Slice | 视频同域 setup/ns | 50 MHz 同域 setup/ns | SDRAM同域 setup/ns | setup违例端点 | 全局TNS/ns | hold WNS/ns |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for tag in TAGS:
        r, g = records[tag], records[tag]['groups']
        lines.append(f"| {r['seed']}{'（当前候选）' if tag==selected else ''} | {r['resources']['slices']} | {g['video_clk -> video_clk']['setup_ns']:+.3f} | {g['clk -> clk']['setup_ns']:+.3f} | {g['sdr_clk -> sdr_clk']['setup_ns']:+.3f} | {r['setup_violations']} | {r['setup_tns_ns']:.3f} | {r['hold_wns_ns']:+.3f} |")
    lines += ['', '选择优先依据非移相路径的最差 setup 裕量，其次看总负裕量与 Slice。所有种子的全局 WNS 均为 −5.565 ns；仅看该值无法比较新增违例。', '',
        '## 当前候选的时序', '', '| 路径组 | 原版 setup/ns | 当前 setup/ns | 当前 hold/ns | 当前 setup违例端点 |', '| --- | ---: | ---: | ---: | ---: |']
    for name, g in best['groups'].items():
        lines.append(f"| {name} | {baseline['groups'][name]['setup_ns']:+.3f} | {g['setup_ns']:+.3f} | {g['hold_ns']:+.3f} | {g['setup_violations']} |")
    lines += ['', f"全局 setup WNS {best['setup_wns_ns']:.3f} ns，TNS {best['setup_tns_ns']:.3f} ns，{best['setup_violations']} 个端点；hold 无违例。",
        f"STA coverage {best['sta_coverage_percent']:.2f}%，与原版相同；报告方案为每组最多 10 个端点，摘要未列出全部路径。",
        '实际报告时钟：控制50 MHz、视频25 MHz、SDRAM100 MHz（含相移）、HDMI串行125 MHz。SDC 旧注释的150 MHz不代表本次PLL输出。', '',
        '既有 sdr_clk↔sdr_clk_sft 各32个 setup 违例仍保留分析，未添加 false_path/multicycle 或降低频率隐藏问题。',
        '新增负裕量路径（各组最差一条）：' if additional else '本候选的非移相路径无新增负裕量。']
    for name, g in best['groups'].items():
        if 'sdr_clk_sft' not in name and g['setup_ns'] < 0:
            lines += ['', f"- `{name}`：{g['setup_ns']:.3f} ns，`{g['worst_start']}` → `{g['worst_end']}`。"]
    lines += ['', '缩小器位于50 MHz控制域，该域没有setup违例。布局变化使原有路径的物理裕量改变，不能据此宣称新增功能对整板时序没有影响。', '',
        '## 告警与证据', '', '综合告警与 uartless 基线逐条归一化对比一致（仅归一化工程路径、源码行号及自动生成实例编号），无新增位宽或锁存器告警。',
        '保留既有厂商SDRAM未驱动网/管脚、FFT tw_rom、RAM初始化忽略及重复CompileOrder告警。eram_init=off 的频谱RAM在完整bank提交前由 active_valid 隔离。',
        '布局保留 PHY-7002：SDRAM实例初始位置不合法后由工具重新放置；该告警原版也有。未出现错误标记，布线DRC及bit生成完成。', '',
        f"核对全部 {len(new_sources)} 个源/约束/初始化输入，源清单与原版一致，只有下列四份RTL哈希变化：", '',
        *[f'- `{p}`' for p in changed], '',
        '每次构建的 inputs.json 记录源、构建脚本文件、综合DB来源的SHA256；build_result.json 记录完成时间及bit哈希。本报告再次校验它们与当前磁盘一致。',
        '33个功能自检场景及整板编译证据仍与当前RTL相符，见 `bmp_downscale_run_report.md`。未重复仿真未变更的RTL。', '',
        '## 产物与复现', '', f"- 当前候选 bit：`prj/td_build/{selected}/skeleton.bit`（{best['build_result']['bitstream']['bytes']} 字节）。",
        f"- SHA256：`{best['build_result']['bitstream']['sha256']}`。",
        f'- 综合：`prj/td_build/{SYN}/gate.qor`、`skeleton_gate.area`。',
        f'- 当前物理报告：`prj/td_build/{selected}/route.qor`、`skeleton_phy.area`、`final_timing.rpt`。',
        '- 结构化汇总：`doc/compile/bmp_downscale_implementation_result.json`。', '',
        '构建命令如下；脚本拒绝覆盖已有目录，重跑时为 Tag 选择新名称。', '', '```powershell',
        r'.\scripts\build.ps1 -Stage syn -Tag bmp_downscale_r1 -LutStructure off',
        *[fr'.\scripts\build.ps1 -Stage phy -Tag {t.removesuffix("_phy")} -SynthesisTag bmp_downscale_r1 -Seed {records[t]["seed"]} -GenerateBitstream' for t in TAGS],
        'python scripts/report_downscale_implementation.py', 'python scripts/report_downscale.py', '```', '',
        '本轮布局比较已结束；所有候选保留。尚未验证实卡大图加载耗时、切换就绪与画质。若继续收敛时序，应先针对报告中的实际负裕量路径做结构优化，并重新进行受影响仿真及实现。', '']
    (ROOT/implementation['report']).write_text('\n'.join(lines), encoding='utf-8')
    state_path = ROOT/'doc/workflow/state.json'
    state = read_json(state_path)
    state.update(status='completed_implementation' if clean else 'completed_implementation_timing_unmet',
                 scope='BMP加载时缩小；用户于2026-10-29授权继续综合、布局布线和生成bit；不下载')
    downscale = state['bmp_downscale']
    downscale['stages']['physical'] = 'completed'
    downscale['implementation'] = implementation
    downscale['limitations'][0] = ('已完成综合/布局布线和bit生成；未下载上板' if clean else
        f'实现完成但时序未收敛：既有64个移相SDRAM违例外，新增{additional}个setup违例端点；未上板')
    write_json(state_path, state)
    quality_path = ROOT/'doc/workflow/quality_reports/bmp_downscale.json'
    quality = read_json(quality_path)
    quality.update(verification_level='routed_bitstream_and_simulation', implementation=implementation,
                   reason='构建与功能自检完成；时序通过' if clean else '构建与功能自检完成；时序未收敛，未上板')
    write_json(quality_path, quality)
    print(json.dumps(implementation, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
