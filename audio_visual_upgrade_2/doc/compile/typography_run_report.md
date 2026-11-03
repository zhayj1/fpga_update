# 华文琥珀 / 幼圆抗锯齿实现与验证

日期：2026-10-30。工程：`D:/Verilog_teacher/guoyi/pro/audio_visual_upgrade`。

更正（2026-10-30）：这是TYP1历史记录。原素材检查与生成器共用了错误的LRC行数读取方法，因此“全部歌词覆盖”结论无效，实际只含前8行。TYP1随后完成实现并由用户上板验证，仍有setup违例；完整字库TYP2见 `full_font_report.md`。以下历史仿真记录不能作为当前TYP2源码的验证证据。

## 显示效果与结构

- 歌词/歌名华文琥珀24px，歌手20px；OSD幼圆16px，面板(424,16)、200×224。8倍字体光栅化→LANCZOS→4bit覆盖率，运行时按真实底色做16级混色。
- 两行歌词和逐字变色保留；行距32，滚行0.3秒。歌名/歌手框宽160，滚动40px/s，绕回停留0.5秒。三页OSD、短按切页、长按显隐、参数调整和自动隐藏沿用原控制器。
- `text_row_aa`共享一套取字状态机，四word对齐读取；`layer_text_aa`共享一枚8×2048双时钟BRAM32K，奇偶行分bank，提前一行准备。完成后通过带帧/行标签mailbox发布，DE期间锁住元数据；迟到取消并整行隐藏，防止半行混入。
- `alpha_blend16`用移位/加法实现精确四舍五入`(bg*(15-a)+fg*a+7)/15`，无RTL乘法。文字在背景饱和度/对比度处理之后叠加；顶层保留原输出延迟。
- OSD字模中文用一枚BRAM32K双口拼64bit行，ASCII用一枚BRAM9K。320点历史压到176显示像素，横坐标用步进累加映射，保留原历史时间范围及纵向量程。实际资源映射仍须综合核对；以上为源码结构，不是测得的资源报表。
- 板级`TYPOGRAPHY=1`选择新实现；core默认0便于旧fixture回归。旧1bit文字模块保留且未修改，generate常量选择分支。原封面算法与素材未改。

## 字库和素材

新FONT.HZK为TYP1格式，仍存SDRAM word地址0xE1000；当前70字形，20644word / 82576byte，仅含卡中前8行歌词、歌名歌手及验证字符。8320word目录，每字24px+20px各字号共704byte。字形保留真实advance；未使用字符不占字形数据。缺字、字体边界或容量不足会报错，不裁切、不换字体、不降低覆盖率等级。新增/修改LRC须重跑生成器。

资源管理器检查FONT长度33296..1046784byte并要求4byte对齐，新模式跳过ASC；字库装好后跨歌复用。配套卡包在`output/typography_implementation_20261029/card_typography.zip`，将其中`sd_card`内文件复制到FAT32卡根目录。该历史包仅用于TYP1 bit，不能配旧字库bit；原`card/`未改。包内外manifest大小/哈希、ZIP内容及模拟内存镜像均核对。

素材检查见`output/typography_implementation_20261029/asset_check.json`：原“全部LRC覆盖”无效，70字形两种字号98560个存储像素与批准字体直接比较，16个覆盖率等级全部存在。中文/ASCII目录和字宽、填充、卡文件大小/哈希、ZIP内容均PASS。

## 验收与证据

TYP-01对应上述素材检查；TYP-02..06及回归如下。每个result内含完整源/模型/镜像哈希、显式源配置、命令、工具版本、退出码、超时及警告；同前缀`_compile.log`/`_sim.log`保留实际输出。

| 测试 | 场景 | 结果 | 证据 |
| --- | --- | --- | --- |
| blend | TYP-02 | PASS | `sim/typography_blend_r1_sim_result.json` |
| row | TYP-03-pixels、TYP-03-invalid、TYP-03-recovery | PASS | `sim/typography_row_r2_sim_result.json` |
| layer | TYP-04-pixels、TYP-04-scroll、TYP-04-deadline | PASS | `sim/typography_layer_r2_sim_result.json` |
| osd | TYP-05-glyphs、TYP-05-frames、TYP-05-state | PASS | `sim/typography_osd_r3_sim_result.json` |
| core | TYP-06-composition、TYP-06-osd-alignment | PASS | `sim/typography_core_r1_sim_result.json` |
| assets | TYP-06-font-loading、TYP-06-song-assets | PASS | `sim/typography_assets_r1_sim_result.json` |
| controls | osd_short_page、osd_long_toggle、osd_volume_adjust、osd_font_and_panel、osd_pixel_alignment、osd_numeric_pages、osd_bar_width、osd_scope_mark、osd_three_pages、osd_parameter_bounds、osd_scope_rescale | PASS | `sim/typography_controls_r1_sim_result.json` |
| legacy_system | real_spi_boot_and_layout、key_and_timer_fade_pixels、natural_song_end_fade_and_slot_protection、pcm_and_video_stream_integrity | PASS | `sim/typography_legacy_system_sim_result.json` |
| board | 最终板级编译展开 | COMPILE_PASS | `sim/typography_board_final_sim_result.json` |

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
