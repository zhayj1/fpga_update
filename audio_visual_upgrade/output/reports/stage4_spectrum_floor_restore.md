# 阶段 4 频谱柱高恢复

日期：2026-10-25。状态：RTL、ModelSim、TD 综合/布线、bit 和上板验证均已完成。

## 原因与修正

用户提供的 `dyblank_r1_seed1bit_phy/skeleton.bit` 作为频谱柱高正常对照。对比构建输入和历史源码后确认，频谱链的 `spec_bands64.v`、`layer_fft64.v` 未变，变化来自共享 `spec_fft.v` 的 `log_level` 基准：正常版为 `78 + exponent*22 + fraction`，阶段4色彩修正版误改为 `145 + exponent*22 + fraction`。这会把每个非零频点整体抬高 67，直接造成柱子高了一大截。

本版将 `log_level` 恢复为正常版的 78 基准，频谱柱和攻击检测因此回到对照 bit 的幅度语义。色彩包络仍保留上一版已上板确认的效果：色彩累计使用 `min(max(FFT_byte-78,0),110)`，它与上一版对 145-floor 字节做 `max(byte-145,0)` 完全等价，不改变色彩联动响应。

## 验证

- `sim/spectrum_floor_restore_sim_result.json`：PASS。45 个卡上 S01.WAV 逐秒 1024 点窗口及静音窗口，扣除 78 基准后的色彩输入统计保持原结果。
- `sim/envelope_floor_restore_sim_result.json`：PASS。弱/中/强/回落包络结果保持黄色/青色 `23/0、71/81、143/245、39/30`。
- `sim/floor_restore_core_sim_result.json`：PASS。真实 SPI/FAT/图片装载/SDRAM 模型下，开机布局、切图渐变、槽保护和 PCM/视频流四个场景通过。
- `sim/floor_restore_board_compile_sim_result.json`：COMPILE_PASS。板级全源编译展开通过。
- 用户已下载 `skeleton.bit` 到目标板并确认上板没有问题；频谱柱高、色彩联动、图片与播放链路保持正常。

## TD 结果

综合：`prj/td_build/spectrum_floor_restore_syn_syn`（脚本自动命名的首轮记录）；标准综合目录为 `prj/td_build/spectrum_floor_restore_syn`。

布线：`prj/td_build/spectrum_floor_restore2_seed4_phy`，Seed 4，输入未被构建过程修改。Seed 3 曾在 `u_core/u_attack_rings/dy2` 产生 PHY-8023 局部冲突，未交付；seed4 成功。

| 资源 | 本版 | 阶段4已确认 bit |
| --- | ---: | ---: |
| Slice | 9383 / 9800（95.74%） | 9464 / 9800（96.57%） |
| 9K RAM | 52 / 64 | 52 / 64 |
| 32K RAM | 4 / 16 | 4 / 16 |
| DSP | 21 / 29 | 21 / 29 |

最终时序：video_clk Setup +2.849 ns，clk Setup +0.464 ns；全局最差 Setup -5.565 ns，Hold +0.023 ns；STA 覆盖率 96.64%。负 setup 路径仍在既有 SDRAM 相关口径内。

bit：`prj/td_build/spectrum_floor_restore2_seed4_phy/skeleton.bit`，638945 字节。

SHA256：`6E93038A44314457319687245ED474D826B6775DD2F6299F61979F406DC54FB0`。

## 上板确认

用户使用与正常对照相同的卡和曲目下载本版，确认上板没有问题。底部 64 柱恢复到正常量级，色彩联动、切图、渐变、歌词和音频连续性均通过实际观察。
