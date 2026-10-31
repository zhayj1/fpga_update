"""Verify current TYP2 evidence and collect the final routed bitstream report."""
from pathlib import Path
from datetime import datetime
import hashlib
import importlib.util
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/typography_full_20261030'
SYN='typography_full_r1_syn'
PHY='typography_full_r1_congestion_seed3_phy'
RUNS={'row':'full_r6','full_rows':'full_r6','full_sdram':'full_r6','full_load':'full_r5',
      'layer':'full_r5','core':'full_final','assets':'full_r3','bmp_writeback':'full_r2',
      'font_legacy':'full_r2','legacy_system':'full_final','board':'full_r5'}

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    spec=importlib.util.spec_from_file_location('physical_report',ROOT/'scripts/report_downscale_implementation.py')
    physical=importlib.util.module_from_spec(spec);spec.loader.exec_module(physical)
    syn_inputs,syn_result=physical.verify_build(SYN)
    phy_inputs,phy_result=physical.verify_build(PHY)
    assert syn_inputs['sources']==phy_inputs['sources']
    measured=physical.physical(PHY)
    previous=physical.physical('typography_dspall1_seed3_phy')
    tests={};scenarios=[]
    for name,suffix in RUNS.items():
        path=ROOT/f'sim/typography_{name}_{suffix}_sim_result.json'
        result=read(path)
        assert result['status']==('COMPILE_PASS' if name=='board' else 'PASS'),(name,result['status'])
        changed=[p for p,digest in result['input_hashes'].items() if sha(Path(p))!=digest]
        assert not changed,(name,changed)
        if result.get('sim_log'):
            log=(ROOT/result['sim_log']).read_text(errors='replace')
            passed=re.findall(r'SCENARIO_PASS\s+(\S+)',log)
            assert set(passed)==set(result['expected_scenarios']),(name,passed)
            assert 'TEST_PASS' in log and 'TEST_FAIL' not in log
            scenarios+=passed
        else:passed=[]
        tests[name]={'status':result['status'],'evidence':path.relative_to(ROOT).as_posix(),
            'compile_log':result['compile_log'],'sim_log':result.get('sim_log'),
            'scenarios':passed,'input_hashes_current':True,
            'warning_count':len(set(result.get('warning_lines',[]))),
            'elapsed_seconds':round(result['finished_at']-result['started_at'],2)}
    assets=read(OUT/'asset_check.json')
    assert assets['status']=='PASS'
    for p,digest in assets['input_hashes'].items():assert sha(Path(p))==digest,p
    assert sha(OUT/'card_typography_full.zip')==assets['package_sha256']
    sdram_log=(ROOT/tests['full_sdram']['sim_log']).read_text()
    max_cycles=int(re.search(r'FULL_ROW_MAX_CYCLES (\d+)',sdram_log)[1])
    assert max_cycles<3200
    clean=measured['setup_violations']==measured['hold_violations']==0
    evidence={'status':'BUILD_COMPLETE','generated':datetime.now().astimezone().isoformat(),
        'format':'TYP2','font_bytes':3856960,'glyph_count':7540,'free_sdram_bytes':145152,
        'bitstream':phy_result['bitstream'],'card_package':{'path':str(OUT/'card_typography_full.zip'),
        'sha256':assets['package_sha256']},'synthesis':SYN,'physical':PHY,
        'current':measured,'previous_typ1':previous,'timing_clean':clean,
        'simulation_scenario_count':len(scenarios),'asset_scenario_count':len(assets['scenarios']),
        'tests':tests,'max_contended_row_cycles_100MHz':max_cycles,
        'all_build_inputs_current':True,'all_test_inputs_current':True,
        'routing_attempts':[{'tag':'typography_full_r1_seed3_phy','status':'FAILED','reason':'One x23y59_local6 conflict between reset nets'},
                            {'tag':PHY,'seed':3,'effort':'routability','status':'BUILD_COMPLETE'}],
        'board_validation':'not_run_for_TYP2',
        'validation_limits':['SDRAM controller/device functional model and full-font loader tested; TYP2 SD/FAT end-to-end boot not simulated.',
                             'Legacy SD/FAT/audio/image regression uses TYPOGRAPHY=0; TYP2 memory map independently checked in core and asset tests.',
                             'No post-route timing simulation or new-board download performed.']}
    write(OUT/'verification_and_build.json',evidence)
    r=measured['resources'];old=previous['resources']
    lines=['# 完整 GB2312 字库 TYP2：实现与验证','',
        '日期：2026-10-30；EG4S20BG256；Tang Dynasty 6.2.168116；ModelSim 10.6e。','',
        '完整字库、RTL、功能仿真、综合、布局布线和bit已生成。以后更换GB2312范围内中文歌曲无需重建字库。'
        +' 新TYP2尚未上板；'+('setup/hold均通过。' if clean else '全工程时序尚未收敛，不能把生成bit当作时序通过。'),'',
        '## 交付与换卡','',
        f'- bit：`prj/td_build/{PHY}/skeleton.bit`',
        '- 完整卡包：`output/typography_full_20261030/card_typography_full.zip`',
        '- 字库单文件：`output/typography_full_20261030/sd_card/FONT.HZK`，3,856,960字节。',
        '- 本次必须同时更新bit与FONT.HZK，TYP1旧bit不兼容。其他卡素材可保留。',
        '- 后续换歌只需按项目要求准备WAV、LRC1和图片；不需重新生成字库或综合。',
        '- 范围为GB2312全部7445字符（6763汉字、682符号）与ASCII 0x20..0x7E；不是全Unicode。',
        '- 现有LRC1格式64行、488字记录、歌词每行19字、歌名/歌手各24字等限制不改变。',
        '- 随包仍是原45秒demo音频；45行全歌歌词均有字形，但字库不会延长音频。','',
        '## 显示与资源','',
        '华文琥珀24px歌词/歌名、20px歌手及16级覆盖率保留；OSD幼圆16px不变。'
        '独立比较原70个字形的64,280个有效像素，全部相同。新增少数字形仅平移不到一个显示像素以避免越界，未裁切或缩字。','',
        '四组640×480背景、四组240×240封面、两份歌词表与完整字库共8,243,456字节，8MiB SDRAM剩余145,152字节（141.75KiB）。'
        '字形去掉32像素行填充；保留固定编码槽直接寻址，省去逐字目录读取；共用32bit移位器及一笔LRC读取的两条记录，无新增BRAM/DSP。','',
        '|资源|TYP1物理结果|TYP2物理结果|变化|','|---|---:|---:|---:|']
    for label,key,total in [('Slice','slices',9800),('LUT','lut',19600),('寄存器','registers',19600),
                            ('BRAM9K','bram9k',64),('BRAM32K','bram32k',16),('DSP','dsp',29)]:
        lines.append(f'|{label}|{old[key]}/{total}|{r[key]}/{total}|{r[key]-old[key]:+d}|')
    lines+=['','综合口径：LUT17668→17711，寄存器11218→11134；与表中布局布线后的物理口径分开统计。','',
        '## 验证与时序','',
        f'{len(scenarios)}个功能自检场景、4个独立素材检查及板级展开通过，输入哈希与当前文件一致。',
        'PC检查全部7540字形的两字号，共7,359,040个存储像素；使用独立字节解析器验证两份LRC各45行，纠正旧生成器把8word头长度当行数的问题。',
        '真实3,856,960字节文件经font_load和公共FIFO/writeback逐字比对，覆盖2MiB边界、尾部、补零、短文件、容量/地址/整数溢出拒绝与恢复。',
        '真实厂商加密SDRAM控制器与IS42s32200模型运行100MHz：完整字库写入后读遍7540字符两字号；首末字形全部行、LRC最后记录、四路图片争用均自检。',
        f'争用测试同时读取两背景及两封面共1320word，覆盖19/24字符、两字号、中文/ASCII/符号、每一字形行及奇偶LRC起点；最慢{max_cycles}拍，即{max_cycles/100:.2f}μs，小于32μs行周期。该数值是模型场景结果，不是板级时序证明。',
        'TYP2装载/显示映射、四槽轮转、双歌词切换、混色/OSD对齐、取消与迟到恢复均验证。旧模式真实SPI/FAT/音频/图片切换回归另行通过。',
        '未做TYP2从SD/FAT启动到字幕的完整整机仿真，也未做新bit上板验证；上述验证层级不混同。','',
        f"setup WNS {measured['setup_wns_ns']:+.3f}ns，TNS {measured['setup_tns_ns']:.3f}ns，违例端点{measured['setup_violations']}个；"
        f"hold WNS {measured['hold_wns_ns']:+.3f}ns，违例{measured['hold_violations']}个。STA coverage {measured['sta_coverage_percent']:.2f}%。",'',
        '|时钟组|setup WNS/ns|setup违例端点|','|---|---:|---:|']
    for group,g in measured['groups'].items():lines.append(f"|{group}|{g['setup_ns']:+.3f}|{g['setup_violations']}|")
    lines+=['','未通过全部setup时序时，本bit仅作为待上板验证的功能候选。首轮在x23y59_local6发生两条复位网的局部布线冲突；保持综合网表和种子3，针对拥塞改用routability布线策略。未修改约束来隐藏违例，也未循环更换布局种子。','',
        '## 证据','',f'- 资源/时序：`prj/td_build/{PHY}/route.qor`、`skeleton_phy.area`、`final_timing.rpt`。',
        '- 汇总及每项日志：`output/typography_full_20261030/verification_and_build.json`。',
        '- 全字库像素、LRC和包校验：`output/typography_full_20261030/asset_check.json`。',
        '- 冻结格式与存储契约：`doc/spec/full_font_behavior_spec.md`。',
        f"- bit SHA256：`{phy_result['bitstream']['sha256']}`。",
        f"- 卡包 SHA256：`{assets['package_sha256']}`。",'']
    (ROOT/'doc/compile/full_font_report.md').write_text('\n'.join(lines),encoding='utf-8')
    state=read(ROOT/'doc/workflow/state.json')
    state['full_font'].update(status='completed',stages={k:'completed' for k in ('architecture','assets','rtl','verification','implementation')},
        implementation=evidence,next_step='用户将新TYP2 bit与完整FONT.HZK配套上板；全工程setup仍需后续结构优化' if not clean else '用户将新TYP2 bit与完整FONT.HZK配套上板')
    for repair in state['full_font']['repairs']:repair['status']='verified; see final current-source evidence'
    write(ROOT/'doc/workflow/state.json',state)
    write(ROOT/'doc/workflow/quality_reports/full_font.json',{
        'skill':'fpga-workflow','status':'completed','verification_level':'functional_simulation_and_routed_bitstream',
        'report':'doc/compile/full_font_report.md','timing_clean':clean,'board_validated':False,
        'evidence':'output/typography_full_20261030/verification_and_build.json',
        'missing_files':[],'reason':'Complete GB2312+ASCII font and matching bit generated; see explicit STA and board limitations.'})
    print(json.dumps({'resources':r,'setup_wns_ns':measured['setup_wns_ns'],
        'setup_violations':measured['setup_violations'],'hold_violations':measured['hold_violations'],
        'functional_scenarios':len(scenarios),'bitstream':phy_result['bitstream']},ensure_ascii=False))


if __name__=='__main__':main()
