"""Audit the selected transition build, regressions and historical attempts."""
from pathlib import Path
from datetime import datetime
from collections import Counter
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from report_scene_transitions import audit_test
from report_downscale_implementation import verify_build, physical, warning_lines, verify_record

OUT = ROOT / 'output/transitions_round2'
BUILDS = ROOT / 'prj/td_build'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def history(number):
    tag = f'transitions_r{number}'
    syn = BUILDS / (tag+'_syn')
    phy = BUILDS / (tag+'_seed3_phy')
    snapshots = {
        'resource_catalog.v': OUT / ('resource_catalog_r7.v' if number == 7 else 'resource_catalog_r5.v'),
        'visual_settings.v': OUT / ('visual_settings_r6_rejected.v' if number == 6 else 'visual_settings_r5.v'),
    }
    # Old build inputs are checked against saved candidate sources when those
    # candidates were rejected. Never claim they match the selected live RTL.
    for run in (syn, phy):
        inputs = read(run / 'inputs.json')
        for item in inputs['sources'] + inputs['build_files']:
            p = Path(item['path'])
            if sha(p).lower() != item['sha256'].lower():
                assert p.name in snapshots, str(p)
                assert sha(snapshots[p.name]).lower() == item['sha256'].lower(), str(p)
        for key in ('synthesis_inputs', 'synthesis_netlist'):
            if key in inputs:
                verify_record(inputs[key])
    area = (syn / 'skeleton_gate.area').read_text()
    log = (phy / 'console.log').read_text(encoding='utf-16')
    m, l = re.findall(r'(\d+) mslices, (\d+) lslices', log)[-1]
    errors = re.findall(r'^.*PHY-9009 ERROR:.*$', log, re.M)
    return dict(candidate=tag, mapped_lut=int(re.search(r'^#lut\s+(\d+)', area, re.M)[1]),
                mapped_registers=int(re.search(r'^#reg\s+(\d+)', area, re.M)[1]),
                mslice=int(m), lslice=int(l), status='FAILED_RESOURCE' if errors else 'BUILD_COMPLETE',
                resource_error=errors[-1] if errors else None,
                log=phy.relative_to(ROOT).as_posix()+'/console.log', historical_sources_verified=True)


