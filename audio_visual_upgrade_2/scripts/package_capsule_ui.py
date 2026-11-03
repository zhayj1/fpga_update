from pathlib import Path
import json,hashlib,re,zipfile,shutil,difflib
root=Path(__file__).resolve().parents[1]
out=root/'output/capsule_ui_20261101_r1'
syn=root/'prj/td_build/capsule_r5_syn'
phy=root/'prj/td_build/capsule_r5_congestion_seed5_phy'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.resolve().relative_to(root).as_posix()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
build=read(phy/'build_result.json')
assert build['status']=='BUILD_COMPLETE' and build['inputs_unchanged']
for folder in [syn,phy]:
 record=read(folder/'inputs.json')
 for item in record['sources']+record['build_files']:
  assert sha(Path(item['path']))==item['sha256'].lower(),item['path']
 assert sha(root/'scripts/build.ps1')==record['script_sha256'].lower()
bit=phy/'skeleton.bit'
assert sha(bit)==build['bitstream']['sha256'].lower()
tests={}
names=['capsule_spectrum_r5','capsule_core_r6','capsule_board_r5','capsule_text_sdram_r3','capsule_system_r3','typography_row_capsule_r5b','typography_full_rows_capsule_r5b']
for name in names:
 p=root/'sim'/f'{name}_sim_result.json';v=read(p)
 assert v['status'] in ['PASS','COMPILE_PASS'],(name,v['status'])
 mismatch=[path for path,h in v['input_hashes'].items() if sha(Path(path))!=h.lower()]
 assert not mismatch,(name,mismatch)
 tests[name]={'status':v['status'],'scenarios':v.get('expected_scenarios',[]),'evidence':rel(p),'inputs_current':True}
probes={}
for name in ['capsule_startup_r5','capsule_baseline_startup_r1']:
 p=root/'sim'/f'{name}_sim_result.json';v=read(p)
 probes[name]={'status':v['status'],'evidence':rel(p)}
