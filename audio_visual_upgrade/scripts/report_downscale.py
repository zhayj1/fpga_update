"""Record current downscale evidence; never promote old bit/board evidence."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def implementation_inputs_current(implementation):
    """Keep implementation evidence only while its recorded inputs still match."""
    selected = implementation.get('selected_physical')
    if not selected:
        return False
    try:
        run = ROOT/selected
        result = json.loads((run/'build_result.json').read_text(encoding='utf-8-sig'))
        if result.get('status') != 'BUILD_COMPLETE':
            return False
        inputs = json.loads((run/'inputs.json').read_text(encoding='utf-8-sig'))
        records = inputs['sources'] + inputs.get('build_files', [])
        records += [inputs[key] for key in ('synthesis_inputs', 'synthesis_netlist') if key in inputs]
        if result.get('bitstream'):
            records.append(result['bitstream'])
        return all(Path(item['path']).is_file() and
                   sha(Path(item['path'])).lower() == item['sha256'].lower()
                   for item in records)
    except (OSError, ValueError, KeyError, TypeError):
        return False


def main():
    state_path = ROOT/'doc/workflow/state.json'
    state = json.loads(state_path.read_text(encoding='utf-8-sig'))
    backup = ROOT/'output/bmp_downscale_baseline_20261029/workflow_state.json'
    if not backup.exists():
        backup.write_text(json.dumps(state, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    checks = {}
    for kind in ('unit', 'writeback', 'legacy', 'catalog', 'system', 'board', 'fft_init'):
        paths = list((ROOT/'sim').glob(f'downscale_{kind}_*_sim_result.json'))
        if not paths:
            continue
        path = max(paths, key=lambda p: p.stat().st_mtime)
        record = json.loads(path.read_text(encoding='utf-8'))
        changed = []
        for name, digest in record.get('input_hashes', {}).items():
            p = Path(name)
            if not p.is_absolute():
                p = ROOT/p
            if not p.exists() or sha(p).lower() != digest.lower():
                changed.append(name)
        checks[kind] = dict(status=record['status'], changed_inputs=changed,
            scenarios=record.get('expected_scenarios', []),
            result=path.relative_to(ROOT).as_posix(),
            compile_log=record.get('compile_log'), sim_log=record.get('sim_log'),
            duration_seconds=round(record.get('finished_at', record['started_at'])-record['started_at'], 2))
    good = len(checks)==7 and all(c['status'] in ('PASS','COMPILE_PASS') and not c['changed_inputs'] for c in checks.values())
    previous = state.get('bmp_downscale', {})
    implementation = previous.get('implementation', {})
    keep_implementation = implementation_inputs_current(implementation)
    state.update(active_stage='bmp_downscale',
                 scope=state['scope'] if keep_implementation else 'BMP加载时只缩小；RTL、编译、单元与集成自检；不运行综合、布局布线或下载',
                 status=state['status'] if good and keep_implementation else ('completed_simulation' if good else 'running'),
                 board_validation='not_run_for_current_sources',
                 target_top='skeleton_top', report='doc/compile/bmp_downscale_run_report.md')
    for key in ('bitstream','build_directory','source','verification','board_confirmation'):
        state.pop(key, None)
    state['bmp_downscale'] = dict(spec='doc/spec/bmp_downscale_behavior_spec.md',
        sources={p:sha(ROOT/p) for p in ['rtl/load/bmp_load.v','rtl/top/skeleton_core.v','rtl/storage/resource_catalog.v','rtl/gfx/layer_fft64.v']},
        stages=dict(requirements='completed', architecture='completed', rtl='completed', tb='completed',
                    simulation='completed' if good else 'running', physical='pending_user_run'),
        evidence=checks,
        repairs=[dict(area='TB超时常量', attempts=2, cause='32位无尺寸常量溢出，延时表达式需括号', status='fixed'),
                 dict(area='TB复位场景', attempts=1, cause='手动启动未刷新预期目标配置', status='fixed'),
                 dict(area='频谱首次出图', attempts=2, cause='更早的首屏遇到未初始化的频谱RAM；独立测试复现，增加active_valid', status='verified' if good else 'unit_pass_system_pending')],
        limitations=['未运行综合/布局布线/时序/上板；旧报告资源不代表当前代码',
                     '整机仿真使用缩小的目标尺寸及HDMI stub；生产尺寸由装载器逐像素测试覆盖',
                     '共享SD读取完整原图，最大尺寸不保证预加载赶上播放切换'])
    if implementation:
        state['bmp_downscale']['implementation'] = implementation
        state['bmp_downscale']['stages']['physical'] = 'completed' if keep_implementation else 'stale'
        if keep_implementation:
            state['bmp_downscale']['limitations'] = previous['limitations']
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    quality = dict(status='completed' if good else 'partial', files_written=[
        'rtl/load/bmp_load.v','rtl/storage/resource_catalog.v','rtl/top/skeleton_core.v','rtl/gfx/layer_fft64.v',
        'tb/tb_bmp_downscale.v','doc/spec/bmp_downscale_behavior_spec.md'], missing_files=[],
        reason='Current source evidence checked' if good else 'Simulation verification in progress',
        verification_level='simulation' if good else 'source_and_partial_simulation', evidence=checks)
    if keep_implementation:
        quality.update(implementation=implementation,
                       reason='Current source evidence checked; timing_clean='+str(implementation.get('timing_clean')),
                       verification_level='routed_bitstream_and_simulation' if good else 'routed_bitstream_simulation_stale')
    (ROOT/'doc/workflow/quality_reports/bmp_downscale.json').write_text(json.dumps(quality, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print(json.dumps(dict(complete=good, checks=checks), indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
