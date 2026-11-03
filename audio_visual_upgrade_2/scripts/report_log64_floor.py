"""Bind the board candidate to the current sources, tests and TD reports."""
from pathlib import Path
from datetime import datetime
import json, shutil, difflib, re, argparse
from report_downscale_implementation import verify_build, physical, sha, read_json

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'output/log64_floor_20261102_r1'
KEYS=['mapping','floor','wav','attack_bands','spectrum_stage1','layer_fft64','split_spectrum','split_core','circular_system','circular_board']

def text(p):
    b=p.read_bytes()
    return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
def save(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--tag',default='log64_floor_20261102_r1')
    p.add_argument('--phy',default='log64_floor_20261102_r1_seed2_phy')
    p.add_argument('--sim-tag',default='log64_floor_20261102_r1')
    args=p.parse_args()
    out=ROOT/'output'/args.tag
    assert not (out/'verification_and_build.json').exists(),'Preserve delivery'
    si,sr=verify_build(args.tag+'_syn');pi,pr=verify_build(args.phy)
    assert si['sources']==pi['sources']
    assert pi['synthesis_tag']==args.tag
    for rec in (si,pi):assert rec['script_sha256'].lower()==sha(ROOT/'scripts/build.ps1')
    baseline=read_json(BASE/'baseline_sha256.json')
    changes=sorted(name for name,h in baseline.items() if sha(ROOT/name)!=h)
    assert changes==['rtl/audio/spec_bands64.v','rtl/gfx/layer_fft64.v','rtl/gfx/layer_spectrum_ring.v'],changes
    tests={};evidence=[]
    for key in KEYS:
        path=ROOT/'sim'/(args.sim_tag+'_'+key+'_sim_result.json');result=read_json(path)
        assert result['status']==('COMPILE_PASS' if key=='circular_board' else 'PASS'),key
        for name,h in result['input_hashes'].items():assert sha(Path(name))==h.lower(),name
        tests[key]={'status':result['status'],'scenarios':result.get('expected_scenarios',[]),
                    'result':str(path.relative_to(ROOT)),'sha256':sha(path),'current_inputs_verified':True,
                    'tool_version':result['tool_version']}
        evidence.append(path)
        for field in ('compile_log','sim_log'):
            if result.get(field):evidence.append(ROOT/result[field])
    current=physical(args.phy);previous=physical('display_floor_20261102_r3_seed2_phy')
    run=ROOT/'prj/td_build'/args.phy
    packed=re.findall(r'(\d+) mslices, (\d+) lslices',text(run/'console.log'))
    ms,ls=map(int,packed[-1]);assert max(ms,ls)<=4900
    assert ms+ls==current['resources']['slices']
    limits=dict(lut=19600,registers=19600,bram9k=64,bram32k=16,dsp=29,pll=4,gclk=16,slices=9800)
    assert all(current['resources'][k]<=v for k,v in limits.items())
    current['slice_types']={'mslice':ms,'lslice':ls,'each_limit':4900}
    out.mkdir(exist_ok=True)
    target=out/'audio_visual_log64_floor.bit';assert not target.exists()
    shutil.copy2(pr['bitstream']['path'],target)
    assert sha(target)==pr['bitstream']['sha256'].lower()
    sim_out=out/'simulation';sim_out.mkdir()
    for f in evidence:shutil.copy2(f,sim_out/f.name)
    testpaths=['tb/tb_log64_mapping.v','tb/tb_log64_floor.v','tb/tb_log64_floor_wav.v',
               'tb/tb_spectrum_stage1.v','tb/tb_layer_fft64.v','tb/tb_split_spectrum.v',
               'tb/expected_spectrum_stage1.json','tb/expected_split_spectrum.json']
    for name in changes+testpaths:
        d=out/'source'/name;d.parent.mkdir(exist_ok=True,parents=True);shutil.copy2(ROOT/name,d)
    diffs=[]
    for name in changes:
        before=text(BASE/'baseline'/name).splitlines(True);after=text(ROOT/name).splitlines(True)
        diffs.extend(difflib.unified_diff(before,after,fromfile='before/'+name,tofile='after/'+name))
    (out/'rtl_change.diff').write_text(''.join(diffs),encoding='utf-8')
    for tag in (args.tag+'_syn',args.phy):
        dest=out/tag;dest.mkdir()
        for name in ('inputs.json','build_result.json','gate.qor','route.qor','skeleton_gate.area',
                     'skeleton_phy.area','final_timing.rpt','skeleton_exception.timing','console.log',
                     'settings.cfg','skeleton.tcl','skeleton.prj'):
            src=ROOT/'prj/td_build'/tag/name
            if src.exists():shutil.copy2(src,dest/name)
    failures=[]
    for folder in sorted((ROOT/'prj/td_build').glob('log64_floor_20261102*')):
        log=folder/'console.log'
        if not log.exists():continue
        errors=[l for l in text(log).splitlines() if 'ERROR:' in l]
        if errors:
            failures.append({'run':str(folder.relative_to(ROOT)),'errors':errors,'log_sha256':sha(log)})
            d=out/'failed_builds'/folder.name;d.mkdir(parents=True)
            for f in folder.iterdir():
                if f.suffix in ('.log','.json') or f.name.endswith('.error.f'):shutil.copy2(f,d/f.name)
    wav_input=read_json(ROOT/'output/display_floor_20261102_r1/wav_input.json')
    wav_path=ROOT.parents[1]/'tone_187p5Hz_10s_48kHz_16bit_stereo.wav'
    assert sha(wav_path)==wav_input['sha256']
    wav_log=text(ROOT/'sim'/(args.sim_tag+'_wav_sim.log'))
    wav_stats=re.search(r'WAV_RESULT[^\r\n]+',wav_log)[0]
    bit={'path':str(target),'bytes':target.stat().st_size,'sha256':sha(target)}
    report={'version':args.tag,'created':datetime.now().astimezone().isoformat(),
            'authorization':'按照这般方案修改吧可以适合多数歌曲，保留刚加入的残值门限',
            'changed_production_files':changes,'baseline_unique_files_checked':len(baseline),
            'build_manifest_entries':len(si['sources']),'all_build_and_simulation_inputs_current':True,
            'mapping':{'kind':'discrete_log','bands':64,'sample_rate':48000,'fft_points':1024,
                       'bin_min':1,'bin_max':256,'csv':str(BASE/'frequency_map.csv'),
                       'per_band_gain':False,'spike_centers':read_json(BASE/'attack_centers.json')},
            'display_floor':{'log_code_max_removed':122,'raw_fft_magnitude_max_removed':4,
                             'single_bin_floor_applied':True,'attack_path_unfiltered':True},
            'synthesis':args.tag+'_syn','physical':args.phy,'tests':tests,
            'simulation_scenario_count':sum(len(t['scenarios']) for k,t in tests.items() if k!='circular_board'),
            'wav_input':wav_input,'wav_result':wav_stats,
            'physical_results':current,'previous_linear_floor_results':previous,
            'failed_builds_preserved':failures,
            'failed_test_preserved':{'path':str(BASE/'failed_tests/wav_verify1'),
              'reason':'The old linear four-bin test limit of 2 levels rejected the log single-bin range 252..255. The original log reference matches exactly. Single-bin test permits 4 levels; no production amplitude logic was changed.'},
            'bitstream':bit,
            'timing_clean':current['setup_violations']==current['hold_violations']==0,
            'board_validation':'not_run',
            'limitations':['STA violations retained per user instruction; board candidate only.',
                           'Actual pure-tone WAV simulation covers 30 FFT frames.',
                           'Board top compile/elaboration only; system regression uses existing scaled fixture.',
                           'Uniform display floor deliberately hides signals with LOG_MAG <=122.']}
    save(out/'verification_and_build.json',report)
    lines=[f'版本：{args.tag}','','64 段恢复离散对数划分，覆盖 FFT bin 1～256（46.875 Hz～12 kHz），排除 DC。',
           '频段边界与原有对数表一致；低频每段一个 bin，高频逐步加宽至14个 bin。',
           '保留各段平均、原有平滑及残值门限 <=122；单 bin 同样经过门限。无额外频段增益。',
           '18 段节拍统计继续读取原始 bin。与修改前线性门限版逐周期对照，节拍和后级触发输出一致。',
           '直条/环形两种显示的尖峰中心按新表同步；尖峰强度、宽度、衰减、颜色、控件保持。','',
           f'9 组运行仿真通过，共 {report["simulation_scenario_count"]} 个场景；板级顶层编译/展开通过。',
           '纯音 WAV：第4根为主峰，第3、5根可含窗函数主瓣，其余61根为零；旧未过滤对照仍出现残值。',
           wav_stats,'',f'核对修改前 {len(baseline)} 个唯一生产输入（清单 {len(si["sources"])} 项），仅以下3个 RTL变化：']
    lines += ['- '+n for n in changes]
    lines += ['', '|资源|使用|上限|','|---|---:|---:|']
    lines += [f'|{k}|{current["resources"][k]}|{v}|' for k,v in limits.items()]
    lines += ['',f'MSlice {ms}/4900；LSlice {ls}/4900。','',
              '|路径组|setup/ns|setup违例|hold/ns|hold违例|','|---|---:|---:|---:|---:|']
    for name,g in current['groups'].items():
        lines.append(f'|{name}|{g["setup_ns"]:+.3f}|{g["setup_violations"]}|{g["hold_ns"]:+.3f}|{g["hold_violations"]}|')
    lines += ['',f'全局 setup WNS {current["setup_wns_ns"]:+.3f} ns，{current["setup_violations"]} 个端点；hold {current["hold_violations"]} 个端点。',
              '依用户先前授权保留时序违例并生成 bit；不能宣称时序通过或整板效果已验收。',
              '未下载硬件、未写卡、未写 Flash。所有失败尝试与日志保留。','',
              f'bit：{target.name}',f'SHA256：{bit["sha256"]}','']
    (out/'交付说明.md').write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps({'bitstream':bit,'physical_results':current,'tests':len(tests),
                      'scenarios':report['simulation_scenario_count']},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
