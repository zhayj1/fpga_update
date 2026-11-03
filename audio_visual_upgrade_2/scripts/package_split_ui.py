from pathlib import Path
import json, hashlib, re, zipfile, shutil, difflib, argparse
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--physical',required=True);p.add_argument('--synthesis',required=True)
p.add_argument('--output',default='output/split_ui_20261101_r1');p.add_argument('--release',default='r1')
p.add_argument('--test-suffix',default='r18');p.add_argument('--capacity14',action='store_true')
p.add_argument('--allow-timing-failure',action='store_true',help='Package an explicitly requested experimental bit with failed STA prominently recorded')
a=p.parse_args()
out=root/a.output;syn=root/'prj/td_build'/a.synthesis;phy=root/'prj/td_build'/a.physical

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.resolve().relative_to(root).as_posix()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

build=read(phy/'build_result.json')
assert build['status']=='BUILD_COMPLETE' and build['inputs_unchanged'],build
build_inputs=[]
for folder in [syn,phy]:
 record=read(folder/'inputs.json')
 for item in record['sources']+record['build_files']:
  file=Path(item['path']);assert sha(file)==item['sha256'].lower(),str(file);build_inputs.append(file)
 assert sha(root/'scripts/build.ps1')==record['script_sha256'].lower()
bit=phy/'skeleton.bit';assert sha(bit)==build['bitstream']['sha256'].lower()
names=['split_pick_r18','split_legacy_pick_r9',*[f'split_{check}_{a.test_suffix}' for check in ['text','text_sdram','legacy_text']],
       'split_spectrum_r13',*[f'split_{check}_{a.test_suffix}' for check in ['core','board']],'split_blend_r13',f'split_system_{a.test_suffix}']
tests={};test_inputs=[]
for name in names:
 file=root/'sim'/f'{name}_sim_result.json';v=read(file)
 assert v['status']==('COMPILE_PASS' if name.startswith('split_board_') else 'PASS'),(name,v['status'])
 for path,h in v['input_hashes'].items():
  assert sha(Path(path))==h.lower(),(name,path);test_inputs.append(Path(path))
 tests[name]={'status':v['status'],'scenarios':v.get('expected_scenarios',[]),'evidence':rel(file),'inputs_current':True}
