"""Audit current typography evidence and write the final simulation handoff."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/typography_implementation_20261029'
RUNS={
    'blend':'typography_blend_r1', 'row':'typography_row_r2',
    'layer':'typography_layer_r2', 'osd':'typography_osd_r3',
    'core':'typography_core_r1', 'assets':'typography_assets_r1',
    'controls':'typography_controls_r1', 'legacy_system':'typography_legacy_system',
    'board':'typography_board_final',
}
LIMITS=[
    '尚未执行本次字体版本的综合、布局布线、STA和上板；没有新bit或实际资源占用结论。',
    '新模式未运行真实SD/FAT到新字库整机fixture；通过真实字库逐行取数/双时钟文字层、字库装载控制、顶层混合专项组合验证。',
    '整机回归使用TYPOGRAPHY=0旧字库、小尺寸BMP目标和HDMI stub；覆盖原SPI/FAT/SDRAM、切歌、PCM和视频链。',
    '新模式顶层专项force图层像素及控制参数，验证真实颜色/渐变/文字混色/OSD流水；存储与取字分别由其他专项覆盖。',
    '新增或修改LRC后须重新生成字库；当前包仅含全部现用字符及验证字符，不是完整GB2312/ASCII字库。',
    '已ack读事务永久不返回done时，取字引擎停在DRAIN直到系统复位；超时/取消后不复用仍在途事务。',
    'gap_cnt仅统计HS时mailbox尚未ack次数，不能作为完整缺行计数。',
]
REPAIRS=[
    {'area':'TB取字变量名','attempts':1,'cause':'small是Verilog保留字',
     'change':'改为small_sel','status':'verified','failure':'sim/typography_row_r1_compile_compile.log'},
    {'area':'TB逐字高亮边界','attempts':1,'cause':'独立参考把追梦G的宽度误填为62，真实24+24+17=65',
     'change':'按真实字宽修正TB边界，RTL未改','status':'verified','failure':'sim/typography_layer_r1_sim.log'},
    {'area':'OSD字模路径配置','attempts':1,'cause':'runner读取library级defines，source级OSD_SIM未生效',
     'change':'将OSD_SIM移到library配置','status':'verified','failure':'sim/typography_osd_r1_sim.log'},
    {'area':'OSD对比基准条末像素','attempts':1,'cause':'缩小后的901定点系数在130%时仅175像素',
     'change':'系数902，极值176像素，保留全部像素断言','status':'verified','failure':'sim/typography_osd_r2_sim.log'},
]


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def audit():
    evidence={}
    for key,prefix in RUNS.items():
        result_path=ROOT/'sim'/f'{prefix}_sim_result.json'
        result=json.loads(result_path.read_text(encoding='utf-8'))
        expected_status='COMPILE_PASS' if key=='board' else 'PASS'
        assert result['status']==expected_status,(key,result['status'])
        assert result['compile_exit_code']==0 and result['batch_exit_code']==0
        if key!='board': assert result['sim_exit_code']==0
        changed=[p for p,sha in result['input_hashes'].items()
                 if not Path(p).is_file() or digest(Path(p))!=sha]
        assert not changed,(key,changed)
        expected=result['expected_scenarios']
        if key!='board':
            log=(ROOT/result['sim_log']).read_text(encoding='utf-8')
            passed=re.findall(r'^#?\s*SCENARIO_PASS\s+(\S+)',log,re.M)
            assert len(passed)==len(set(passed)) and set(passed)==set(expected),(key,passed)
            assert len(re.findall(r'^#?\s*TEST_PASS\s*$',log,re.M))==1
            assert not re.search(r'^#?\s*TEST_FAIL\b',log,re.M)
        evidence[key]={
            'status':result['status'],'result':result_path.relative_to(ROOT).as_posix(),
            'compile_log':result['compile_log'],'sim_log':result['sim_log'],
            'scenarios':expected,'changed_inputs':changed,
            'duration_seconds':round(result['finished_at']-result['started_at'],2),
            'unique_warning_count':len(set(result.get('warning_lines',[]))),
            'command':result['command'],'tool_version':result['tool_version'],
            'config_top':result['config']['dut_top'],
        }
    return evidence


def main():
    evidence=audit()
    assets=json.loads((OUT/'asset_check.json').read_text(encoding='utf-8'))
    assert assets['status']=='PASS'
    for name,sha in assets['input_hashes'].items(): assert digest(Path(name))==sha,name
    assert digest(OUT/'card_typography.zip')==assets['package_sha256']
    baseline=json.loads((OUT/'baseline_manifest.json').read_text(encoding='utf-8'))
    delta=[p for p,v in baseline.items() if digest(ROOT/p)!=v['sha256']]
    # Preserve the withdrawn cover work and the legacy renderer.
    assert digest(ROOT/'rtl/gfx/layer_text.v')==baseline['rtl/gfx/layer_text.v']['sha256']
    card_same=all((OUT/'sd_card'/p.name).read_bytes()==p.read_bytes()
                  for p in (ROOT/'card').iterdir() if p.is_file() and p.suffix.upper() not in ('.HZK','.JSON'))
    assert card_same
    bit=ROOT/'prj/td_build/bmp_downscale_r1_seed3_phy/skeleton.bit'
    assert digest(bit)=='6d415526c16e01255c466c3c082de798d37e4867d1cd3560f52b3c36643656a3'
    source_paths=set()
    for folder in ('rtl','scripts','tb'):
        source_paths.update(p for p in (ROOT/folder).rglob('*') if p.is_file()
                            and p.suffix.lower() in ('.v','.vh','.py','.ps1','.dath','.json'))
    source_paths.update((ROOT/'sim').glob('modelsim*.json'))
    for result in RUNS.values():
        raw=json.loads((ROOT/'sim'/f'{result}_sim_result.json').read_text(encoding='utf-8'))
        source_paths.update(Path(p) for p in raw['input_hashes'])
    source_paths.update((ROOT/'prj/skeleton.al',ROOT/'doc/spec/typography_behavior_spec.md'))
    source_manifest={p.relative_to(ROOT).as_posix():{'bytes':p.stat().st_size,'sha256':digest(p)}
                     for p in sorted(source_paths)}
    write_json(OUT/'final_source_manifest.json',source_manifest)
    screenshots={}
    for filename,result,dump in (
        ('osd_sim_three_pages.png','osd','typography_osd_actual.mem'),
        ('core_sim_alignment.png','core','typography_core_actual.mem')):
        screenshots[filename]={'sha256':digest(OUT/filename),'origin':evidence[result]['result'],
                               'dump':'sim/'+dump,'dump_sha256':digest(ROOT/'sim'/dump),
                               'kind':'actual_simulation_pixels'}
    scenario_count=sum(len(e['scenarios']) for e in evidence.values())
    verified={
        'status':'completed_simulation','generated_at_utc':datetime.now(timezone.utc).isoformat(),
        'evidence':evidence,'asset_check':'output/typography_implementation_20261029/asset_check.json',
        'simulation_scenarios':scenario_count,'asset_scenarios':len(assets['scenarios']),
        'source_manifest':'output/typography_implementation_20261029/final_source_manifest.json',
        'changed_baseline_files':delta,'legacy_renderer_unchanged':True,
        'card_audio_images_lyrics_unchanged':card_same,
        'new_bitstream':None,'synthesis':'not_run','place_route':'not_run','timing':'not_run',
        'board_validation':'not_run','screenshots':screenshots,'repairs':REPAIRS,'limitations':LIMITS,
        'card_package':{'path':'output/typography_implementation_20261029/card_typography.zip',
                        'sha256':assets['package_sha256']},
    }
    write_json(OUT/'verification_summary.json',verified)
    state_path=ROOT/'doc/workflow/state.json'
    state=json.loads(state_path.read_text(encoding='utf-8'))
    if state.get('active_stage')!='typography':
        state.setdefault('task_history',[]).append({k:state[k] for k in (
            'active_stage','scope','status','board_validation','report','limitations','repair_record') if k in state})
    state.update(active_stage='typography',scope='用户批准的华文琥珀/幼圆、16级抗锯齿和紧凑OSD；代码/编译/仿真',
                 target_top='skeleton_top',status='completed_simulation',board_validation='not_run_for_typography',
                 report='doc/compile/typography_run_report.md',limitations=LIMITS,repair_record=REPAIRS)
    state['typography']={
        'spec':'doc/spec/typography_behavior_spec.md','interface_version':'TYP1/1',
        'stages':{k:'completed' for k in ('requirements','architecture','rtl','tb','compile','simulation')},
        'physical_stage':'pending_user_execution','evidence':evidence,'repairs':REPAIRS,
        'modules':[
            {'name':n,'path':'rtl/gfx/'+n+'.v','dependencies':deps,'status':'completed'}
            for n,deps in (('alpha_blend16',[]),('text_row_aa',[]),
                           ('layer_text_aa',['text_row_aa','EG_LOGIC_BRAM']),
                           ('osd_font_youyuan',['EG_LOGIC_BRAM']),
                           ('osd_layer_small',['osd_font_youyuan','alpha_blend16']))],
        'integration':['rtl/top/skeleton_core.v','rtl/top/skeleton_top.v','rtl/app/asset_manager.v'],
        'verification_summary':'output/typography_implementation_20261029/verification_summary.json',
        'blocking_reason':None,'next_step':'对本次源码执行TD综合/布局布线/STA，核对实际资源并生成配套bit；尚未执行',
    }
    write_json(state_path,state)
    files_written=[
        'rtl/gfx/alpha_blend16.v','rtl/gfx/text_row_aa.v','rtl/gfx/layer_text_aa.v',
        'rtl/gfx/osd_font_youyuan.v','rtl/gfx/osd_layer_small.v',
        'rtl/gfx/osd_youyuan_ch.dath','rtl/gfx/osd_youyuan_ascii.dath',
        'rtl/top/skeleton_core.v','rtl/top/skeleton_top.v','rtl/app/asset_manager.v',
        'scripts/prepare_typography.py','scripts/check_typography_assets.py',
        'scripts/verify_typography.py','scripts/render_typography_sim.py','scripts/report_typography.py',
        'doc/spec/typography_behavior_spec.md','doc/compile/typography_run_report.md',
        'doc/workflow/state.json','output/typography_implementation_20261029/verification_summary.json']
    quality={
        'skill':'fpga-workflow','status':'completed','verification_level':'simulation',
        'files_written':files_written,'missing_files':[],
        'reason':'29个ModelSim自检场景、3个素材检查和最终板级编译展开通过；当前输入哈希匹配。物理验证不在本轮已执行范围。',
        'sim_result_path':'output/typography_implementation_20261029/verification_summary.json',
        'stages':{k:{'status':'completed','missing_files':[]} for k in
                  ('requirements','architecture','rtl','tb','compile','simulation')},
        'warnings':{k:e['unique_warning_count'] for k,e in evidence.items()},
        'repairs':REPAIRS,'limitations':LIMITS,
    }
    write_json(ROOT/'doc/workflow/quality_reports/typography.json',quality)
    rows=[]
    for key,e in evidence.items():
        rows.append(f"| {key} | {'、'.join(e['scenarios']) or '最终板级编译展开'} | {e['status']} | `{e['result']}` |")
    report=REPORT.replace('@@ROWS@@','\n'.join(rows)).replace('@@COUNT@@',str(scenario_count))
    (ROOT/'doc/compile/typography_run_report.md').write_text(report,encoding='utf-8')
    print(json.dumps({'status':verified['status'],'simulation_scenarios':scenario_count,
                      'asset_scenarios':len(assets['scenarios']),'changed_inputs':[],
                      'source_files':len(source_manifest),'card_package_sha256':assets['package_sha256']},ensure_ascii=False))


REPORT='''# 华文琥珀 / 幼圆抗锯齿实现与验证

日期：2026-10-30。工程：`D:/Verilog_teacher/guoyi/pro/audio_visual_upgrade`。

结论：完成到代码、ModelSim编译展开及功能仿真。8套功能仿真共@@COUNT@@个自检场景、3个素材完整性场景和最终`skeleton_top`板级展开全部通过；本报告生成时全部输入SHA256与PASS证据一致。**未执行本次版本的综合、布局布线、STA和上板，无配套新bit，不能据此宣称资源可放入或时序通过。**

## 显示效果与结构

- 歌词/歌名华文琥珀24px，歌手20px；OSD幼圆16px，面板(424,16)、200×224。8倍字体光栅化→LANCZOS→4bit覆盖率，运行时按真实底色做16级混色。
- 两行歌词和逐字变色保留；行距32，滚行0.3秒。歌名/歌手框宽160，滚动40px/s，绕回停留0.5秒。三页OSD、短按切页、长按显隐、参数调整和自动隐藏沿用原控制器。
- `text_row_aa`共享一套取字状态机，四word对齐读取；`layer_text_aa`共享一枚8×2048双时钟BRAM32K，奇偶行分bank，提前一行准备。完成后通过带帧/行标签mailbox发布，DE期间锁住元数据；迟到取消并整行隐藏，防止半行混入。
- `alpha_blend16`用移位/加法实现精确四舍五入`(bg*(15-a)+fg*a+7)/15`，无RTL乘法。文字在背景饱和度/对比度处理之后叠加；顶层保留原输出延迟。
- OSD字模中文用一枚BRAM32K双口拼64bit行，ASCII用一枚BRAM9K。320点历史压到176显示像素，横坐标用步进累加映射，保留原历史时间范围及纵向量程。实际资源映射仍须综合核对；以上为源码结构，不是测得的资源报表。
- 板级`TYPOGRAPHY=1`选择新实现；core默认0便于旧fixture回归。旧1bit文字模块保留且未修改，generate常量选择分支。原封面算法与素材未改。

## 字库和素材

新FONT.HZK为TYP1格式，仍存SDRAM word地址0xE1000；当前70字形，20644word / 82576byte，含卡中全部LRC实际文字及验证字符。8320word目录，每字24px+20px各字号共704byte。字形保留真实advance；未使用字符不占字形数据。缺字、字体边界或容量不足会报错，不裁切、不换字体、不降低覆盖率等级。新增/修改LRC须重跑生成器。

资源管理器检查FONT长度33296..1046784byte并要求4byte对齐，新模式跳过ASC；字库装好后跨歌复用。配套卡包在`output/typography_implementation_20261029/card_typography.zip`，将其中`sd_card`内文件复制到FAT32卡根目录。该包仅用于未来本版本新bit，不能配旧字库bit；原`card/`未改。包内外manifest大小/哈希、ZIP内容及模拟内存镜像均核对。

素材检查见`output/typography_implementation_20261029/asset_check.json`：两首LRC全部字符覆盖，70字形两种字号98560个存储像素与批准字体直接比较，16个覆盖率等级全部存在。中文/ASCII目录和字宽、填充、卡文件大小/哈希、ZIP内容均PASS。

## 验收与证据

TYP-01对应上述素材检查；TYP-02..06及回归如下。每个result内含完整源/模型/镜像哈希、显式源配置、命令、工具版本、退出码、超时及警告；同前缀`_compile.log`/`_sim.log`保留实际输出。

| 测试 | 场景 | 结果 | 证据 |
| --- | --- | --- | --- |
@@ROWS@@

- TYP-02逐通道穷举256×256×16，确认端点和全部正负颜色差。
- TYP-03两字号全部行、中文/比例ASCII、高低半字节、实际宽度、逐字高亮；坏头/缺字/短读/非法参数、无ack超时、取消及延后done、空行/复位恢复。样本最大615个SDR时钟，仅代表本测试响应时序。
- TYP-04真实双时钟BRAM模型、完整640×480逐像素、标题绕回/停留/17px偏移、歌词上滚16px、故意延迟6000个SDR周期时不出现半行，恢复后再次逐像素通过。
- TYP-05独立参考不读RTL。44字形全部16×16像素、3页×常规/极值6帧640×256连续扫描，逐像素精确比对；DE/可见性、历史绕回及切歌清空。原controls测试另覆盖按键和自动隐藏。
- TYP-06真实core混合流水，逐拍变化背景/FFT/淡入淡出/覆盖率/DE，确认文字在颜色处理之后叠加；OSD实际帧3拍输出对齐。装载专项覆盖FONT长度/对齐/失败、跳过ASC、图片/歌词加载、下一首LRC预加载槽、跨歌复用FONT。

实际仿真图`osd_sim_three_pages.png`和`core_sim_alignment.png`位于产物目录；来源是通过checker的模拟器像素dump，非PC参考图。前者上排常规/下排极值三页，后者是流水对齐用的彩色测试背景，不代表播放器整机实拍。`verification_summary.json`记录图/dump哈希。人工检查了两张图的文字完整性、边界与重叠。

## 修复与警告

每个问题各使用1次自动修改→重跑，未超3次预算；失败证据保留：

1. `typography_row_r1_compile_compile.log`：TB变量small触发保留字，改small_sel。
2. `typography_layer_r1_sim.log`：TB将前三字边界误填62；按真实24+24+17修正65，RTL未改。
3. `typography_osd_r1_sim.log`：source级OSD_SIM未被runner读取，改library级，恢复真实字模路径。
4. `typography_osd_r2_sim.log`：130%对比基准条末1px未填满，将定点系数901改902；r3六帧全部通过。

子模块测试各1种警告（ModelSim -novopt）。core专项32种、旧整机25种、板级23种唯一警告，包含既有厂商unsized常量、PLL宽度、未连接调试/状态输出和TB观察输出等，均完整保留。板级实际新分支已展开，未出现新模块端口宽度/未知字模加载警告；像素checker未忽略X或失配。功能仿真不能替代物理时序验证。

## 验证边界与后续

- 新模式尚未做真实SD/FAT→TYP1整机镜像仿真；取字/双时钟层/装载控制/core组合分别覆盖。core专项force图层源像素和参数，验证真实颜色与OSD流水；不把它称为端到端整机测试。
- 旧模式整机回归使用小目标BMP和HDMI stub，验证原SPI/FAT/SDRAM、切歌槽保护、音频及视频链；不是新字体端到端证据。
- 已ack事务在取消/超时后等done排空；永不done会维持busy直到系统复位。当前无自动复位仲裁器机制。gap_cnt仅是mailbox阻塞统计。
- 本次尚无资源/STA结果。上一版上板基线bit为`prj/td_build/bmp_downscale_r1_seed3_phy/skeleton.bit`，SHA256 `6D415526C16E01255C466C3C082DE798D37E4867D1CD3560F52B3C36643656A3`，未修改。该旧bit不包含本次字体，历史STA也未收敛。

## 复现

在工程根目录执行，Python使用项目现有`../music_screen/.pylibs`中的Pillow/fontTools及Windows华文琥珀/幼圆字体。ModelSim为`D:/modeltech64_10.6e/win64/vsim.exe`，实际版本10.6e；测试不生成VCD。

```powershell
python scripts/prepare_typography.py
python scripts/typography_osd_reference.py
python scripts/check_typography_assets.py
python scripts/verify_typography.py row --compile-only --suffix fresh_compile
python scripts/verify_typography.py row --suffix fresh_run
# 其余检查: blend, layer, osd, core, assets, controls, legacy_system, board
# 每个检查先compile-only，再run；board本身只编译展开。
python scripts/render_typography_sim.py
python scripts/report_typography.py
```

复用证据审计只需`python scripts/report_typography.py`，不重新执行已通过测试；该脚本会拒绝输入变动。完整重跑后，需将`report_typography.py`的RUNS更新为新证据前缀。`integrate_typography.py`和`implement_osd_typography.py`为已执行的一次性迁移脚本，不要重复运行。
'''


if __name__=='__main__': main()
