"""Bind the circular UI delivery to current tests, source hashes and TD output."""
from pathlib import Path
from datetime import datetime
import json,hashlib,re,shutil,zipfile,difflib
from report_downscale_implementation import physical,verify_build
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/circular_ui_20261101_r1'
SYN='circular_r2_syn'
PHYSICAL_CANDIDATES=['circular_r1_congestion_seed3_phy','circular_r1_congestion_seed1_phy','circular_r2_congestion_seed3_phy']
CHECKS=['circular_spectrum_r2','circular_text_r2','circular_text_sdram_r2','circular_core_r3',
        'circular_board_r2','circular_legacy_core_r2','circular_system_r2',
        'typography_visual_circular_r1','typography_visual_osd_circular_r1','typography_controls_circular_r1']

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,obj):p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    candidates={tag:physical(tag) for tag in PHYSICAL_CANDIDATES
                if (ROOT/f'prj/td_build/{tag}/build_result.json').is_file()}
    def rank(tag):
        d=candidates[tag];ordinary=[v for k,v in d['groups'].items() if 'sdr_clk_sft' not in k]
        return (-sum(g['setup_violations'] for g in ordinary),-d['hold_violations'],min(g['setup_ns'] for g in ordinary))
    PHY=max(candidates,key=rank)
    tests={}
    for name in CHECKS:
        p=ROOT/f'sim/{name}_sim_result.json';d=read(p)
        expected='COMPILE_PASS' if name=='circular_board_r2' else 'PASS'
        assert d['status']==expected and d['compile_exit_code']==0,(name,d['status'])
        for f,h in d['input_hashes'].items():assert sha(Path(f))==h.lower(),f
        scenarios=[]
        if expected=='PASS':
            assert d['sim_exit_code']==0,name
            log=(ROOT/d['sim_log']).read_text(errors='replace')
            scenarios=re.findall(r'SCENARIO_PASS\s+(\S+)',log)
            assert sorted(scenarios)==sorted(d['expected_scenarios']) and len(set(scenarios))==len(scenarios),name
            assert len(re.findall(r'\bTEST_PASS\b',log))==1 and 'TEST_FAIL' not in log,name
        tests[name]={'status':expected,'scenarios':scenarios,'evidence':p.relative_to(ROOT).as_posix(),'inputs_current':True}
    si,sr=verify_build(SYN);pi,pr=verify_build(PHY)
    assert si['sources']==pi['sources']
    assert si['script_sha256'].lower()==sha(ROOT/'scripts/build.ps1')
    current=physical(PHY)
    baseline=physical('visual_r9_congestion_seed3_phy')
    ordinary=sum(g['setup_violations'] for n,g in current['groups'].items() if 'sdr_clk_sft' not in n)
    assert ordinary==0 and current['hold_violations']==0,current
    for name,limit in [('slices',9800),('lut',19600),('registers',19600),('bram9k',64),('bram32k',16),('dsp',29)]:
        assert current['resources'][name]<=limit,(name,current['resources'][name])
    bit=OUT/'audio_circular_ui_r1.bit';shutil.copy2(pr['bitstream']['path'],bit)
    assert sha(bit)==pr['bitstream']['sha256'].lower()
    snapshot=OUT/'candidate_build_sources.zip'
    with zipfile.ZipFile(snapshot,'w',zipfile.ZIP_DEFLATED) as z:
        added=set()
        for item in si['sources']:
            p=Path(item['path']);name=p.relative_to(ROOT).as_posix()
            if name not in added:z.write(p,name);added.add(name)
        z.write(ROOT/'scripts/build.ps1','scripts/build.ps1')
        z.write(ROOT/f'prj/td_build/{SYN}/inputs.json','build_inputs.json')
    manifest=read(OUT/'baseline_manifest.json');changed=[];patch=[]
    with zipfile.ZipFile(OUT/'baseline_sources.zip') as z:
        for entry in manifest['files']:
            p=ROOT/entry['path'];assert p.is_file(),entry['path']
            if sha(p)!=entry['sha256']:
                changed.append({'path':entry['path'],'before':entry['sha256'],'after':sha(p)})
                old=z.read(entry['path']).decode('utf-8-sig',errors='replace').replace('\r\n','\n').splitlines(True)
                new=p.read_text(encoding='utf-8-sig').splitlines(True)
                patch.extend(difflib.unified_diff(old,new,fromfile='baseline/'+entry['path'],tofile='current/'+entry['path']))
    (OUT/'changes_from_board_baseline.patch').write_text(''.join(patch),encoding='utf-8')
    new_files=['rtl/gfx/layer_spectrum_ring.v','rtl/gfx/spectrum_angles.dath',
        'scripts/prepare_circular_ui.py','scripts/verify_circular_ui.py','scripts/render_circular_ui_preview.py',
        'scripts/report_circular_ui.py','tb/tb_circular_spectrum.v','tb/tb_circular_text.v','tb/tb_circular_core.v']
    # Feature boundary: every existing audio/storage/load/memory block remains
    # byte-for-byte identical; all image/font/music resources remain untouched.
    assert not any(c['path'].startswith(('rtl/audio/','rtl/storage/','rtl/load/','rtl/mem/','constraints/')) for c in changed)
    count=sum(len(t['scenarios']) for t in tests.values())
    report={'date':'2026-11-01','status':'candidate_built_pending_board','baseline':manifest['baseline'],
        'scope':manifest['scope'],'tests':tests,'scenario_count':count,'current':current,'baseline_physical':baseline,
        'ordinary_setup_endpoints':ordinary,'timing_clean':current['setup_violations']==0 and current['hold_violations']==0,
        'synthesis_result':sr,'physical_result':pr,'selected_physical':PHY,'physical_candidates':candidates,
        'all_build_inputs_current':True,'changed_existing_files':changed,
        'new_implementation_files':[{'path':p,'sha256':sha(ROOT/p)} for p in new_files],
        'bitstream':{'path':bit.relative_to(ROOT).as_posix(),'bytes':bit.stat().st_size,'sha256':sha(bit)},
        'source_snapshot':{'path':snapshot.relative_to(ROOT).as_posix(),'sha256':sha(snapshot)},
        'board_validation':'not_run','sd_card_changes_required':False,
        'geometry':{'center':[320,254],'spectrum_bands':64,'inner_radius':136,'maximum_radius':182,
            'horizontal_screen_compensation':'existing 6:5','title_top':16,'artist_top':44,
            'lyric_box':[96,448,448,24],'osd_box':[440,224,200,224]},
        'limits':['New bitstream has not been tested on hardware; no hardware download or card/Flash write performed.',
            'Full SPI/SDRAM/PCM system regression retains its existing compact-image/legacy-font fixture; new typography is tested separately with real SDRAM contention.',
            'Composition test controls image and overlay pixels; radial geometry and text are independently checked against full-frame references.',
            'No post-route delay simulation. Existing SDRAM phase-shift setup violations remain explicitly reported.',
            'Preview combines actual RTL spectrum/text masks with existing card artwork; its text and spectrum levels are test fixtures.']}
    write(OUT/'verification_and_build.json',report)
    lines=['# 圆形频谱与单行歌词布局','',
        '2026-11-01。用户确认实施：外围圆形频谱、中央封面、顶部居中歌名/歌手、底部单行高亮歌词。状态：已生成候选 bit，待用户上板。','',
        '## 显示与复用','',
        '- 64 个频段沿圆周排列；复用原 FFT、频带电平、节拍检测、尖峰、颜色与开关。没有新增内侧彩色曲线。',
        '- 封面与频谱/扩散波纹共用中心 (320,254)。240×240 封面、四档回弹、16 级边缘覆盖及图片淡入淡出保留。',
        '- 歌名 y=16，歌手 y=44；短文本居中，长文本沿用跑马灯。歌词位于 x=96..543/y=448..471，只显示当前句，保留原字级时间、高亮、字体和长句横滚。',
        '- 设置面板整体上移 32 像素到 x=440..639/y=224..447，避开底部歌词；五页设置、按键、颜色和效果语义保持。',
        '- 保留原显示模式作为编译期参数，当前板级顶层启用 CIRCULAR_UI=1。音频、存储、装载、SDRAM、约束源码未改；SD 卡资源无需更换。',
        '- 圆形沿用原工程显示屏横向 6:5 补偿；基础半径 136、最大 182，频谱柱间留缝。','',
        '字幕滚动的停留/分频判定使用与原计数器同步更新的标志，保持采样事件、停留长度与环回时刻，缩短控制路径；已重跑受影响回归。','',
        '## 验证','',f'{count} 个自检场景通过，板级顶层编译展开通过；测试/构建输入 SHA256 与交付源码一致。',
        '频谱检查覆盖完整 640×480 像素、64 频带、颜色端点、尖峰跨圆周接缝、帧切换、独立效果开关、复位；文字检查覆盖高亮、单行裁剪、长句环回、切歌清相位、迟到恢复及真实 SDRAM 争用。',
        '整体合成检查覆盖移动后封面四尺寸抗锯齿、淡化、文字上色、OSD 平移与 AXIS 像素/行尾对齐；原播放链路与控制回归另行通过。','',
        '|资源|原上板版|圆形布局候选|','|---|---:|---:|']
    for label,key,lim in [('Slice','slices',9800),('LUT','lut',19600),('寄存器','registers',19600),('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f'|{label}|{baseline["resources"][key]}/{lim}|{current["resources"][key]}/{lim}|')
    lines+=['',f'非移相路径 setup 违例 {ordinary}；Hold 违例 {current["hold_violations"]}。全局 setup 违例 {current["setup_violations"]}，WNS {current["setup_wns_ns"]:.3f} ns。',
        '原工程 SDRAM 移相接口时序欠项仍保留，不将 bit 生成或功能仿真描述为全工程时序闭合。未修改时钟、约束或添加例外。','',
        '## 交付与复现','',f'- bit：`{report["bitstream"]["path"]}`',f'- SHA256：`{sha(bit)}`',
        f'- 综合：`prj/td_build/{SYN}`；布局布线/STA：`prj/td_build/{PHY}`。',
        '- 证据：同目录 `verification_and_build.json`；改动前快照 `baseline_sources.zip` 和清单；已有文件补丁 `changes_from_board_baseline.patch`。',
        f'- 重建使用 `scripts/build.ps1`，选择全新 Tag；先 `-Stage syn`，再 `-Stage phy -SynthesisTag <综合Tag> -RouteEffort routability -Seed {pi["seed"]} -GenerateBitstream`。',
        '- 回归使用 `scripts/verify_circular_ui.py <spectrum|text|text_sdram|core|board|legacy_core|system> --suffix <新编号>`。','',
        '## 验证边界','',
        '未上板、未下载、未写 SD 卡或 Flash。板测需用户确认歌曲播放、中央封面切换/回弹、环形频谱/颜色/尖峰、底部高亮歌词及所有设置。',
        '完整 SPI/SDRAM/PCM 回归采用既有小图/旧字体夹具；新字体/单行显示通过单独真实 SDRAM 争用测试。合成测试替代图层像素，频谱和歌词分别逐像素验证；未做带延迟后仿真。',
        '布局预览使用 RTL 输出的频谱/文字像素与原卡图片组合，测试文字与频谱电平用于展示位置，不是板测截图。','']
    content='\n'.join(lines)
    (ROOT/'doc/compile/circular_ui_20261101.md').write_text(content,encoding='utf-8')
    (OUT/'README.md').write_text(content,encoding='utf-8')
    readme=ROOT/'README.md';old=readme.read_text(encoding='utf-8')
    prefix='# 圆形频谱前端候选（2026-11-01）\n\n已按用户确认修改中央封面、外围 64 柱环形频谱、顶部歌名/歌手和底部单行高亮歌词。候选待上板，原功能及 SD 卡资源保留。\n\n- bit：`output/circular_ui_20261101_r1/audio_circular_ui_r1.bit`\n- 说明与证据：`output/circular_ui_20261101_r1/README.md`\n- 改动前源码快照和 SHA256 清单：同目录 `baseline_sources.zip` / `baseline_manifest.json`。\n\n以下为原上板基线说明。\n\n'
    if not old.startswith('# 圆形频谱前端候选'):readme.write_text(prefix+old,encoding='utf-8')
    state_path=ROOT/'doc/workflow/state.json';state=read(state_path)
    state.update(active_stage='circular_ui',status='candidate_built_pending_board',board_validation='not_run_for_circular_ui',
        scope='User-approved circular spectrum, centered cover/top metadata, bottom single lyric; all controls retained',
        report='doc/compile/circular_ui_20261101.md')
    state['circular_ui']={'status':report['status'],'evidence':'output/circular_ui_20261101_r1/verification_and_build.json',
        'bitstream':report['bitstream'],'board_validation':'not_run','active_writer':'implementation complete; awaiting user board feedback',
        'stages':{'rtl':'completed','simulation':'completed','synthesis':'completed','physical':'completed','board':'pending'}}
    write(state_path,state)
    # Include the final README/state edits in the baseline patch as well.
    changed=[];patch=[]
    with zipfile.ZipFile(OUT/'baseline_sources.zip') as z:
        for entry in manifest['files']:
            p=ROOT/entry['path']
            if sha(p)!=entry['sha256']:
                changed.append({'path':entry['path'],'before':entry['sha256'],'after':sha(p)})
                patch.extend(difflib.unified_diff(z.read(entry['path']).decode('utf-8-sig',errors='replace').replace('\r\n','\n').splitlines(True),
                    p.read_text(encoding='utf-8-sig').splitlines(True),fromfile='baseline/'+entry['path'],tofile='current/'+entry['path']))
    report['changed_existing_files']=changed
    write(OUT/'verification_and_build.json',report)
    (OUT/'changes_from_board_baseline.patch').write_text(''.join(patch),encoding='utf-8')
    write(OUT/'implementation_attempts.json',{'date':'2026-11-01','selected':PHY,'candidates':candidates,'candidate_synthesis':{'circular_r1':'before exact marquee flag optimization','circular_r2':'exact flags; counters and event timing unchanged'}})
    print(json.dumps({'bitstream':report['bitstream'],'scenarios':count,'resources':current['resources'],
        'setup_violations':current['setup_violations'],'ordinary_setup_violations':ordinary,'hold_violations':current['hold_violations']},indent=2))

if __name__=='__main__':main()
