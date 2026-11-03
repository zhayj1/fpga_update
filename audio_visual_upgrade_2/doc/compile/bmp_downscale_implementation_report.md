# BMP 缩小功能：综合与布局布线

日期：2026-10-29。工具：Tang Dynasty 6.2.168116；器件：EG4S20BG256。

综合及 4 个布局种子均完成并生成 bit。当前选择 `bmp_downscale_r1_seed3_phy`，资源可容纳；全工程时序尚未收敛，除既有移相 SDRAM 路径外，还有 9 个 setup 违例端点。
未下载、未上板。本轮只更换布局种子，RTL、管脚与时序约束均未改动。

## 当前候选与修改前资源

| 资源 | 原版 uartless seed1 | 当前候选 | 变化 |
| --- | ---: | ---: | ---: |
| Slice | 9581/9800 | 9420/9800 | -161 |
| LUT | 17981/19600 | 17738/19600 | -243 |
| 寄存器 | 11041/19600 | 10858/19600 | -183 |
| BRAM9K | 55/64 | 55/64 | +0 |
| BRAM32K | 6/16 | 6/16 | +0 |
| DSP | 26/29 | 24/29 | -2 |
| PLL | 2/4 | 2/4 | +0 |
| GCLK | 4/16 | 4/16 | +0 |

Slice 占用 96.12%，剩余 380 个。RAM 总数保持 61 块，新增缩小器无行/帧 RAM。
综合 gate.qor 的逻辑 LUT 从 12699 降到 12653；物理 LUT 与综合 LUT 统计口径不同。
loader 层次统计：LUT 837→960、ripple 102→136、寄存器 667→634、DSP 2→0。固定输出几何消除了原有 span 乘法；新增计数逻辑仍有资源开销。

## 布局种子比较

| 种子 | Slice | 视频同域 setup/ns | 50 MHz 同域 setup/ns | SDRAM同域 setup/ns | setup违例端点 | 全局TNS/ns | hold WNS/ns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 9457 | -0.430 | +1.969 | -1.489 | 117 | -225.987 | +0.022 |
| 3（当前候选） | 9420 | +3.105 | +0.757 | -0.323 | 73 | -200.673 | +0.024 |
| 2 | 9473 | +0.941 | +0.538 | -0.513 | 68 | -208.784 | +0.024 |
| 4 | 9470 | +2.011 | +1.043 | -0.658 | 67 | -200.104 | +0.027 |

选择优先依据非移相路径的最差 setup 裕量，其次看总负裕量与 Slice。所有种子的全局 WNS 均为 −5.565 ns；仅看该值无法比较新增违例。

## 当前候选的时序

| 路径组 | 原版 setup/ns | 当前 setup/ns | 当前 hold/ns | 当前 setup违例端点 |
| --- | ---: | ---: | ---: | ---: |
| video_clk -> video_clk | +0.563 | +3.105 | +0.030 | 0 |
| clk -> clk | +1.284 | +0.757 | +0.027 | 0 |
| sdr_clk -> sdr_clk | +0.005 | -0.323 | +0.024 | 9 |
| sdr_clk -> video_clk | +2.757 | +2.675 | +0.244 | 0 |
| video_clk -> sdr_clk | +1.083 | +0.714 | +0.244 | 0 |
| hdmi_5x_clk -> hdmi_5x_clk | +6.394 | +5.874 | +0.223 | 0 |
| sdr_clk -> sdr_clk_sft | -1.889 | -1.085 | +5.001 | 32 |
| sdr_clk_sft -> sdr_clk | -5.565 | -5.565 | +9.430 | 32 |

全局 setup WNS -5.565 ns，TNS -200.673 ns，73 个端点；hold 无违例。
STA coverage 96.63%，与原版相同；报告方案为每组最多 10 个端点，摘要未列出全部路径。
实际报告时钟：控制50 MHz、视频25 MHz、SDRAM100 MHz（含相移）、HDMI串行125 MHz。SDC 旧注释的150 MHz不代表本次PLL输出。

既有 sdr_clk↔sdr_clk_sft 各32个 setup 违例仍保留分析，未添加 false_path/multicycle 或降低频率隐藏问题。
新增负裕量路径（各组最差一条）：

- `sdr_clk -> sdr_clk`：-0.323 ns，`u_core/u_lyr/u_row/wd_reg[26]_syn_4.clk` → `u_core/u_lyr/u_row/err_t_reg[1]_syn_17.a[0]`。

缩小器位于50 MHz控制域，该域没有setup违例。布局变化使原有路径的物理裕量改变，不能据此宣称新增功能对整板时序没有影响。

## 告警与证据

综合告警与 uartless 基线逐条归一化对比一致（仅归一化工程路径、源码行号及自动生成实例编号），无新增位宽或锁存器告警。
保留既有厂商SDRAM未驱动网/管脚、FFT tw_rom、RAM初始化忽略及重复CompileOrder告警。eram_init=off 的频谱RAM在完整bank提交前由 active_valid 隔离。
布局保留 PHY-7002：SDRAM实例初始位置不合法后由工具重新放置；该告警原版也有。未出现错误标记，布线DRC及bit生成完成。

核对全部 78 个源/约束/初始化输入，源清单与原版一致，只有下列四份RTL哈希变化：

- `rtl/load/bmp_load.v`
- `rtl/storage/resource_catalog.v`
- `rtl/top/skeleton_core.v`
- `rtl/gfx/layer_fft64.v`

每次构建的 inputs.json 记录源、构建脚本文件、综合DB来源的SHA256；build_result.json 记录完成时间及bit哈希。本报告再次校验它们与当前磁盘一致。
33个功能自检场景及整板编译证据仍与当前RTL相符，见 `bmp_downscale_run_report.md`。未重复仿真未变更的RTL。

## 产物与复现

- 当前候选 bit：`prj/td_build/bmp_downscale_r1_seed3_phy/skeleton.bit`（651749 字节）。
- SHA256：`6D415526C16E01255C466C3C082DE798D37E4867D1CD3560F52B3C36643656A3`。
- 综合：`prj/td_build/bmp_downscale_r1_syn/gate.qor`、`skeleton_gate.area`。
- 当前物理报告：`prj/td_build/bmp_downscale_r1_seed3_phy/route.qor`、`skeleton_phy.area`、`final_timing.rpt`。
- 结构化汇总：`doc/compile/bmp_downscale_implementation_result.json`。

构建命令如下；脚本拒绝覆盖已有目录，重跑时为 Tag 选择新名称。

```powershell
.\scripts\build.ps1 -Stage syn -Tag bmp_downscale_r1 -LutStructure off
.\scripts\build.ps1 -Stage phy -Tag bmp_downscale_r1_seed1 -SynthesisTag bmp_downscale_r1 -Seed 1 -GenerateBitstream
.\scripts\build.ps1 -Stage phy -Tag bmp_downscale_r1_seed3 -SynthesisTag bmp_downscale_r1 -Seed 3 -GenerateBitstream
.\scripts\build.ps1 -Stage phy -Tag bmp_downscale_r1_seed2 -SynthesisTag bmp_downscale_r1 -Seed 2 -GenerateBitstream
.\scripts\build.ps1 -Stage phy -Tag bmp_downscale_r1_seed4 -SynthesisTag bmp_downscale_r1 -Seed 4 -GenerateBitstream
python scripts/report_downscale_implementation.py
python scripts/report_downscale.py
```

本轮布局比较已结束；所有候选保留。尚未验证实卡大图加载耗时、切换就绪与画质。若继续收敛时序，应先针对报告中的实际负裕量路径做结构优化，并重新进行受影响仿真及实现。
