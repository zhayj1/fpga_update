# 转场设置：第二轮资源优化与验证

目标 EG4S20BG256；TD 6.2.168116 / ModelSim 10.6e。

当前r7完成综合、布局布线并生成候选bit；Slice 9757/9800。
77次场景自检通过，包含69个不同场景ID，另通过真实板级顶层编译展开。
全部采用的结果已重新核对当前实际输入哈希、退出码、场景集合及唯一TEST_PASS。

## 已实现行为

保留淡入淡出，新增左向右擦除、像素溶解、15条水平百叶窗。OSD第六页选择效果及快速/标准/慢速/很慢四档速度。
速度对应16/32/64/128帧间隔，约0.269/0.538/1.075/2.150秒；默认淡入淡出、标准。KEY2/KEY3双向循环选择。
设置在帧边界整体提交，每次转场开始锁存；忙时修改下次生效。旧读取排空后才释放旧存储槽。
背景、封面参与转场；歌词、频谱和OSD保持实时叠加。图像/同步流水对齐，未减少色彩精度或转场分辨率。

## 本轮等价优化与尝试

r5将目录seen/valid标志改成常量位索引写使能；r7保留它，将通过完整ASCII校验的数字直接取低半字节、资源ID改为字段拼接，并把16首歌计数缩至5位。
逐周期对比r4目录的全部36个输出及标志；保留全部原矩阵场景，增加65,536种数字字节组合和全部CV后缀/文件类型组合。
r6颜色暂存移位结构功能等价但物理打包更差，已撤回；最终visual_settings与r4逐字节相同。

|候选|综合LUT|综合REG|M-Slice|L-Slice|结果|
|---|---:|---:|---:|---:|---|
|transitions_r5|17665|11785|4906|4906|FAILED_RESOURCE|
|transitions_r6|17766|11785|4970|4969|FAILED_RESOURCE|
|transitions_r7|17615|11782|4879|4878|BUILD_COMPLETE|

每类Slice上限4900。历史候选按保存的源码快照核对，不能视为当前源码结果。

## 最终资源

|资源|原版|当前|上限|
|---|---:|---:|---:|
|Slice|9767|9757|9800|
|LUT|18195|18174|19600|
|REG|11785|11799|19600|
|BRAM9K|64|64|64|
|BRAM32K|16|16|16|
|DSP|29|29|29|

管脚和时钟约束与基线哈希相同；综合95条告警归一化后与基线逐条一致。原95个像素字体槽内容不变，新中文使用原字库空槽。

## 最终时序

|路径组|基线setup/ns|当前setup/ns|当前hold/ns|setup违例端点|
|---|---:|---:|---:|---:|
|video_clk -> video_clk|+3.612|+0.721|+0.027|0|
|clk -> clk|+0.663|+0.476|+0.024|0|
|sdr_clk -> sdr_clk|+0.470|-1.854|+0.105|30|
|sdr_clk -> video_clk|+2.763|+2.032|+0.205|0|
|video_clk -> sdr_clk|+2.988|+0.083|+0.244|0|
|hdmi_5x_clk -> hdmi_5x_clk|+6.164|+6.092|+0.230|0|
|sdr_clk -> sdr_clk_sft|-1.567|-1.524|+5.001|32|
|sdr_clk_sft -> sdr_clk|-5.565|-5.565|+9.430|32|

WNS -5.565ns，TNS -229.383ns；setup 94个，hold 0个；STA coverage 96.38%。
非移相路径setup违例为30个；全工程时序未全部通过，候选bit不能视为硬件验收通过。

## 仿真证据

|检查|场景次数|结果JSON|
|---|---:|---|
|transitions|4|`sim/transitions_r4_final_scene_transitions_sim_result.json`|
|controls_cdc|4|`sim/transitions_r4_final_visual_controls_sim_result.json`|
|osd_pixels|4|`sim/transitions_r7_visual_osd_sim_result.json`|
|osd_equivalence|4|`sim/transitions_r7_osd_equivalence_sim_result.json`|
|luma_equivalence|2|`sim/transitions_r7_color_luma_equivalence_sim_result.json`|
|color_envelope|1|`sim/transitions_r7_color_envelope_sim_result.json`|
|legacy_scene|4|`sim/transitions_r2_scene_legacy_sim_result.json`|
|split_core|6|`sim/transitions_r7_split_core_sim_result.json`|
|circular_system|4|`sim/transitions_r7_circular_system_sim_result.json`|
|catalog_matrix|8|`sim/transitions_r7_catalog_matrix_sim_result.json`|
|catalog_equivalence|9|`sim/transitions_r7_catalog_equivalence_sim_result.json`|
|catalog_legacy|4|`sim/transitions_r7_catalog_legacy_sim_result.json`|
|attack_bands|3|`sim/transitions_r1_attack_bands_sim_result.json`|
|spectrum_stage1|4|`sim/transitions_r1_spectrum_stage1_sim_result.json`|
|layer_fft64|7|`sim/transitions_r1_layer_fft64_sim_result.json`|
|split_spectrum|9|`sim/transitions_r1_split_spectrum_sim_result.json`|
|board_compile|0|`sim/transitions_r7_circular_board_sim_result.json`|

矩阵与逐周期等价测试共用8个场景ID，两者均实际执行；次数与不同ID数量分别报告。

## 产物与限制

候选bit：`prj/td_build/transitions_r7_seed3_phy/skeleton.bit`，701801字节。
SHA256：`75B6BE3E117F03B497C4C997088C4308830409BD3803AB332B75C9919A55C995`。

- 最终STA仍有94个setup、0个hold违例；其中非移相路径setup 30个，WNS -5.565ns。
- 未下载上板；生成bit和功能仿真通过不能代替硬件验证。
- SD/FAT/音视频系统回归沿用缩放夹具与150MHz参数，不替代实际100MHz SDRAM板级验证。
- 全部BRAM及DSP仍满载；新转场没有增加RAM或DSP。

结构化证据：`output/transitions_round2/verification_and_build.json`。第一轮失败记录保留于`doc/compile/scene_transitions_20261102.md`。

本轮3次资源修改实现已用完，资源问题已解决；未自动下载上板。

复核命令：`python -B scripts/report_scene_transitions_round2.py`。
