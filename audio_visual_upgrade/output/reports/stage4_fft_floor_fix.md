# 阶段 4：FFT 底值导致色彩系数长期满格的修正

日期：2026-10-25。状态：RTL、ModelSim 仿真、TD 实现和 bit 生成完成；尚未上板验证本版。

## 问题与修正

用户反馈上一版诊断 bit 的浅黄色响度条在中段变化，青色色彩系数条一直满格，包括弱伴奏段。上一版为 `stage4_calibrated_diag1_seed3_phy/skeleton.bit`。

真实 `spec_fft` RTL 的非零对数频点最低输出为 145。旧色彩包络直接平均该字节；`card/S01.WAV` 的 2 秒和 4 秒采样窗均值为 96、93，已超过旧映射的 90 上限，导致色彩系数长期饱和。此前按不准确的离线幅度估算定阈值，没有覆盖真实 FFT 的底值，是该问题的原因。

`rtl/top/skeleton_core.v` 现在仅对色彩包络累计 `max(sp_bin_mag - 145, 0)`；均值乘 8 后做原有上升/回落平滑，映射区间改为 32～144。频谱柱与攻击检测仍使用原始频点字节。右上角两条诊断条保留。

## 验证证据与范围

- `sim/color_wav_floor_fix_sim_result.json`：PASS，哈希与当前探针源码一致。将卡上 S01.WAV 每秒起始处的 1024 点原始左声道 PCM 送入真实 1024 点 FFT，共 45 个音乐采样窗及一个静音窗。它验证 FFT 数值范围，不等同整首音频的连续回放。扣底均值：2 秒为 3，4 秒为 4，18 秒为 16，23 秒为 18，32 秒为 19，44 秒为 11。
- `sim/stage4_floor_core_sim_result.json`：PASS。真实 SPI/FAT/图片装载/SDRAM 模型；完成开机布局、按键和定时切图、自然跨歌渐变及槽保护、PCM 和视频流完整性四个场景。检查 348160 个合成像素和 13832 个 PCM 样本；TMDS 与显示器行为不在该测试范围。
- `sim/stage4_floor_board_compile_sim_result.json`：COMPILE_PASS，只编译展开，不代表板级功能验证。
- `sim/stage4_floor_envelope_checked_sim_result.json`：PASS。`tb/tb_color_envelope.v` 对真实 skeleton_core 的频点接口注入弱/中/强/回落序列，隔离验证色彩包络。黄色/青色结果分别为 23/0、71/81、143/245、39/30。它不替代真实 FFT 探针和整机回归。回落计算采用整数右移，目标 24、差值小于 16 时会停止下降；因此回落至 39 属于现有整数平滑的死区，测试按该契约检查。首次将响度回落上限设为 36 的断言过紧，修为 45；青条回落上限始终为 40。
- 新增可复现配置 `sim/modelsim_color_envelope.json` 与 `tb/expected_color_envelope.json`。第一次复用旧 core 配置缺少 cover_pop、cover_pop_geom、attack_rings 依赖；已改用完整板级源清单，不改 RTL。

独立包络自检复现命令（项目根目录，PowerShell）：

```powershell
$env:SIMULATOR='modelsim'
$env:RUN_SIM='1'
$env:ENABLE_VCD='0'
$env:MODELSIM_CONFIG='sim/modelsim_color_envelope.json'
$env:EXPECTED_SCENARIOS='tb/expected_color_envelope.json'
$env:SIM_OUTPUT='stage4_floor_envelope_checked'
$env:TIMEOUT_SECONDS='120'
python sim/run.py
```

## TD 实现与交付

构建：`prj/td_build/stage4_floor_diag1_seed3_phy`，综合来源 `stage4_floor_diag1_syn`，Seed 3。`build_result.json` 确认输入在构建期间未变。

| 资源 | 上一版诊断 bit | 本版 | 本次差值 |
| --- | ---: | ---: | ---: |
| Slice | 9391 / 9800 | 9464 / 9800（96.57%） | +73 |
| 9K RAM | 52 / 64 | 52 / 64 | 0 |
| 32K RAM | 4 / 16 | 4 / 16 | 0 |
| DSP | 21 / 29 | 21 / 29 | 0 |

Slice 依据 route.qor；RAM/DSP 类型依据 skeleton_phy.area。本表比较对象是上一版色彩诊断 bit，不能据此计算阶段 3 或阶段 4 相对早期基线的总增量。

最终时序：video_clk Setup +0.240 ns，clk Setup +0.686 ns；全局最差 Setup -5.565 ns，Hold +0.024 ns。所列负裕量路径的起终点均在 SDRAM PHY 内；仍沿用既有 SDRAM 处理口径，不能表述为全设计时序收敛。STA 覆盖率 96.63%。

bit：`prj/td_build/stage4_floor_diag1_seed3_phy/skeleton.bit`，638945 字节。

SHA256：`1531E0B98FEDFCBECE239A715A3872F68292A7E50B1577E99C1C9F2D45E8D516`。

上板观察：同一张卡上从曲首播放，青条应在弱段较短、强段增长，并在声音减弱后缩短；图像饱和度与对比度随青条变化。结合切图与跨歌渐变检查图片、歌词与音频。只有实际下载本 bit 并观察后，才能认定本版色彩效果通过上板验证。
