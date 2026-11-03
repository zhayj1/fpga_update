# 转场功能：时序优化与最终候选

当前选择r7；Slice 9757/9800。
77次场景自检通过（69个不同场景），另通过实际板级顶层编译展开。
已审计实际输入哈希、退出码、场景集合和唯一TEST_PASS。功能及资源优化经过见 [第二轮报告](scene_transitions_round2_20261102.md)。

保留淡入淡出，新增擦除、溶解、百叶窗；OSD第六页设置效果及快速/标准/慢速/很慢。
四档为16/32/64/128帧间隔，约0.269/0.538/1.075/2.150秒；默认淡入淡出、标准。
设置在帧边界提交并在转场开始锁存；背景/封面参与转场，歌词、频谱、OSD继续实时叠加。

## 本轮改动

r7种子3新增的30个普通setup端点主要经过歌名/歌手滚动回绕计算。种子2打包失败。
r8在行渲染完成时预计算并保存回绕边界，功能回归通过，但M/L-Slice为4902/4903，无法采用。
r9仅缓存可达回绕边界的变化位，恒定高位由连线恢复；另保存宽文字与可回绕标志。
r9综合LUT降至17688、REG为11784，但最终打包4956/4956，未进入布线，不能以综合面积替代物理资源结果。
当前BOX_W=448时可达边界为896..1023，只存7个低位；边界超出1023时继续保持原10位偏移自然溢出的行为。
与冻结的r7真实AA模块逐周期对比，覆盖全部1024种宽度、边界前后偏移、溢出、停顿、采样间隔、同时完成/切歌/复位优先级；9组参数包括默认1200/24000。
r9未采用，当前RTL已还原为资源可容纳且回归通过的r7。

## 实现尝试

|候选|M-Slice|L-Slice|结果|普通setup端点|
|---|---:|---:|---|---:|
|transitions_r7_seed3_phy|4879|4878|BUILD_COMPLETE|30|
|transitions_r7_seed2_phy|4914|4915|FAILED_RESOURCE|-|
|transitions_r8_seed3_phy|4902|4903|FAILED_RESOURCE|-|
|transitions_r9_seed3_phy|4956|4956|FAILED_RESOURCE|-|

每类Slice上限4900。失败候选与其源码快照、日志均保留。

## 当前资源与时序

|资源|原版|r7|当前|上限|
|---|---:|---:|---:|---:|
|Slice|9767|9757|9757|9800|
|LUT|18195|18174|18174|19600|
|REG|11785|11799|11799|19600|
|BRAM9K|64|64|64|64|
|BRAM32K|16|16|16|16|
|DSP|29|29|29|29|

|路径组|r7 setup/ns|当前setup/ns|当前hold/ns|当前setup端点|
|---|---:|---:|---:|---:|
|video_clk -> video_clk|+0.721|+0.721|+0.027|0|
|clk -> clk|+0.476|+0.476|+0.024|0|
|sdr_clk -> sdr_clk|-1.854|-1.854|+0.105|30|
|sdr_clk -> video_clk|+2.032|+2.032|+0.205|0|
|video_clk -> sdr_clk|+0.083|+0.083|+0.244|0|
|hdmi_5x_clk -> hdmi_5x_clk|+6.092|+6.092|+0.230|0|
|sdr_clk -> sdr_clk_sft|-1.524|-1.524|+5.001|32|
|sdr_clk_sft -> sdr_clk|-5.565|-5.565|+9.430|32|

最终STA setup 94个、hold 0个违例；其中普通路径setup 30个，WNS -5.565ns。
TNS -229.383ns，STA coverage 96.38%。
综合95条告警归一化后与原版一致；管脚、时钟和时序约束哈希与原版相同。
未降低频率、增加false_path/multicycle或修改PLL；SDRAM双向移相路径仍按真实报告列出。

## 采用的功能验证

|检查|场景次数|结果|
|---|---:|---|
|transitions|4|[PASS](../../sim/transitions_r4_final_scene_transitions_sim_result.json)|
|controls_cdc|4|[PASS](../../sim/transitions_r4_final_visual_controls_sim_result.json)|
|osd_pixels|4|[PASS](../../sim/transitions_r7_visual_osd_sim_result.json)|
|osd_equivalence|4|[PASS](../../sim/transitions_r7_osd_equivalence_sim_result.json)|
|luma_equivalence|2|[PASS](../../sim/transitions_r7_color_luma_equivalence_sim_result.json)|
|color_envelope|1|[PASS](../../sim/transitions_r7_color_envelope_sim_result.json)|
|legacy_scene|4|[PASS](../../sim/transitions_r2_scene_legacy_sim_result.json)|
|split_core|6|[PASS](../../sim/transitions_r7_split_core_sim_result.json)|
|circular_system|4|[PASS](../../sim/transitions_r7_circular_system_sim_result.json)|
|catalog_matrix|8|[PASS](../../sim/transitions_r7_catalog_matrix_sim_result.json)|
|catalog_equivalence|9|[PASS](../../sim/transitions_r7_catalog_equivalence_sim_result.json)|
|catalog_legacy|4|[PASS](../../sim/transitions_r7_catalog_legacy_sim_result.json)|
|attack_bands|3|[PASS](../../sim/transitions_r1_attack_bands_sim_result.json)|
|spectrum_stage1|4|[PASS](../../sim/transitions_r1_spectrum_stage1_sim_result.json)|
|layer_fft64|7|[PASS](../../sim/transitions_r1_layer_fft64_sim_result.json)|
|split_spectrum|9|[PASS](../../sim/transitions_r1_split_spectrum_sim_result.json)|
|board_compile|0|[COMPILE_PASS](../../sim/transitions_r7_circular_board_sim_result.json)|

## 产物与限制

- 候选bit：`D:\Verilog_teacher\guoyi\pro\audio_visual_upgrade_2\prj\td_build\transitions_r7_seed3_phy\skeleton.bit`。
- SHA256：`75B6BE3E117F03B497C4C997088C4308830409BD3803AB332B75C9919A55C995`。
- 结构化证据：`output/transitions_timing/verification_and_build.json`。
- 未下载上板；生成bit和功能仿真通过不能代替硬件验证。
- SD/FAT/音视频系统回归沿用缩放夹具与150MHz参数，不替代实际100MHz SDRAM板级验证。
- 全部BRAM及DSP仍满载；新转场没有增加RAM或DSP。

## 重试预算

本轮时序预算源于r7首次装入芯片后获得的新STA证据：种子2、r8预计算、r9压缩边界共3次自动重跑。
结果：exhausted。原资源优化预算未重置。
依据 [规则50](C:/Users/Lenovo/.codex/skills/fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md)：
> 预算用尽写 doc/compile/repair_report.md，说明尝试、剩余错误、证据和下一步，停止自动重试。
本轮停止自动修改和更换种子。下一轮应先针对r7的ws→hold_empty/hold_count/off_s实际路径，尝试更小的滚动判定控制结构，维持同拍采样和行完成优先级。
r8虽仅超2个M-Slice、3个L-Slice，但尚无最终STA；不能据此认为它时序已修复。继续需要明确授权新一轮，并保留独立等价/文字/SDRAM回归。
原64个SDRAM移相违例还须核实厂商硬宏模型与读写/三态采样契约；不能仅凭原版也存在而豁免。
