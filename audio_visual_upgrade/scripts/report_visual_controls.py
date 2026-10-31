"""Audit current visual-control sources, verification and physical delivery."""
from pathlib import Path
from collections import Counter
from datetime import datetime
import json, hashlib, re, shutil
from report_downscale_implementation import physical, verify_build, warning_lines
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/visual_controls_aa_20261031'
SYN='visual_r9_syn';PHY='visual_r9_congestion_seed3_phy';BASE='osdcorner_r1_congestion_seed3_phy'
CHECKS=['visual_mailbox_r1','visual_core_normalized_r1','visual_osd_final_r1','osd_final_r1',
        'geometry_visual_r1','numeric_visual_r1','font_pixel_visual_r2','controls_shared_r1',
        'catalog_visual_r1','catalog_legacy_visual_r5','layout_sdram_visual_r4',
        'full_load_visual_r4','bmp_writeback_visual_r4','legacy_system_normalized_r1','board_visual_final_r1']
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 tests={}
 for n in CHECKS:
  p=ROOT/f'sim/typography_{n}_sim_result.json';d=read(p)
  expected='COMPILE_PASS' if n.startswith('board_') else 'PASS'
  assert d['status']==expected and d['compile_exit_code']==0,(n,d['status'])
  for f,h in d['input_hashes'].items():assert sha(Path(f))==h.lower(),f
  scenarios=[]
  if expected=='PASS':
   assert d['sim_exit_code']==0
   log=(ROOT/d['sim_log']).read_text(errors='replace')
   scenarios=re.findall(r'SCENARIO_PASS\s+(\S+)',log)
   assert sorted(scenarios)==sorted(d['expected_scenarios']) and len(set(scenarios))==len(scenarios),n
   assert len(re.findall(r'\bTEST_PASS\b',log))==1 and 'TEST_FAIL' not in log,n
  tests[n]=dict(status=expected,evidence=p.relative_to(ROOT).as_posix(),scenarios=scenarios,
                input_hashes_current=True,warnings=d.get('warning_lines',[]))
 si,sr=verify_build(SYN);pi,pr=verify_build(PHY)
 assert si['sources']==pi['sources']
 for d in (si,pi):assert d['script_sha256'].lower()==sha(ROOT/'scripts/build.ps1')
 old=physical(BASE);cur=physical(PHY)
 timing_clean=cur['setup_violations']==cur['hold_violations']==0
 normal=sum(g['setup_violations'] for n,g in cur['groups'].items() if 'sdr_clk_sft' not in n)
 bit=OUT/'audio_visual_controls_aa.bit'
 shutil.copy2(Path(pr['bitstream']['path']),bit)
 assert sha(bit)==pr['bitstream']['sha256'].lower()
 generated=read(OUT/'generated.json')
 for asset in generated['assets']:assert sha(OUT/'sd_card'/asset['file'])==asset['sha256']
 import zipfile
 with zipfile.ZipFile(OUT/'S01_cover_aa.zip') as z:assert set(z.namelist())=={'S01CV1.BMP','S01CV2.BMP','S01CV3.BMP','README.txt'}
 warnings={}
 for name,base,new in [('syn','osdcorner_r1_syn',SYN),('phy',BASE,PHY)]:
  a,b=Counter(warning_lines(base)),Counter(warning_lines(new))
  warnings[name]=dict(current=list(b.elements()),added=list((b-a).elements()),removed=list((a-b).elements()))
 count=sum(len(d['scenarios']) for d in tests.values())
 evidence=dict(generated=datetime.now().astimezone().isoformat(),status='completed_implementation' if timing_clean else 'completed_implementation_timing_unmet',
   tests=tests,scenario_count=count,baseline=old,current=cur,ordinary_setup_endpoints=normal,timing_clean=timing_clean,
   synthesis_result=sr,physical_result=pr,warnings=warnings,
   warning_review='New synthesis BYTE_ENABLE=0 ROM bea/beb warnings match the vendor-model convention; both pins are explicitly tied to zero. Remaining optional-output/TB stub/novopt warnings retained. Physical location/timing warnings are not suppressed.',
   bitstream=dict(path=bit.relative_to(ROOT).as_posix(),bytes=bit.stat().st_size,sha256=sha(bit)),
   sd_package=dict(path='output/visual_controls_aa_20261031/S01_cover_aa.zip',sha256=sha(OUT/'S01_cover_aa.zip'),assets=generated['assets'],font_update_required=False),
   board_validation='not_run',validation_limits=[
    'Contour antialiasing only; internal photograph downscaling retains its original sampling algorithm.',
    'SD/FAT integration uses small normalized targets, legacy typography and an HDMI stub. Production geometry/AA/text/OSD and font SDRAM are checked in focused regressions.',
    'No post-route simulation or board download. Existing timing deficits are reported explicitly.'],
   capacity_attempts=[dict(tag='visual_r3_congestion_seed3_phy',mslice=5085,lslice=5086,status='capacity_failed'),dict(tag='visual_r6_congestion_seed3_phy',mslice=5008,lslice=5008,status='capacity_failed'),dict(tag=PHY,status='BUILD_COMPLETE')])
 write(OUT/'verification_and_build.json',evidence)
 lines=['# 封面抗锯齿与视觉设置交付','',
  '仅按第一组 S01 标准：封面画布 240×240，中心 (160,165)，可见轮廓半轴 100/120；正常及回弹 240/250/256/260 均采用 16 级覆盖率，与实时底图混合，换图淡入淡出保留。照片内部沿用原缩小采样。','',
  '右下角 OSD 保持 200×224，原三页后新增颜色和效果两页。六项颜色：频谱白→所选色、歌词已唱、歌词其余、歌名、歌手、波纹；五项效果：扩散圆环、封面回弹、柱顶尖峰、频谱柱、色彩联动。默认全开。字体、五行歌词、布局和滚动方式保持。','',
  '资源优化：目录有效性按歌曲归约；调节运算共用；颜色滤镜精确代数合并；10 位图像几何；OSD 逐像素字库及精确数字/条宽 ROM；稳定跨域邮箱减少冗余副本；装载器和显示层共用固定目标尺寸，保留 BMP_DOWNSCALE=0 的动态尺寸。没有删减选色、效果或抗锯齿级数。','',
  f'{count} 个自检场景及真实板顶层编译展开通过，所有证据输入哈希与当前文件匹配。关键核对包括 212,992 组滤镜新旧公式、2,036,640 拍图像几何、32,768 个字库像素、4,096 组数字/条宽、四种封面尺寸、完整 OSD 页和 640×480 合成帧。SD/FAT/SDRAM 缩小装载、切歌、PCM 与视频流回归通过。','',
  '|资源|原上板版本|本版本|','|---|---:|---:|']
 for label,key,total in [('Slice','slices',9800),('LUT','lut',19600),('FF','registers',19600),('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
  lines.append(f'|{label}|{old["resources"][key]}/{total}|{cur["resources"][key]}/{total}|')
 lines+=['',f'Setup 违例 {old["setup_violations"]} → {cur["setup_violations"]}，本版非移相组 {normal}；Hold {cur["hold_violations"]}。WNS {cur["setup_wns_ns"]} ns，TNS {cur["setup_tns_ns"]} ns。',
  '时序已闭合。' if timing_clean else '时序尚未闭合，bit 是待上板验证的候选版本，不能把生成 bit 当作时序通过。未更改频率、PLL、管脚或 SDC，未添加 false path/multicycle。',
  '', '|路径组|Setup/ns|违例端点|','|---|---:|---:|']
 for name,g in cur['groups'].items():lines.append(f'|{name}|{g["setup_ns"]:+.3f}|{g["setup_violations"]}|')
 lines+=['','## 上板文件','',
  '- bit：output/visual_controls_aa_20261031/audio_visual_controls_aa.bit',
  '- 素材：output/visual_controls_aa_20261031/S01_cover_aa.zip，仅覆盖三张 S01CV*.BMP。',
  '- 完整 FONT.HZK 保持，不能用旧 card 目录整体覆盖 SD 卡。',
  '- KEY4 长按约 0.6 秒显隐，短按切项目/翻页；KEY2/3 减加，效果页分别关闭/开启。设置切歌保留、复位恢复默认。','',
  f'bit SHA256：{sha(bit)}','',
  '证据：output/visual_controls_aa_20261031/verification_and_build.json',
  f'实现：prj/td_build/{PHY}/final_timing.rpt','',
  '仿真限制：SD 系统回归使用缩小目标及旧字库模式；新完整字库、五行取字、像素合成分别做专项测试。未做带延迟后仿真，未下载或上板。','']
 report=ROOT/'doc/compile/visual_controls_aa_report.md';report.write_text('\n'.join(lines),encoding='utf-8')
 (OUT/'README.md').write_text('\n'.join(lines),encoding='utf-8')
 p=ROOT/'doc/workflow/state.json';state=read(p);v=state['visual_controls_aa'];v.update(status=evidence['status'],report=report.relative_to(ROOT).as_posix(),evidence='output/visual_controls_aa_20261031/verification_and_build.json',bitstream=evidence['bitstream'],timing_clean=timing_clean,board_validation='not_run',next_step='Board validation with matching S01 assets; review reported timing deficits.')
 v['stages'].update(rtl='completed',simulation='completed',synthesis='completed',physical='completed',board='pending')
 v['physical_capacity']['outcome']='capacity_met';v['physical_capacity']['attempts'][-1]['result']='BUILD_COMPLETE'
 state['status']=evidence['status'];write(p,state)
 write(ROOT/'doc/workflow/quality_reports/visual_controls_aa.json',dict(status='completed',verification_level='simulation_and_physical_implementation',timing_clean=timing_clean,missing_files=[],evidence=v['evidence'],reason='S01 AA and six colors/five toggles delivered; timing and board limits explicit.'))
 print(json.dumps(dict(bit=evidence['bitstream'],resources=cur['resources'],setup=cur['setup_violations'],hold=cur['hold_violations'],ordinary=normal,scenarios=count),indent=2))
if __name__=='__main__':main()