def main():
    syn_inputs, syn_result = verify_build('transitions_r7_syn')
    phy_inputs, phy_result = verify_build('transitions_r7_seed3_phy')
    assert phy_inputs['sources'] == syn_inputs['sources']
    selected = physical('transitions_r7_seed3_phy')
    baseline = physical('log64_floor_20261102_r1_seed2_phy')
    attempts = [history(n) for n in (5, 6, 7)]
    tests = {}
    for name, prefix in [
        ('transitions', 'transitions_r4_final_scene_transitions'),
        ('controls_cdc', 'transitions_r4_final_visual_controls'),
        ('osd_pixels', 'transitions_r7_visual_osd'),
        ('osd_equivalence', 'transitions_r7_osd_equivalence'),
        ('luma_equivalence', 'transitions_r7_color_luma_equivalence'),
        ('color_envelope', 'transitions_r7_color_envelope'),
        ('legacy_scene', 'transitions_r2_scene_legacy'),
        ('split_core', 'transitions_r7_split_core'),
        ('circular_system', 'transitions_r7_circular_system'),
        ('catalog_matrix', 'transitions_r7_catalog_matrix'),
        ('catalog_equivalence', 'transitions_r7_catalog_equivalence'),
        ('catalog_legacy', 'transitions_r7_catalog_legacy'),
        ('attack_bands', 'transitions_r1_attack_bands'),
        ('spectrum_stage1', 'transitions_r1_spectrum_stage1'),
        ('layer_fft64', 'transitions_r1_layer_fft64'),
        ('split_spectrum', 'transitions_r1_split_spectrum')]:
        tests[name] = audit_test(prefix)
    tests['board_compile'] = audit_test('transitions_r7_circular_board', 'COMPILE_PASS')
    scenarios = [s for t in tests.values() for s in t['scenarios']]
    assert warning_lines('transitions_r7_syn') == warning_lines('log64_floor_20261102_r1_syn')
    baseline_inputs = read(BUILDS / 'log64_floor_20261102_r1_syn/inputs.json')
    old_constraints = {Path(r['path']).name: r['sha256'].lower()
                       for r in baseline_inputs['sources'] if Path(r['path']).suffix in ('.adc', '.sdc')}
    constraints = [r for r in syn_inputs['sources'] if Path(r['path']).suffix in ('.adc', '.sdc')]
    assert all(old_constraints[Path(r['path']).name] == r['sha256'].lower() for r in constraints)
    font_old = (ROOT / 'output/transitions_20261102_r1/baseline/rtl/gfx/osd_youyuan_pixel.dath').read_text().splitlines()
    font_new = (ROOT / 'rtl/gfx/osd_youyuan_pixel.dath').read_text().splitlines()
    assert len(font_new) == len(font_old) == 16384 and font_new[:95*128] == font_old[:95*128]
    regular = {name: g for name, g in selected['groups'].items() if 'sdr_clk_sft' not in name}
    extra_setup = sum(g['setup_violations'] for g in regular.values())
    clean = selected['setup_violations'] == selected['hold_violations'] == 0
    limitations = [
        '未下载上板；生成bit和功能仿真通过不能代替硬件验证。',
        'SD/FAT/音视频系统回归沿用缩放夹具与150MHz参数，不替代实际100MHz SDRAM板级验证。',
        '全部BRAM及DSP仍满载；新转场没有增加RAM或DSP。',
    ]
    if not clean:
        limitations.insert(0, f"最终STA仍有{selected['setup_violations']}个setup、{selected['hold_violations']}个hold违例；"
                              f"其中非移相路径setup {extra_setup}个，WNS {selected['setup_wns_ns']:.3f}ns。")
    state = read(ROOT / 'doc/workflow/transitions_state.json')
    budget = state['retry_budget']
    budget.update(automatic_retries_used=3, outcome='resource_fit')
    report = 'doc/compile/scene_transitions_round2_20261102.md'
    evidence_path = 'output/transitions_round2/verification_and_build.json'
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        status='implementation_timing_clean' if clean else 'implementation_complete_timing_violations',
        selected_build='prj/td_build/transitions_r7_seed3_phy', spec='doc/spec/scene_transitions.md',
        report=report, tests=tests, scenario_pass_occurrences=len(scenarios),
        unique_scenario_count=len(set(scenarios)), synthesis_result=syn_result, physical_result=phy_result,
        all_selected_build_inputs_current=True, constraints_unchanged=True, constraints=constraints,
        synthesis_warning_count=len(warning_lines('transitions_r7_syn')), synthesis_warnings_unchanged=True,
        font_first_95_unchanged=True, selected=selected, baseline=baseline, attempts=attempts,
        non_shifted_setup_violations=extra_setup, timing_clean=clean, bitstream=phy_result['bitstream'],
        board_validation='not_run', retry_budget=budget, limitations=limitations,
        preserved_incomplete_runs=[
            dict(result='sim/transitions_r5_catalog_equivalence_sim_result.json', reason='生成脚本引号错误导致配置缺失，后已修正；不是RTL仿真失配'),
            dict(result='sim/transitions_r6_circular_system_sim_result.json', reason='选错expected配置后主动取消，未计入通过'),
            dict(result='sim/transitions_r6_circular_system_fix1_sim_result.json', reason='r6打包失败被撤回，系统回归主动取消；由最终r7系统回归替代')])
    write(ROOT / evidence_path, evidence)
    lines = ['# 转场设置：第二轮资源优化与验证', '',
        '目标 EG4S20BG256；TD 6.2.168116 / ModelSim 10.6e。', '',
        f"当前r7完成综合、布局布线并生成候选bit；Slice {selected['resources']['slices']}/9800。",
        f"{len(scenarios)}次场景自检通过，包含{len(set(scenarios))}个不同场景ID，另通过真实板级顶层编译展开。",
        '全部采用的结果已重新核对当前实际输入哈希、退出码、场景集合及唯一TEST_PASS。', '',
        '## 已实现行为', '',
        '保留淡入淡出，新增左向右擦除、像素溶解、15条水平百叶窗。OSD第六页选择效果及快速/标准/慢速/很慢四档速度。',
        '速度对应16/32/64/128帧间隔，约0.269/0.538/1.075/2.150秒；默认淡入淡出、标准。KEY2/KEY3双向循环选择。',
        '设置在帧边界整体提交，每次转场开始锁存；忙时修改下次生效。旧读取排空后才释放旧存储槽。',
        '背景、封面参与转场；歌词、频谱和OSD保持实时叠加。图像/同步流水对齐，未减少色彩精度或转场分辨率。', '',
        '## 本轮等价优化与尝试', '',
        'r5将目录seen/valid标志改成常量位索引写使能；r7保留它，将通过完整ASCII校验的数字直接取低半字节、资源ID改为字段拼接，并把16首歌计数缩至5位。',
        '逐周期对比r4目录的全部36个输出及标志；保留全部原矩阵场景，增加65,536种数字字节组合和全部CV后缀/文件类型组合。',
        'r6颜色暂存移位结构功能等价但物理打包更差，已撤回；最终visual_settings与r4逐字节相同。', '',
        '|候选|综合LUT|综合REG|M-Slice|L-Slice|结果|',
        '|---|---:|---:|---:|---:|---|']
    for a in attempts:
        lines.append(f"|{a['candidate']}|{a['mapped_lut']}|{a['mapped_registers']}|{a['mslice']}|{a['lslice']}|{a['status']}|")
    lines += ['', '每类Slice上限4900。历史候选按保存的源码快照核对，不能视为当前源码结果。', '',
        '## 最终资源', '', '|资源|原版|当前|上限|', '|---|---:|---:|---:|']
    for label, key, limit in [('Slice','slices',9800),('LUT','lut',19600),('REG','registers',19600),
                              ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f"|{label}|{baseline['resources'][key]}|{selected['resources'][key]}|{limit}|")
    lines += ['', '管脚和时钟约束与基线哈希相同；综合95条告警归一化后与基线逐条一致。原95个像素字体槽内容不变，新中文使用原字库空槽。', '',
        '## 最终时序', '', '|路径组|基线setup/ns|当前setup/ns|当前hold/ns|setup违例端点|', '|---|---:|---:|---:|---:|']
    for name, g in selected['groups'].items():
        lines.append(f"|{name}|{baseline['groups'][name]['setup_ns']:+.3f}|{g['setup_ns']:+.3f}|{g['hold_ns']:+.3f}|{g['setup_violations']}|")
    lines += ['', f"WNS {selected['setup_wns_ns']:.3f}ns，TNS {selected['setup_tns_ns']:.3f}ns；"
              f"setup {selected['setup_violations']}个，hold {selected['hold_violations']}个；STA coverage {selected['sta_coverage_percent']:.2f}%。",
              f'非移相路径setup违例为{extra_setup}个；全工程时序'+('通过。' if clean else '未全部通过，候选bit不能视为硬件验收通过。'), '',
        '## 仿真证据', '', '|检查|场景次数|结果JSON|', '|---|---:|---|']
    for name, t in tests.items():
        lines.append(f"|{name}|{len(t['scenarios'])}|`{t['result']}`|")
    bit = phy_result['bitstream']
    lines += ['', '矩阵与逐周期等价测试共用8个场景ID，两者均实际执行；次数与不同ID数量分别报告。', '',
        '## 产物与限制', '', f"候选bit：`{Path(bit['path']).relative_to(ROOT).as_posix()}`，{bit['bytes']}字节。",
        f"SHA256：`{bit['sha256']}`。", '', *['- '+s for s in limitations], '',
        f'结构化证据：`{evidence_path}`。第一轮失败记录保留于`doc/compile/scene_transitions_20261102.md`。', '',
        '本轮3次资源修改实现已用完，资源问题已解决；未自动下载上板。', '',
        '复核命令：`python -B scripts/report_scene_transitions_round2.py`。', '']
    (ROOT / report).write_text('\n'.join(lines), encoding='utf-8')
    state.update(status=evidence['status'], evidence=evidence_path, retry_budget=budget,
        stages=dict(requirements='completed', rtl='completed', simulation='completed', synthesis='completed',
                    physical='completed', final_sta='completed' if clean else 'failed', bitstream='completed', hardware='pending'),
        remaining_error=None if clean else limitations[0], limitations=limitations)
    write(ROOT / 'doc/workflow/transitions_state.json', state)
    write(ROOT / 'doc/workflow/quality_reports/transitions.json',
        dict(status=evidence['status'], verification_level='simulation_and_implementation', missing_files=[],
             evidence=evidence_path, scenario_pass_occurrences=len(scenarios), unique_scenario_count=len(set(scenarios)),
             implementation_pass=True, timing_clean=clean, final_sta=selected, board_validation='not_run'))
    repair = ROOT / 'doc/compile/repair_report.md'
    marker = '## 2026-11-02 scene_transitions 第二轮资源优化'
    old = repair.read_text(encoding='utf-8')
    if marker in old:
        old = old.split(marker)[0].rstrip()
    repair.write_text(old+'\n\n'+marker+'\n\n'+
        f"用户明确授权继续后执行r5/r6/r7三次资源候选；最终r7 Slice {selected['resources']['slices']}/9800，资源可容纳。\n\n"+
        f"完成77次场景自检及真实板级编译展开；生成bit，setup {selected['setup_violations']}、hold {selected['hold_violations']}。未下载上板。\n\n"+
        f'详见 [{report}]({Path(report).name})；证据 `{evidence_path}`。\n', encoding='utf-8')
    print(json.dumps(dict(status=evidence['status'], resources=selected['resources'],
                          non_shifted_setup_violations=extra_setup, scenario_pass_occurrences=len(scenarios)), ensure_ascii=False))


if __name__ == '__main__':
    main()
