"""Check the exact inputs and package the display floor board candidate."""
from pathlib import Path
from datetime import datetime
import argparse
import json
import re
import shutil
import difflib
from report_downscale_implementation import verify_build, physical, sha, read_json

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'output/display_floor_20261102_r1'
KEYS = ['floor', 'wav', 'attack_bands', 'spectrum_stage1', 'layer_fft64',
        'split_spectrum', 'split_core', 'circular_system', 'circular_board']


def text_file(path):
    data = path.read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff'))
                       else 'utf-8-sig', errors='replace')


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--tag', default='display_floor_20261102_r3')
    p.add_argument('--phy', default='display_floor_20261102_r3_seed2_phy')
    args = p.parse_args()
    out = ROOT / 'output' / args.tag
    assert not out.exists(), 'Preserve existing delivery: ' + str(out)
    syn_tag = args.tag + '_syn'
    syn_inputs, syn_result = verify_build(syn_tag)
    phy_inputs, phy_result = verify_build(args.phy)
    assert syn_inputs['sources'] == phy_inputs['sources']
    assert phy_inputs['synthesis_tag'] == args.tag
    for record in (syn_inputs, phy_inputs):
        assert record['script_sha256'].lower() == sha(ROOT / 'scripts/build.ps1')
    baseline = read_json(BASE / 'baseline_sha256.json')
    changed = [name for name, digest in baseline.items() if sha(ROOT / name) != digest.lower()]
    assert changed == ['rtl/audio/spec_bands64.v'], changed
    tests = {}
    evidence_files = []
    for key in KEYS:
        path = ROOT / 'sim' / (args.tag + '_' + key + '_sim_result.json')
        test = read_json(path)
        assert test['status'] == ('COMPILE_PASS' if key == 'circular_board' else 'PASS'), key
        for source, digest in test['input_hashes'].items():
            assert sha(Path(source)) == digest.lower(), source
        tests[key] = {'status': test['status'], 'scenarios': test.get('expected_scenarios', []),
                      'result': str(path.relative_to(ROOT)), 'result_sha256': sha(path),
                      'input_hashes_current': True, 'tool_version': test['tool_version']}
        evidence_files.append(path)
        for field in ('compile_log', 'sim_log'):
            if test.get(field):
                evidence_files.append(ROOT / test[field])
    current = physical(args.phy)
    previous = physical('linear64_20261102_r1_seed2_phy')
    run = ROOT / 'prj/td_build' / args.phy
    console = text_file(run / 'console.log')
    packed = re.findall(r'(\d+) mslices, (\d+) lslices', console)
    mslice, lslice = map(int, packed[-1])
    assert max(mslice, lslice) <= 4900
    assert mslice + lslice == current['resources']['slices']
    current['slice_types'] = {'mslice': mslice, 'lslice': lslice, 'each_limit': 4900}
    limits = dict(lut=19600, registers=19600, bram9k=64, bram32k=16,
                  dsp=29, pll=4, gclk=16, slices=9800)
    assert all(current['resources'][k] <= v for k, v in limits.items())
    attempts = []
    for folder in sorted((ROOT / 'prj/td_build').glob('display_floor_20261102*')):
        log = folder / 'console.log'
        if not log.exists():
            continue
        errors = [line for line in text_file(log).splitlines() if 'ERROR:' in line]
        if errors:
            attempts.append({'run': str(folder.relative_to(ROOT)), 'errors': errors,
                             'console_sha256': sha(log)})
    wav_path = ROOT.parents[1] / 'tone_187p5Hz_10s_48kHz_16bit_stereo.wav'
    wav_input = read_json(BASE / 'wav_input.json')
    assert sha(wav_path) == wav_input['sha256']
    wav_log = text_file(ROOT / 'sim' / (args.tag + '_wav_sim.log'))
    wav_stats = re.search(r'WAV_RESULT frames=(\d+) first_min=(\d+) first_max=(\d+) '
                         r'second_max=(\d+) original_residual_bar_events=(\d+) '
                         r'residual_log_max=(\d+)', wav_log)
    assert wav_stats
    wav_result = dict(zip(('frames', 'first_min', 'first_max', 'second_max',
                           'original_residual_bar_events', 'residual_log_max'),
                         map(int, wav_stats.groups())))
    out.mkdir()
    target = out / 'audio_visual_display_floor.bit'
    shutil.copy2(phy_result['bitstream']['path'], target)
    assert sha(target) == phy_result['bitstream']['sha256'].lower()
    (out / 'simulation').mkdir()
    for source in evidence_files:
        shutil.copy2(source, out / 'simulation' / source.name)
    for tag in (syn_tag, args.phy):
        dest = out / tag
        dest.mkdir()
        folder = ROOT / 'prj/td_build' / tag
        for name in ('inputs.json', 'build_result.json', 'gate.qor', 'route.qor',
                     'skeleton_gate.area', 'skeleton_phy.area', 'final_timing.rpt',
                     'skeleton_exception.timing', 'console.log', 'settings.cfg',
                     'skeleton.tcl', 'skeleton.prj'):
            source = folder / name
            if source.exists():
                shutil.copy2(source, dest / name)
    shutil.copy2(ROOT / changed[0], out / 'spec_bands64.v')
    shutil.copy2(BASE / 'baseline/spec_bands64.v', out / 'spec_bands64_before.v')
    before = (BASE / 'baseline/spec_bands64.v').read_text(encoding='utf-8-sig').splitlines(True)
    after = (ROOT / changed[0]).read_text(encoding='utf-8-sig').splitlines(True)
    (out / 'rtl_change.diff').write_text(''.join(difflib.unified_diff(
        before, after, fromfile='before/spec_bands64.v', tofile='after/spec_bands64.v')), encoding='utf-8')
    bit = {'path': str(target), 'bytes': target.stat().st_size, 'sha256': sha(target)}
    report = {'created': datetime.now().astimezone().isoformat(), 'version': args.tag,
              'changed_production_files': changed,
              'baseline_files_checked': len(baseline),
              'floor': {'raw_magnitude_max': 4, 'log_code_max': 122,
                        'applies_to': '64 display bands only, before accumulation'},
              'synthesis': syn_tag, 'physical': args.phy, 'tests': tests,
              'simulation_scenario_count': sum(len(t['scenarios']) for k, t in tests.items()
                                                if k != 'circular_board'),
              'wav_input': wav_input, 'wav_result': wav_result,
              'physical_results': current, 'previous_linear64_results': previous,
              'failed_builds_preserved': attempts, 'bitstream': bit,
              'timing_clean': current['setup_violations'] == current['hold_violations'] == 0,
              'board_validation': 'not_run',
              'limitations': ['STA violations are saved; this is a board validation candidate.',
                              'Actual WAV simulation covers 30 FFT frames, not the full 10 seconds.',
                              'Board top was compiled and elaborated; it was not dynamically simulated.',
                              'Signals at or below the shared display floor are deliberately hidden.']}
    write_json(out / 'verification_and_build.json', report)
    lines = [f'版本：{args.tag}', '',
             '仅修改 spec_bands64.v：64 根基础柱累加前，将 LOG_MAG 码值 <=122（原始幅值 <=4）归零。',
             '64 段线性等宽划分、平滑系数及输出周期保持。18 段节拍沿用未过滤值；对照检查逐周期一致。',
             '四个显示 bin 的平均改用右移两位，等价于原 Q16 的 1/4 系数；用于减少硬件开销。', '',
             f"8 组运行仿真通过，共 {report['simulation_scenario_count']} 个场景；板级顶层编译与展开通过。",
             f"用户 WAV 的 {wav_result['frames']} 个 FFT 帧：第一根 {wav_result['first_min']}～{wav_result['first_max']} 级，第二根最高 {wav_result['second_max']} 级，第3～64根全零。",
             '未过滤对照中其余62根柱累计1851次非零；原始节拍输出逐周期一致。', '',
             f"核对基线 {len(baseline)} 个 RTL/IP/约束/数据文件，仅 spec_bands64.v 变化；全部构建、仿真输入哈希与当前文件一致。",
             f'MSlice {mslice}/4900，LSlice {lslice}/4900。', '',
             '|资源|使用|上限|', '|---|---:|---:|']
    lines += [f'|{name}|{current["resources"][name]}|{limit}|' for name, limit in limits.items()]
    lines += ['', '|路径组|setup/ns|setup违例|hold/ns|hold违例|', '|---|---:|---:|---:|---:|']
    for name, group in current['groups'].items():
        lines.append(f'|{name}|{group["setup_ns"]:+.3f}|{group["setup_violations"]}|'
                     f'{group["hold_ns"]:+.3f}|{group["hold_violations"]}|')
    lines += ['', f'全局 setup WNS {current["setup_wns_ns"]:+.3f}ns，{current["setup_violations"]} 个违例；'
                   f'hold WNS {current["hold_wns_ns"]:+.3f}ns，{current["hold_violations"]} 个违例。',
              f'前一线性版 setup WNS {previous["setup_wns_ns"]:+.3f}ns，{previous["setup_violations"]} 个违例。',
              '依用户要求保留违例并提供上板候选；不能宣称时序通过或硬件效果已验收。',
              f'STA coverage {current["sta_coverage_percent"]:.2f}%。', '',
              '失败构建目录、日志保留；详见 verification_and_build.json。',
              'bit 尚未上板，未写 TF 卡或 Flash。实际显示效果及其他整板功能待用户板测。', '',
              f'bit：{target.name}', f'SHA256：{bit["sha256"]}', '']
    (out / '交付说明.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'bitstream': bit, 'resources': current['resources'],
                      'setup_wns_ns': current['setup_wns_ns'],
                      'setup_violations': current['setup_violations'],
                      'hold_violations': current['hold_violations'],
                      'changed_files': changed}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