selected=read(phy/'inputs.json')
area=(phy/'skeleton_phy.area').read_text(encoding='utf-8')
resources={k:int(re.search(r'^#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ['lut','reg','bram','bram32k','dsp']}
log=(phy/'console.log').read_text(encoding='utf-8',errors='replace');slices=re.findall(r'(\d+) mslices, (\d+) lslices',log)
resources.update(slices=sum(map(int,slices[-1])),mslices=int(slices[-1][0]),lslices=int(slices[-1][1]))
timing=(phy/'final_timing.rpt').read_text(encoding='utf-8');groups=[]
pattern=r'Path Group\s*:\s*([^\r\n]+).*?Max\s*: SWNS\s+([\d.-]+)ns, STNS\s+([\d.-]+)ns,\s+(\d+) Viol Endpoints.*?Min\s*: HWNS\s+([\d.-]+)ns, HTNS\s+([\d.-]+)ns,\s+(\d+) Viol Endpoints'
for m in re.finditer(pattern,timing,re.S):groups.append({'group':m[1].strip(),'setup_wns_ns':float(m[2]),'setup_endpoints':int(m[4]),'hold_wns_ns':float(m[5]),'hold_endpoints':int(m[7])})
assert groups
tim={'coverage':re.search(r'STA coverage\s*:\s*(\S+)',timing)[1],'setup_wns_ns':float(re.search(r'SWNS:\s*([\d.-]+)ns',timing)[1]),'hold_wns_ns':float(re.search(r'HWNS:\s*([\d.-]+)ns',timing)[1]),'setup_violations':sum(g['setup_endpoints'] for g in groups),'hold_violations':sum(g['hold_endpoints'] for g in groups),'groups':groups,'non_shifted_setup_violations':sum(g['setup_endpoints'] for g in groups if 'sdr_clk_sft' not in g['group'])}
candidate_timing_ok=tim['non_shifted_setup_violations']==0 and tim['hold_violations']==0
assert candidate_timing_ok or a.allow_timing_failure,tim
finalbit=out/f'audio_split_ui_{a.release}.bit';shutil.copy2(bit,finalbit)
files=set(build_inputs+test_inputs)
for folder in ['rtl','ip','constraints','scripts','tb']:
 files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(p for p in (root/'sim').glob('modelsim_*.json'));files.add(root/'sim/run.py');files.add(root/'sim/modelsim_run.py');files.add(root/'prj/skeleton.al')
manifest={rel(p):sha(p) for p in sorted(files)};save(out/'source_manifest.json',manifest)
with zipfile.ZipFile(out/'sources_and_tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for file in sorted(files):z.write(file,rel(file))
with zipfile.ZipFile(out/'sources_and_tests.zip') as z:
 for name,h in manifest.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
baseline=read(out/'baseline_manifest.json');baseline={k.replace('\\','/'):v for k,v in baseline.items()}
changed=[name for name,h in baseline.items() if (root/name).is_file() and sha(root/name)!=h.lower()]
added=sorted(set(manifest)-set(baseline));patch=[]
with zipfile.ZipFile(out/'baseline_sources.zip') as z:
 zipnames={name.replace('\\','/'):name for name in z.namelist()}
 for name in changed:
  try:before=z.read(zipnames[name]).decode('utf-8-sig').replace('\r\n','\n').splitlines(True);after=(root/name).read_text(encoding='utf-8-sig').splitlines(True)
  except UnicodeError:continue
  patch.extend(difflib.unified_diff(before,after,fromfile='previous/'+name,tofile='split/'+name))
 for name in added:
  if not name.startswith(('rtl/','tb/','scripts/','sim/modelsim_split')):continue
  try:after=(root/name).read_text(encoding='utf-8-sig').splitlines(True)
  except UnicodeError:continue
  patch.extend(difflib.unified_diff([],after,fromfile='/dev/null',tofile='split/'+name))
(out/'changes_from_previous.patch').write_text(''.join(patch),encoding='utf-8')
limitations={'timing':'The previous capsule build already had 64 SDRAM shifted-interface setup violations, WNS -5.565 ns. See this build timing groups for actual values. Full STA closure is not claimed. No clock/constraint relaxation was introduced.', 'system_regression':f'Passing split_system_{a.test_suffix} is the legacy 150 MHz integration fixture with legacy display flags. It is not production startup proof; split UI has separate text/spectrum/core tests.', 'startup':'The previous capsule and pre-capsule production compact-image startup probes both showed unknown background RGB. Root cause unresolved. No new successful production startup probe is claimed.', 'board':'Not tested on hardware. No board, TF or Flash writes performed.', 'preview':'RTL text and spectrum over current cover/background, using test metadata and lyrics. OSD omitted. Not a board capture.'}
evidence={'date':'2026-11-01','status':'candidate_built_pending_board','scope':'640x480 equal split: cover and capsule spectrum at left; title/artist and seven lyric rows at right, fourth row current with progressive highlighting, vertical scroll and marquee retained. Silence dots, controls, audio and effects retained.','selected_synthesis':rel(syn),'selected_physical':rel(phy),'selected_strategy':{'seed':selected['seed'],'route_effort':selected['route_effort']},'tests':tests,'resources':resources,'timing':tim,'timing_clean':tim['setup_violations']==0 and tim['hold_violations']==0,'limitations':limitations,'changed_baseline_files':changed,'added_snapshot_files':added,'bitstream':{'path':rel(finalbit),'bytes':finalbit.stat().st_size,'sha256':sha(finalbit)},'source_snapshot':{'path':rel(out/'sources_and_tests.zip'),'sha256':sha(out/'sources_and_tests.zip'),'files':len(manifest)},'no_hardware_writes':True,'no_clock_or_constraint_changes':True}
save(out/'verification_and_build.json',evidence)
if not candidate_timing_ok:
 evidence['status']='experimental_bit_timing_failed_pending_board'
 evidence['timing_failure_delivery_authorization']='User explicitly requested a bit even if checks fail, with error evidence preserved, 2026-11-01.'
 evidence['limitations']['new_timing']='New non-shifted setup/hold violations remain; this experimental bit is not timing-qualified. See final_timing.rpt.'
for folder,label in [(syn,'synthesis'),(phy,'physical')]:
 dest=out/label;dest.mkdir(exist_ok=True)
 for file in folder.iterdir():
  if file.is_file() and file.suffix in ['.log','.area','.qor','.rpt','.timing','.json','.cfg','.tcl','.prj']:shutil.copy2(file,dest/file.name)
dest=out/'simulation';dest.mkdir(exist_ok=True)
for name in names:
 for file in (root/'sim').glob(name+'_*'):
  if file.is_file():shutil.copy2(file,dest/file.name)
if a.capacity14:
 evidence['scope']+=' Lyric glyphs use native 20px size in a centered 280px window (x340..619), fitting 14 Chinese characters; longer lines keep marquee. Metadata size and seven-row pitch unchanged.'
 evidence['lyric_layout']={'chinese_visible_capacity':14,'glyph_pixels':20,'window_x':340,'window_width':280,'row_pitch':32,'glyph_y_inset':0,'overflow':'marquee'}
save(out/'verification_and_build.json',evidence)
capacity_note='\n歌词复用现有 20×20 像素汉字字形，窗口 x340..619、宽 280 像素，一行完整容纳 14 个汉字；15 字及更长歌词继续横向滚动，不截断内容。七行起始位置和 32 像素行距不变，复用字形渲染通路。歌名、歌手字号不变。英文和数字沿用比例字宽，因此可能同时显示更多字符。14 字静止和 15 字横滚的边界用例均进行逐像素校验，并覆盖真实 SDRAM 争用。\n' if a.capacity14 else ''
readme=f'''# 左右分区界面 {a.release}（待上板验证）

640×480 画面中轴分区：左侧封面和胶囊频谱；右侧上方歌名、歌手，下方七行歌词，第四行为当前句，上下各三句。保留逐字高亮、滚行、长句横向滚动、静音圆点、抗锯齿、原音频和按键/OSD/动效功能。
{capacity_note}

- 下载候选：{finalbit.name}
- 字节数：{finalbit.stat().st_size}
- SHA256：{sha(finalbit)}
- 综合：{a.synthesis}
- 布局布线：{a.physical}
- 资源：Slice {resources['slices']}/9800；LUT {resources['lut']}/19600；REG {resources['reg']}/19600；9K BRAM {resources['bram']}/64；32K BRAM {resources['bram32k']}/16；DSP {resources['dsp']}/29。

## 验证

七行选择和渲染、逐字高亮、长句和歌名/歌手横滚、八槽滚行、RAM 同址访问、真实 SDRAM 争用、频谱逐像素等价/静音圆点、整屏合成和旧模式回归均通过。混色计算通过 256×256×16 穷举；板级顶层仅编译通过。最终证据输入哈希与当前源码匹配。详细结果见 verification_and_build.json 和 simulation/。

整机回归使用旧版 150 MHz 小镜像测试环境及旧显示模式；不能替代生产参数下的完整启动验证。七行界面由独立的文本、频谱和合成仿真验证。此前生产参数紧凑镜像启动探针在改动前基线也出现背景 RGB 未知值，原因尚未解决，未声称该项通过。

## 时序和上板状态

本版非移相域 setup 违例 {tim['non_shifted_setup_violations']}，hold 违例 {tim['hold_violations']}。完整 STA 仍有 {tim['setup_violations']} 个 setup 违例，最差 {tim['setup_wns_ns']} ns；详见 physical/final_timing.rpt。旧胶囊版已有 64 个 SDRAM 移相接口 setup 违例（-5.565 ns）。未放宽时钟或约束，不声称完整时序收敛。

尚未上板验证，未下载硬件、写 TF 或 Flash。请使用本目录的确切 bit，复用当前已正常工作的 TF 素材，验证音画、七行高亮和滚动、静音圆点及按键功能。

## 文件

- sources_and_tests.zip / source_manifest.json：源码和测试快照及 SHA256。
- changes_from_previous.patch：相对修改前快照的差异。
- baseline_sources.zip / baseline_manifest.json：修改前现场快照，保持原样。
- split_ui_preview.png：静音/音乐布局预览。素材和背景来自当前工程，文字来自测试数据，未含 OSD，非板上截图。
- synthesis/、physical/、simulation/：选定版本报告。历次失败构建保留在工程 prj/td_build/，不覆盖。

## 复现

构建脚本还使用同级 music_screen_area_opt/prj/td_build/ 中 timing_repair_v3_syn 与 timing_repair_v3_seed3_phy 的工程模板；复现需保留这些原工作区模板和本机 TD/ModelSim 工具。实际选定构建的 .prj/.cfg/.tcl 已收入快照与报告目录。

```powershell
.\\scripts\\build.ps1 -Stage syn -Tag <新综合编号>
.\\scripts\\build.ps1 -Stage phy -Tag <新物理编号> -SynthesisTag <新综合编号> -RouteEffort {selected['route_effort']} -Seed {selected['seed']} -GenerateBitstream
python -B scripts/verify_split_ui.py pick text text_sdram core spectrum board system legacy_text legacy_pick --suffix <新测试编号>
```

工程当前已接近资源上限，七行共享原字形渲染通路；滚动状态和频谱常量积使用片内 RAM 以节省逻辑，未增加帧缓存。
'''
if not candidate_timing_ok:
 readme=readme.replace('（待上板验证）','（实验版：时序未通过，待上板验证）',1)
 readme=readme.replace('\n\n640×480',f'\n\n**用户要求先提供 bit 并保留错误证据。本版仍有 {tim["non_shifted_setup_violations"]} 个新增非移相域 setup 违例，hold 违例 {tim["hold_violations"]}；属于实验版，不代表时序验收通过。**\n\n640×480',1)
(out/'README.md').write_text(readme,encoding='utf-8')
with (out/'WORK.md').open('a',encoding='utf-8') as f:f.write(f'\nFinal candidate: {a.physical}; bit SHA256 {sha(finalbit)}. Functional tests PASS / board compile PASS. Non-shift setup {tim["non_shifted_setup_violations"]}, hold {tim["hold_violations"]}; full setup {tim["setup_violations"]}, WNS {tim["setup_wns_ns"]} ns. Board not run. See README.md for inherited timing/startup limitations.\n')
print(json.dumps({'bit':evidence['bitstream'],'snapshot':evidence['source_snapshot'],'resources':resources,'timing':{k:v for k,v in tim.items() if k!='groups'},'tests':{k:v['status'] for k,v in tests.items()}},ensure_ascii=False,indent=2))
