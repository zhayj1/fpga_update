"""Audit transition evidence without modifying RTL, tests, or existing reports."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from report_downscale_implementation import verify_build, physical, warning_lines, verify_record

OUT = ROOT / 'output/transitions_20261102_r1'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def audit_test(prefix, status='PASS'):
    path = ROOT / 'sim' / (prefix + '_sim_result.json')
    data = read(path)
    assert data['status'] == status, (prefix, data['status'])
    assert data['compile_exit_code'] == 0
    assert status == 'COMPILE_PASS' or data['sim_exit_code'] == 0
    # ModelSim records actual sources, includes, images, configuration and runner.
    # Audit every recorded input; unrelated files do not invalidate old evidence.
    for name, digest in data['input_hashes'].items():
        p = Path(name)
        if not p.is_absolute():
            p = ROOT / p
        assert p.is_file() and sha(p) == digest, (prefix, name)
    log = (ROOT / (data['sim_log'] or data['compile_log'])).read_text(encoding='utf-8', errors='replace')
    scenarios = re.findall(r'^#?\s*SCENARIO_PASS (\S+)\s*$', log, re.M)
    if status == 'PASS':
        assert len(scenarios) == len(set(scenarios))
        assert set(scenarios) == set(data['expected_scenarios'])
        assert len(re.findall(r'^#?\s*TEST_PASS\s*$', log, re.M)) == 1
        assert not re.search(r'^#?\s*TEST_FAIL', log, re.M)
    return dict(status=status, result=path.relative_to(ROOT).as_posix(), sha256=sha(path),
                scenarios=scenarios, current_recorded_inputs_verified=True,
                compile_log=data['compile_log'], sim_log=data['sim_log'],
                started_at=data['started_at'], finished_at=data['finished_at'],
                warning_lines=data.get('warning_lines', []), tool_version=data['tool_version'])


def main():
    tests = {}
    for name, prefix in [
        ('transitions', 'transitions_r4_final_scene_transitions'),
        ('controls_cdc', 'transitions_r4_final_visual_controls'),
        ('osd_pixels', 'transitions_r4_final_visual_osd'),
        ('osd_equivalence', 'transitions_r4_osd_equivalence'),
        ('luma_equivalence', 'transitions_r4_color_luma_equivalence_fix1'),
        ('color_envelope', 'transitions_r4_final_color_envelope'),
        ('legacy_scene', 'transitions_r2_scene_legacy'),
        ('split_core', 'transitions_r4_split_core'),
        ('circular_system', 'transitions_r4_circular_system'),
        ('attack_bands', 'transitions_r1_attack_bands'),
        ('spectrum_stage1', 'transitions_r1_spectrum_stage1'),
        ('layer_fft64', 'transitions_r1_layer_fft64'),
        ('split_spectrum', 'transitions_r1_split_spectrum')]:
        tests[name] = audit_test(prefix)
    tests['board_compile'] = audit_test('transitions_r4_circular_board', 'COMPILE_PASS')
    syn_inputs, syn_result = verify_build('transitions_r4_syn')
    phy_inputs = read(ROOT / 'prj/td_build/transitions_r4_seed3_phy/inputs.json')
    for item in phy_inputs['sources'] + phy_inputs['build_files']:
        verify_record(item)
    for key in ('synthesis_inputs', 'synthesis_netlist'):
        verify_record(phy_inputs[key])
    assert warning_lines('transitions_r4_syn') == warning_lines('log64_floor_20261102_r1_syn')
    attempts = []
    for i, description in enumerate([
        '支持四种转场、速度和第六页',
        '标签扁平译码、百分比算术共享（资源更差，已撤回）',
        '共享一个标签译码器、共享百分比算术',
        '保留共享译码；亮度代数等价变换；除法比较复用借位'], 1):
        tag = f'transitions_r{i}'
        run = ROOT / 'prj/td_build' / (tag + '_seed3_phy')
        text = (run / 'console.log').read_text(encoding='utf-16')
        m = re.findall(r'(\d+) mslices, (\d+) lslices', text)[-1]
        error = re.search(r'^.*PHY-9009 ERROR:.*$', text, re.M)[0]
        area = (ROOT / 'prj/td_build' / (tag + '_syn') / 'skeleton_gate.area').read_text()
        attempts.append(dict(attempt=i, description=description, status='FAILED_RESOURCE',
            mapped_lut=int(re.search(r'^#lut\s+(\d+)', area, re.M)[1]),
            mapped_registers=int(re.search(r'^#reg\s+(\d+)', area, re.M)[1]),
            mslice=int(m[0]), lslice=int(m[1]), each_slice_limit=4900,
            error=error, log=run.relative_to(ROOT).as_posix() + '/console.log'))
    baseline = physical('log64_floor_20261102_r1_seed2_phy')
    before = read(OUT / 'baseline_sha256.json')
    changed = [p for p, h in before.items() if sha(ROOT / p) != h]
    old_font = (OUT / 'baseline/rtl/gfx/osd_youyuan_pixel.dath').read_text().splitlines()
    new_font = (ROOT / 'rtl/gfx/osd_youyuan_pixel.dath').read_text().splitlines()
    assert len(old_font) == len(new_font) == 16384
    assert old_font[:95*128] == new_font[:95*128]
    constraints = [r for r in syn_inputs['sources'] if Path(r['path']).suffix in ('.sdc', '.adc')]
    baseline_inputs = read(ROOT / 'prj/td_build/log64_floor_20261102_r1_syn/inputs.json')
    baseline_constraints = {Path(r['path']).name: r['sha256'].lower()
        for r in baseline_inputs['sources'] if Path(r['path']).suffix in ('.sdc', '.adc')}
    assert all(baseline_constraints[Path(r['path']).name] == r['sha256'].lower() for r in constraints)
    count = sum(len(r['scenarios']) for r in tests.values())
    limitations = [
        '当前布局打包失败：4940 M-Slice + 4940 L-Slice，各类上限4900；未进入布线，未生成新bit。',
        '当前版本没有最终STA；基线既有64个移相SDRAM setup违例，WNS -5.565ns，不能移植为当前版本结果。',
        '未下载上板；系统仿真使用原有缩放数据夹具及150MHz参数，不能代替实际板级100MHz SDRAM时序验证。',
        '功能自检与算术等价检查通过不代表整板全部输入、时序和硬件行为均已验证。']
    evidence = dict(generated=datetime.now().astimezone().isoformat(),
        status='simulation_pass_implementation_resource_failed',
        spec='doc/spec/scene_transitions.md', report='doc/compile/scene_transitions_20261102.md',
        tests=tests, simulation_scenario_count=count, synthesis_result=syn_result,
        current_synthesis_inputs_verified=True, changed_existing_files=changed,
        current_failed_physical_inputs_verified=True, synthesis_warnings_unchanged=True,
        synthesis_warning_count=len(warning_lines('transitions_r4_syn')),
        current_changed_file_hashes={p: sha(ROOT / p) for p in changed},
        constraints_unchanged=True, constraints=constraints, font_first_95_unchanged=True,
        pixel_font_sha256=sha(ROOT / 'rtl/gfx/osd_youyuan_pixel.dath'),
        baseline=baseline, attempts=attempts, bitstream=None, final_sta=None,
        board_validation='not_run', limitations=limitations,
        retry_budget=dict(initial_failures=1, automatic_retries_used=3, maximum=3,
            outcome='exhausted', rule='C:/Users/Lenovo/.codex/skills/fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md'),
        preserved_failed_tests=[
            dict(result='sim/transitions_r1_circular_system_sim_result.json', reason='执行期间修改了输入，失效；已用最终r4重跑替代'),
            dict(result='sim/transitions_r4_color_luma_equivalence_sim_result.json', reason='新测试误启用缺依赖的旧OSD分支，展开失败；关闭与纯函数检查无关的OSD/FFT实例后通过')])
    write(OUT / 'verification_and_build.json', evidence)
    lines = ['# 转场设置：实现与验证', '',
        '日期：2026-11-02。目标 EG4S20BG256，TD 6.2.168116 / ModelSim 10.6e。', '',
        f'功能实现及 {count} 个场景自检通过，综合完成；布局资源超限，尚未完成可下载交付。', '',
        '## 功能', '',
        'OSD 第六页包含转场效果与速度；四种效果为淡入淡出、从左向右擦除、像素溶解、15条水平百叶窗。',
        '四档速度为快速/标准/慢速/很慢：16/32/64/128 帧间隔，约0.269/0.538/1.075/2.150秒。默认淡入淡出、标准。',
        'KEY2/KEY3双向循环选择。帧边界提交设置，转场开始锁存，中途修改于下次生效。旧存储槽等待读取排空后才释放。',
        '背景和封面参与转场；歌词、频谱、OSD沿用实时叠加。图像流水与同步延迟保持，新增特效无额外RAM/DSP。', '',
        '## 等价优化证据', '',
        '- 亮度使用 256g+55(r-g)+18(b-g) 代替原移位求和。全部16,777,216种RGB逐值一致；262,144组完整颜色增益变换与原版比较一致，包含原有溢出语义。',
        '- OSD共用标签译码、共用百分比计算，除法使用减法借位比较；512个标签地址、32个转场字地址、131,072组百分比输入、全部131,072个scope除数和六页完整画面与未优化版本一致。',
        '- 原95个像素字体槽及管脚/时钟约束的哈希不变，新中文字占用原字库空槽。', '',
        '## 资源失败记录', '',
        '原版已占9767/9800 Slice（M-Slice 4884、L-Slice 4883），全部BRAM及29个DSP已满。',
        '综合LUT与布局Slice统计口径不同；不能因综合LUT未满就认定能装入芯片。', '',
        '| 尝试 | 修改 | 综合LUT | 综合REG | 布局M-Slice | 布局L-Slice |',
        '| --- | --- | ---: | ---: | ---: | ---: |']
    for a in attempts:
        lines.append(f"| r{a['attempt']} | {a['description']} | {a['mapped_lut']} | {a['mapped_registers']} | {a['mslice']} | {a['lslice']} |")
    lines += ['', '每类Slice上限4900。最终r4超出40个M-Slice、40个L-Slice，打包需求合计9880，超出总数80。',
        'r4日志：`prj/td_build/transitions_r4_seed3_phy/console.log:404`。没有生成新bit或最终时序报告。',
        '最终打包有2833个单独LUT、952个单独SEQ；LUT下降并未带来Slice下降。后续应重点核查BLE配对、寄存器控制集合及算术映射，不能继续只按LUT数判断收益。', '',
        '## 自检证据', '', '| 项目 | 场景数 | 状态 | 结果JSON |', '| --- | ---: | --- | --- |']
    for name, r in tests.items():
        lines.append(f"| {name} | {len(r['scenarios'])} | {r['status']} | `{r['result']}` |")
    lines += ['', '所有采用的结果再次核对了其记录的全部实际输入哈希、退出码、唯一TEST_PASS及预期场景集合。失败/失效结果完整保留，未计入通过数。',
        '综合95条告警按路径、源码行号及综合实例编号归一化后与基线逐条一致；保留既有厂商SDRAM、未用只读RAM字节使能脚及FFT初始化告警。',
        '详细场景ID、日志、工具、时间、输入核对结果见结构化证据。整板为真实active top和厂商模型的编译展开；系统夹具不是硬件验证。', '',
        '## 剩余工作与限次', '', *['- '+s for s in limitations], '',
        '同一资源问题经历初次失败及3次修改重跑，自动预算已用尽。根据fpga-workflow规则50停止本轮修改重试，等待新信息、明确新一轮授权或问题前提实质变化。',
        '下一轮建议：先针对packing中的单独SEQ/控制集合和较大算术块形成可等价验证的优化，再做受影响回归、综合、布局布线及最终STA；继续保留所有显示、音频及存储功能。', '',
        '## 复现', '', '```powershell',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage syn -Tag <新tag>',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage phy -Tag <新phy_tag> -SynthesisTag <新tag> -Seed 3 -GenerateBitstream',
        'python -B scripts/report_scene_transitions.py', '```', '',
        '仿真复现：设置MODELSIM_CONFIG、EXPECTED_SCENARIOS为相应结果JSON记录的配置，SIM_OUTPUT使用新前缀，RUN_SIM=1（整板编译为0），再运行python -B sim/run.py。', '']
    (ROOT / evidence['report']).write_text('\n'.join(lines), encoding='utf-8')
    state = dict(task='scene_transitions', status='blocked_resource_after_retry_budget',
        target='skeleton_top / EG4S20BG256', spec=evidence['spec'], evidence='output/transitions_20261102_r1/verification_and_build.json',
        stages=dict(requirements='completed', rtl='completed', simulation='completed', synthesis='completed', physical='failed', final_sta='blocked', bitstream='blocked', hardware='pending'),
        retry_budget=evidence['retry_budget'], remaining_error=attempts[-1]['error'], limitations=limitations)
    write(ROOT / 'doc/workflow/transitions_state.json', state)
    write(ROOT / 'doc/workflow/quality_reports/transitions.json', dict(status='incomplete_resource_failed',
        verification_level='simulation_and_synthesis', missing_files=[],
        evidence=state['evidence'], simulation_scenarios=count, implementation_pass=False,
        final_sta=None, board_validation='not_run', reason=attempts[-1]['error']))
    repair = ROOT / 'doc/compile/repair_report.md'
    marker = '## 2026-11-02 scene_transitions 资源失败（r1–r4）'
    existing = repair.read_text(encoding='utf-8') if repair.exists() else ''
    if marker not in existing:
        repair.write_text(existing.rstrip() + '\n\n' + marker + '\n\n' +
            '初次失败后已执行3次自动修改重跑，当前4940 M-Slice、4940 L-Slice，每类上限4900。\n\n' +
            '完整尝试、等价检查、剩余错误及后续方案见 [转场实现报告](scene_transitions_20261102.md)。本轮停止自动重试，无新bit、无最终STA、未上板。\n', encoding='utf-8')
    print(json.dumps(dict(status=evidence['status'], scenarios=count, attempts=attempts), ensure_ascii=False))


if __name__ == '__main__':
    main()
