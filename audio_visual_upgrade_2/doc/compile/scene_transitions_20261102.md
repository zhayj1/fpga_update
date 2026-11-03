# 转场设置：实现与验证

日期：2026-11-02。目标 EG4S20BG256，TD 6.2.168116 / ModelSim 10.6e。

功能实现及 56 个场景自检通过，综合完成；布局资源超限，尚未完成可下载交付。

## 功能

OSD 第六页包含转场效果与速度；四种效果为淡入淡出、从左向右擦除、像素溶解、15条水平百叶窗。
四档速度为快速/标准/慢速/很慢：16/32/64/128 帧间隔，约0.269/0.538/1.075/2.150秒。默认淡入淡出、标准。
KEY2/KEY3双向循环选择。帧边界提交设置，转场开始锁存，中途修改于下次生效。旧存储槽等待读取排空后才释放。
背景和封面参与转场；歌词、频谱、OSD沿用实时叠加。图像流水与同步延迟保持，新增特效无额外RAM/DSP。

## 等价优化证据

- 亮度使用 256g+55(r-g)+18(b-g) 代替原移位求和。全部16,777,216种RGB逐值一致；262,144组完整颜色增益变换与原版比较一致，包含原有溢出语义。
- OSD共用标签译码、共用百分比计算，除法使用减法借位比较；512个标签地址、32个转场字地址、131,072组百分比输入、全部131,072个scope除数和六页完整画面与未优化版本一致。
- 原95个像素字体槽及管脚/时钟约束的哈希不变，新中文字占用原字库空槽。

## 资源失败记录

原版已占9767/9800 Slice（M-Slice 4884、L-Slice 4883），全部BRAM及29个DSP已满。
综合LUT与布局Slice统计口径不同；不能因综合LUT未满就认定能装入芯片。

| 尝试 | 修改 | 综合LUT | 综合REG | 布局M-Slice | 布局L-Slice |
| --- | --- | ---: | ---: | ---: | ---: |
| r1 | 支持四种转场、速度和第六页 | 17722 | 11796 | 4940 | 4941 |
| r2 | 标签扁平译码、百分比算术共享（资源更差，已撤回） | 18018 | 11777 | 4997 | 4998 |
| r3 | 共享一个标签译码器、共享百分比算术 | 17690 | 11777 | 4937 | 4937 |
| r4 | 保留共享译码；亮度代数等价变换；除法比较复用借位 | 17597 | 11777 | 4940 | 4940 |

每类Slice上限4900。最终r4超出40个M-Slice、40个L-Slice，打包需求合计9880，超出总数80。
r4日志：`prj/td_build/transitions_r4_seed3_phy/console.log:404`。没有生成新bit或最终时序报告。
最终打包有2833个单独LUT、952个单独SEQ；LUT下降并未带来Slice下降。后续应重点核查BLE配对、寄存器控制集合及算术映射，不能继续只按LUT数判断收益。

## 自检证据

| 项目 | 场景数 | 状态 | 结果JSON |
| --- | ---: | --- | --- |
| transitions | 4 | PASS | `sim/transitions_r4_final_scene_transitions_sim_result.json` |
| controls_cdc | 4 | PASS | `sim/transitions_r4_final_visual_controls_sim_result.json` |
| osd_pixels | 4 | PASS | `sim/transitions_r4_final_visual_osd_sim_result.json` |
| osd_equivalence | 4 | PASS | `sim/transitions_r4_osd_equivalence_sim_result.json` |
| luma_equivalence | 2 | PASS | `sim/transitions_r4_color_luma_equivalence_fix1_sim_result.json` |
| color_envelope | 1 | PASS | `sim/transitions_r4_final_color_envelope_sim_result.json` |
| legacy_scene | 4 | PASS | `sim/transitions_r2_scene_legacy_sim_result.json` |
| split_core | 6 | PASS | `sim/transitions_r4_split_core_sim_result.json` |
| circular_system | 4 | PASS | `sim/transitions_r4_circular_system_sim_result.json` |
| attack_bands | 3 | PASS | `sim/transitions_r1_attack_bands_sim_result.json` |
| spectrum_stage1 | 4 | PASS | `sim/transitions_r1_spectrum_stage1_sim_result.json` |
| layer_fft64 | 7 | PASS | `sim/transitions_r1_layer_fft64_sim_result.json` |
| split_spectrum | 9 | PASS | `sim/transitions_r1_split_spectrum_sim_result.json` |
| board_compile | 0 | COMPILE_PASS | `sim/transitions_r4_circular_board_sim_result.json` |

所有采用的结果再次核对了其记录的全部实际输入哈希、退出码、唯一TEST_PASS及预期场景集合。失败/失效结果完整保留，未计入通过数。
综合95条告警按路径、源码行号及综合实例编号归一化后与基线逐条一致；保留既有厂商SDRAM、未用只读RAM字节使能脚及FFT初始化告警。
详细场景ID、日志、工具、时间、输入核对结果见结构化证据。整板为真实active top和厂商模型的编译展开；系统夹具不是硬件验证。

## 剩余工作与限次

- 当前布局打包失败：4940 M-Slice + 4940 L-Slice，各类上限4900；未进入布线，未生成新bit。
- 当前版本没有最终STA；基线既有64个移相SDRAM setup违例，WNS -5.565ns，不能移植为当前版本结果。
- 未下载上板；系统仿真使用原有缩放数据夹具及150MHz参数，不能代替实际板级100MHz SDRAM时序验证。
- 功能自检与算术等价检查通过不代表整板全部输入、时序和硬件行为均已验证。

同一资源问题经历初次失败及3次修改重跑，自动预算已用尽。根据fpga-workflow规则50停止本轮修改重试，等待新信息、明确新一轮授权或问题前提实质变化。
下一轮建议：先针对packing中的单独SEQ/控制集合和较大算术块形成可等价验证的优化，再做受影响回归、综合、布局布线及最终STA；继续保留所有显示、音频及存储功能。

## 复现

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage syn -Tag <新tag>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage phy -Tag <新phy_tag> -SynthesisTag <新tag> -Seed 3 -GenerateBitstream
python -B scripts/report_scene_transitions.py
```

仿真复现：设置MODELSIM_CONFIG、EXPECTED_SCENARIOS为相应结果JSON记录的配置，SIM_OUTPUT使用新前缀，RUN_SIM=1（整板编译为0），再运行python -B sim/run.py。