area=(phy/'skeleton_phy.area').read_text(encoding='utf-8')
resources={k:int(re.search(r'^#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ['lut','reg','bram','bram32k','dsp']}
log=(phy/'console.log').read_text(encoding='utf-8',errors='replace')
slices=re.findall(r'(\d+) mslices, (\d+) lslices',log)
resources.update(slices=sum(map(int,slices[-1])),mslices=int(slices[-1][0]),lslices=int(slices[-1][1]))
timing=(phy/'final_timing.rpt').read_text(encoding='utf-8')
groups=[]
pattern=r'Path Group\s*:\s*([^\r\n]+).*?Max\s*: SWNS\s+([\d.-]+)ns, STNS\s+([\d.-]+)ns,\s+(\d+) Viol Endpoints.*?Min\s*: HWNS\s+([\d.-]+)ns, HTNS\s+([\d.-]+)ns,\s+(\d+) Viol Endpoints'
for m in re.finditer(pattern,timing,re.S):
 groups.append({'group':m[1].strip(),'setup_wns_ns':float(m[2]),'setup_endpoints':int(m[4]),'hold_wns_ns':float(m[5]),'hold_endpoints':int(m[7])})
assert groups
tim={'coverage':re.search(r'STA coverage\s*:\s*(\S+)',timing)[1],
 'setup_wns_ns':float(re.search(r'SWNS:\s*([\d.-]+)ns',timing)[1]),
 'hold_wns_ns':float(re.search(r'HWNS:\s*([\d.-]+)ns',timing)[1]),
 'setup_violations':sum(g['setup_endpoints'] for g in groups),
 'hold_violations':sum(g['hold_endpoints'] for g in groups),'groups':groups,
 'non_shifted_setup_violations':sum(g['setup_endpoints'] for g in groups if 'sdr_clk_sft' not in g['group'])}
assert tim['non_shifted_setup_violations']==0 and tim['hold_violations']==0,tim
finalbit=out/'audio_capsule_ui_r1.bit';shutil.copy2(bit,finalbit)
files=set()
for folder in ['rtl','ip','constraints','scripts','tb']:
 files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
for name in names+list(probes):
 v=read(root/'sim'/f'{name}_sim_result.json')
 files.update(Path(p) for p in v['input_hashes'])
files.update(p for p in (root/'sim').glob('modelsim_*.json'))
manifest={rel(p):sha(p) for p in sorted(files)}
save(out/'source_manifest.json',manifest)
with zipfile.ZipFile(out/'sources_and_tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(files):z.write(p,rel(p))
with zipfile.ZipFile(out/'sources_and_tests.zip') as z:
 for name,h in manifest.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
baseline=read(out/'baseline_manifest.json')
changed=[p for p,h in baseline.items() if (root/p).is_file() and sha(root/p)!=h.lower()]
patch=[]
with zipfile.ZipFile(out/'baseline_sources.zip') as z:
 for name in changed:
  try:a=z.read(name).decode('utf-8-sig').splitlines(True);b=(root/name).read_text(encoding='utf-8-sig').splitlines(True)
  except UnicodeError:continue
  patch.extend(difflib.unified_diff(a,b,fromfile='baseline/'+name,tofile='capsule/'+name))
(out/'changes_from_circular.patch').write_text(''.join(patch),encoding='utf-8')
evidence={'date':'2026-11-01','status':'candidate_built_pending_board',
 'scope':'64 radial capsules, 16-level edge AA, all 64 dots retained in silence; existing controls and effects preserved',
 'user_media_correction':'User attributed earlier black screen/fixed tone to TF file format and reported correcting it; no full acceptance of this new bit implied.',
 'selected_synthesis':rel(syn),'selected_physical':rel(phy),'tests':tests,'extended_startup_probes':probes,
 'startup_probe_scope':'Probe executed on r4, before the two text predecode registers; not a passed final startup test.',
 'startup_limit':'100 MHz/180-degree compact-image startup probe has unknown background RGB at 25.8124 ms in pre-change and 25.81244 ms in final capsule sources (one pixel-clock pipeline delay). Root cause unresolved; not a passed startup test. Passing legacy system regression uses 150 MHz and legacy display flags.',
 'resources':resources,'timing':tim,'timing_clean':False,'board_validation':'not_run','changed_baseline_files':changed,
 'bitstream':{'path':rel(finalbit),'bytes':finalbit.stat().st_size,'sha256':sha(finalbit)},
 'source_snapshot':{'path':rel(out/'sources_and_tests.zip'),'sha256':sha(out/'sources_and_tests.zip'),'files':len(manifest)},
 'attempts':['r1: capacity failure, 4949 MSlices','r2 physical: interrupted','r2b: capacity failure, 4907 MSlices / 4908 LSlices','r3: capacity met; 11 added video setup violations, not selected','r4 seed3: video timing met, 11 lyric SDRAM-domain setup violations; not selected','r4 seed2: 4905 MSlices capacity failure','r4 seed5: 7 lyric setup violations; not selected','r5: predecode header and width checks in existing prior states; no added text latency'],
 'no_hardware_writes':True,'no_clock_or_constraint_changes':True}
save(out/'verification_and_build.json',evidence)
for folder,label in [(syn,'synthesis'),(phy,'physical')]:
 d=out/label;d.mkdir(exist_ok=True)
 for p in folder.iterdir():
  if p.is_file() and p.suffix in ['.log','.area','.qor','.rpt','.timing','.json','.cfg','.tcl','.prj']:shutil.copy2(p,d/p.name)
d=out/'simulation';d.mkdir(exist_ok=True)
for name in names+list(probes):
 for p in (root/'sim').glob(name+'_*'):
  if p.is_file():shutil.copy2(p,d/p.name)
print(json.dumps({'bit':evidence['bitstream'],'resources':resources,'timing':{k:v for k,v in tim.items() if k!='groups'},'tests':{k:v['status'] for k,v in tests.items()},'changed':changed},ensure_ascii=False,indent=2))
