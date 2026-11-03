"""Audit the selected live RTL and preserve rejected timing candidates honestly."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from report_scene_transitions import audit_test
from report_downscale_implementation import verify_build, verify_record, physical, warning_lines

OUT = ROOT / 'output/transitions_timing'
BUILDS = ROOT / 'prj/td_build'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().lower()


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def audit_historical_record(item, version):
    p = Path(item['path'])
    if sha(p) == item['sha256'].lower():
        return
    assert p.name == 'layer_text_aa.v', str(p)
    assert sha(OUT / f'layer_text_aa_r{version}.v') == item['sha256'].lower(), str(p)


def historical_build(tag, version):
    run = BUILDS / tag
    manifest = read(run / 'inputs.json')
    for item in manifest['sources'] + manifest['build_files']:
        audit_historical_record(item, version)
    for key in ('synthesis_inputs', 'synthesis_netlist'):
        if key in manifest:
            verify_record(manifest[key])
    syn = read(Path(manifest['synthesis_inputs']['path']))
    assert syn['sources'] == manifest['sources']
    for item in syn['sources'] + syn['build_files']:
        audit_historical_record(item, version)
    log = (run / 'console.log').read_text(encoding='utf-16')
    counts = re.findall(r'(\d+) mslices, (\d+) lslices', log)
    errors = re.findall(r'^.*PHY-9009 ERROR:.*$', log, re.M)
    result = dict(tag=tag, source_snapshot=f'output/transitions_timing/layer_text_aa_r{version}.v',
                  recorded_inputs_verified=True, status='FAILED_RESOURCE' if errors else 'BUILD_COMPLETE',
                  mslice=int(counts[-1][0]), lslice=int(counts[-1][1]), errors=errors)
    if (run / 'build_result.json').exists():
        build_result = read(run / 'build_result.json')
        assert build_result['status'] == 'BUILD_COMPLETE' and build_result['inputs_unchanged']
        verify_record(build_result['bitstream'])
        result.update(physical=physical(tag), build_result=build_result)
    else:
        assert errors, tag
    return result


def historical_test(prefix, version):
    path = ROOT / 'sim' / (prefix+'_sim_result.json')
    result = read(path)
    assert result['status'] in ('PASS', 'COMPILE_PASS'), prefix
    assert result['compile_exit_code'] == 0
    for name, digest in result['input_hashes'].items():
        p = Path(name)
        if not p.is_absolute():
            p = ROOT / p
        audit_historical_record(dict(path=str(p), sha256=digest), version)
    if result['status'] == 'PASS':
        assert result['sim_exit_code'] == 0
        log = (ROOT / result['sim_log']).read_text()
        scenarios = re.findall(r'^#?\s*SCENARIO_PASS (\S+)\s*$', log, re.M)
        assert len(scenarios) == len(set(scenarios))
        assert set(scenarios) == set(result['expected_scenarios'])
        assert len(re.findall(r'^#?\s*TEST_PASS\s*$', log, re.M)) == 1
        assert not re.search(r'^#?\s*TEST_FAIL', log, re.M)
    return dict(result=path.relative_to(ROOT).as_posix(), sha256=sha(path),
                status=result['status'], historical_inputs_verified=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--selected', choices=('r7', 'r9'), required=True)
    args = parser.parse_args()
    version = int(args.selected[1:])
    tag = f'transitions_{args.selected}'
    assert sha(ROOT / 'rtl/gfx/layer_text_aa.v') == sha(OUT / f'layer_text_aa_{args.selected}.v')
    syn_inputs, syn_result = verify_build(tag+'_syn')
    phy_inputs, phy_result = verify_build(tag+'_seed3_phy')
    assert phy_inputs['sources'] == syn_inputs['sources']
    selected = physical(tag+'_seed3_phy')
    old = read(OUT / 'r7_resource_fit_evidence.json')
    tests = {}
    affected = {'luma_equivalence':'color_luma_equivalence', 'color_envelope':'color_envelope',
                'split_core':'split_core', 'circular_system':'circular_system', 'board_compile':'circular_board'}
    for name, record in old['tests'].items():
        prefix = Path(record['result']).name.removesuffix('_sim_result.json')
        if version == 9 and name in affected:
            prefix = tag+'_'+affected[name]
        tests[name] = audit_test(prefix, record['status'])
    if version == 9:
        for suffix in ('marquee_equivalence', 'typography_layer', 'circular_text_sdram', 'split_text_sdram'):
            tests[suffix] = audit_test(tag+'_'+suffix)
    attempts = [historical_build(t, v) for t,v in (
        ('transitions_r7_seed3_phy',7), ('transitions_r7_seed2_phy',7),
        ('transitions_r8_seed3_phy',8), ('transitions_r9_seed3_phy',9))]
    historical = [historical_test(f'transitions_r{v}_'+s,v) for v in (8,9) for s in (
        'marquee_equivalence','typography_layer','circular_text_sdram','split_text_sdram',
        'color_luma_equivalence','color_envelope','split_core','circular_board','circular_system')]
    warnings = warning_lines(tag+'_syn')
    assert warnings == warning_lines('log64_floor_20261102_r1_syn')
    base_manifest = read(BUILDS / 'log64_floor_20261102_r1_syn/inputs.json')
    constraints = {Path(r['path']).name: r['sha256'].lower()
                   for r in syn_inputs['sources'] if Path(r['path']).suffix in ('.adc','.sdc')}
    base_constraints = {Path(r['path']).name: r['sha256'].lower()
                        for r in base_manifest['sources'] if Path(r['path']).suffix in ('.adc','.sdc')}
    assert constraints == base_constraints
    baseline = physical('log64_floor_20261102_r1_seed2_phy')
    regular = {n:g for n,g in selected['groups'].items() if 'sdr_clk_sft' not in n}
    extra = sum(g['setup_violations'] for g in regular.values())
    clean = selected['setup_violations'] == selected['hold_violations'] == 0
    scenarios = [s for t in tests.values() for s in t['scenarios']]
    state = read(ROOT / 'doc/workflow/transitions_state.json')
    budget = state['timing_retry_budget']
    budget.update(automatic_retries_used=3, outcome='timing_clean' if clean else
                  'legacy_shifted_paths_only' if extra == 0 else 'exhausted', attempts=attempts)
    limitations = [f"最终STA setup {selected['setup_violations']}个、hold {selected['hold_violations']}个违例；"
                  f"其中普通路径setup {extra}个，WNS {selected['setup_wns_ns']:.3f}ns。",
                  *old['limitations'][1:]]
    evidence_path = 'output/transitions_timing/verification_and_build.json'
    report_path = 'doc/compile/scene_transitions_timing_20261102.md'
    status = 'implementation_timing_clean' if clean else 'implementation_complete_timing_violations'
    evidence = dict(generated=datetime.now().astimezone().isoformat(), status=status,
        selected_build=f'prj/td_build/{tag}_seed3_phy', selected=selected, baseline=baseline,
        r7=old['selected'], attempts=attempts, tests=tests, historical_tests=historical,
        synthesis_result=syn_result, physical_result=phy_result, bitstream=phy_result['bitstream'],
        all_selected_build_inputs_current=True, constraints_unchanged=True,
        synthesis_warnings_unchanged=True, synthesis_warning_count=len(warnings),
        scenario_pass_occurrences=len(scenarios), unique_scenario_count=len(set(scenarios)),
        non_shifted_setup_violations=extra, timing_clean=clean, limitations=limitations,
        timing_retry_budget=budget, report=report_path, prior_resource_evidence=old['report'])
    write(ROOT / evidence_path, evidence)
    state.update(status=status, evidence=evidence_path, remaining_error='' if clean else limitations[0],
                 limitations=limitations, selected_build=evidence['selected_build'])
    state['stages'].update(simulation='completed',synthesis='completed',physical='completed',
                           final_sta='completed' if clean else 'failed',bitstream='completed',hardware='pending')
    write(ROOT / 'doc/workflow/transitions_state.json', state)
    quality = read(ROOT / 'doc/workflow/quality_reports/transitions.json')
    quality.update(status=status,evidence=evidence_path,scenario_pass_occurrences=len(scenarios),
        unique_scenario_count=len(set(scenarios)),implementation_pass=True,timing_clean=clean,
        final_sta=selected,limitations=limitations,timing_retry_budget=budget)
    write(ROOT / 'doc/workflow/quality_reports/transitions.json', quality)
    lines = ['# 转场功能：时序优化与最终候选', '',
        f"当前选择{args.selected}；Slice {selected['resources']['slices']}/9800。",
        f"{len(scenarios)}次场景自检通过（{len(set(scenarios))}个不同场景），另通过实际板级顶层编译展开。",
        '已审计实际输入哈希、退出码、场景集合和唯一TEST_PASS。功能及资源优化经过见 [第二轮报告](scene_transitions_round2_20261102.md)。', '',
        '保留淡入淡出，新增擦除、溶解、百叶窗；OSD第六页设置效果及快速/标准/慢速/很慢。',
        '四档为16/32/64/128帧间隔，约0.269/0.538/1.075/2.150秒；默认淡入淡出、标准。',
        '设置在帧边界提交并在转场开始锁存；背景/封面参与转场，歌词、频谱、OSD继续实时叠加。', '',
        '## 本轮改动', '',
        'r7种子3新增的30个普通setup端点主要经过歌名/歌手滚动回绕计算。种子2打包失败。',
        'r8在行渲染完成时预计算并保存回绕边界，功能回归通过，但M/L-Slice为4902/4903，无法采用。',
        'r9仅缓存可达回绕边界的变化位，恒定高位由连线恢复；另保存宽文字与可回绕标志。',
        'r9综合LUT降至17688、REG为11784，但最终打包4956/4956，未进入布线，不能以综合面积替代物理资源结果。',
        '当前BOX_W=448时可达边界为896..1023，只存7个低位；边界超出1023时继续保持原10位偏移自然溢出的行为。',
        '与冻结的r7真实AA模块逐周期对比，覆盖全部1024种宽度、边界前后偏移、溢出、停顿、采样间隔、同时完成/切歌/复位优先级；9组参数包括默认1200/24000。',
        ('r9已采用，以上优化保留在当前RTL。' if version == 9 else 'r9未采用，当前RTL已还原为资源可容纳且回归通过的r7。'), '',
        '## 实现尝试', '', '|候选|M-Slice|L-Slice|结果|普通setup端点|', '|---|---:|---:|---|---:|']
    for a in attempts:
        ordinary = sum(g['setup_violations'] for n,g in a.get('physical',{}).get('groups',{}).items()
                       if 'sdr_clk_sft' not in n) if 'physical' in a else '-'
        lines.append(f"|{a['tag']}|{a['mslice']}|{a['lslice']}|{a['status']}|{ordinary}|")
    lines += ['', '每类Slice上限4900。失败候选与其源码快照、日志均保留。', '',
              '## 当前资源与时序', '', '|资源|原版|r7|当前|上限|', '|---|---:|---:|---:|---:|']
    for name,key,total in [('Slice','slices',9800),('LUT','lut',19600),('REG','registers',19600),
                           ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f"|{name}|{baseline['resources'][key]}|{old['selected']['resources'][key]}|{selected['resources'][key]}|{total}|")
    lines += ['', '|路径组|r7 setup/ns|当前setup/ns|当前hold/ns|当前setup端点|', '|---|---:|---:|---:|---:|']
    for name,g in selected['groups'].items():
        lines.append(f"|{name}|{old['selected']['groups'][name]['setup_ns']:+.3f}|{g['setup_ns']:+.3f}|{g['hold_ns']:+.3f}|{g['setup_violations']}|")
    lines += ['', limitations[0], f"TNS {selected['setup_tns_ns']:.3f}ns，STA coverage {selected['sta_coverage_percent']:.2f}%。",
        '综合95条告警归一化后与原版一致；管脚、时钟和时序约束哈希与原版相同。',
        '未降低频率、增加false_path/multicycle或修改PLL；SDRAM双向移相路径仍按真实报告列出。', '',
        '## 采用的功能验证', '', '|检查|场景次数|结果|', '|---|---:|---|']
    for name,t in tests.items():
        lines.append(f"|{name}|{len(t['scenarios'])}|[{t['status']}](../../{t['result']})|")
    lines += ['', '## 产物与限制', '', f"- 候选bit：`{phy_result['bitstream']['path']}`。",
        f"- SHA256：`{phy_result['bitstream']['sha256']}`。",
        f'- 结构化证据：`{evidence_path}`。', *['- '+s for s in limitations[1:]], '',
        '## 重试预算', '',
        '本轮时序预算源于r7首次装入芯片后获得的新STA证据：种子2、r8预计算、r9压缩边界共3次自动重跑。',
        f"结果：{budget['outcome']}。原资源优化预算未重置。",
        '依据 [规则50](C:/Users/Lenovo/.codex/skills/fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md)：',
        '> 预算用尽写 doc/compile/repair_report.md，说明尝试、剩余错误、证据和下一步，停止自动重试。',
        '本轮停止自动修改和更换种子。下一轮应先针对r7的ws→hold_empty/hold_count/off_s实际路径，尝试更小的滚动判定控制结构，维持同拍采样和行完成优先级。',
        'r8虽仅超2个M-Slice、3个L-Slice，但尚无最终STA；不能据此认为它时序已修复。继续需要明确授权新一轮，并保留独立等价/文字/SDRAM回归。',
        '原64个SDRAM移相违例还须核实厂商硬宏模型与读写/三态采样契约；不能仅凭原版也存在而豁免。', '']
    (ROOT / report_path).write_text('\n'.join(lines),encoding='utf-8')
    repair = ROOT / 'doc/compile/repair_report.md'
    heading = '## 2026-11-02 scene_transitions 时序优化'
    previous = repair.read_text(encoding='utf-8').split(heading)[0].rstrip()
    repair.write_text(previous+'\n\n'+heading+'\n\n'+
        f"当前{args.selected}，Slice {selected['resources']['slices']}/9800；{limitations[0]}\n\n"+
        '本轮3次自动重跑已完成，停止自动结构修改和换种子；原资源预算不重置。\n\n'+
        f'详见 [{report_path}]({Path(report_path).name})；证据 `{evidence_path}`。\n',encoding='utf-8')
    print(json.dumps(dict(selected=args.selected,scenarios=len(scenarios),resources=selected['resources'],
                         ordinary_setup=extra,timing_clean=clean,report=report_path),ensure_ascii=False))


if __name__ == '__main__':
    main()
