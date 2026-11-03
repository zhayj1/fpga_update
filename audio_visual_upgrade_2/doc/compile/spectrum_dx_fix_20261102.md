# r7 圆形频谱右半圈修复与候选实现

用户确认 r7 圆形频谱右半圈缺失。诊断发现综合网表的横向距离不等价：右侧 x=168 被当成距离 1016，导致有效范围判断屏蔽右半圈；零延迟门级即可复现。详见 `doc/review/r7_spectrum_right_root_cause_20261102.md`。

本次仅修改生产文件 `rtl/gfx/layer_spectrum_ring.v`。横向距离改为显式 11 位有符号差与按符号取绝对值。为适配器件，抗锯齿平方和阈值计算改成精确的 256×4 位常量逻辑表，再复用减法借位、缩短舍入与绝对值运算的位宽，保留完整距离范围判断。接口、流水级、原透明度/形状/颜色和频谱功能保持。

当前状态：已生成修复候选 bit，完成 RTL 与综合、物理网表的功能检查；未下载上板。全工程时序仍有违例，不能据此宣称整板验证通过。

## 验证

全部 26 个场景自检通过；审计脚本再次核对当前源码、厂商模型、测试、配置、数据镜像及构建输入哈希。测试使用 ModelSim 10.6e 和真实安路模型。

| 验证 | 结果与范围 |
|---|---|
| 横向距离 | 中心 160/320 各扫描 x=0..1023，2048 点 PASS |
| 常量透明度表 | 16×16 全部 256 输入对照原函数，PASS |
| 距离与范围优化 | 1,852,688 组：完整 signed across、六种 end2 的全 along、联合舍入边界；over/outside/alpha 与保存的原 RTL 相等 |
| 完整频谱 | 原 9 场景全部 PASS |
| 画面合成 | 原 6 场景全部 PASS |
| 综合网表 | 640×480 全帧，频谱长度 0/32/41，与原 RTL coverage 逐像素对照 |
| 最终物理网表 | 相同三帧和真实单元模型的零延迟对照 |

mapped：
```
# COUNTS length=0 gate=1000/1000 reference=1000/1000 errors=0
# SCENARIO_PASS mapped_coverage_length0
# COUNTS length=32 gate=6766/6766 reference=6766/6766 errors=0
# SCENARIO_PASS mapped_coverage_length32
# COUNTS length=41 gate=8384/8384 reference=8384/8384 errors=0
# SCENARIO_PASS mapped_coverage_length41
# TEST_PASS
```

physical：
```
# COUNTS length=0 gate=1000/1000 reference=1000/1000 errors=0
# SCENARIO_PASS mapped_coverage_length0
# COUNTS length=32 gate=6766/6766 reference=6766/6766 errors=0
# SCENARIO_PASS mapped_coverage_length32
# COUNTS length=41 gate=8384/8384 reference=8384/8384 errors=0
# SCENARIO_PASS mapped_coverage_length41
# TEST_PASS
```

门级验证隔离 frequency-ring coverage 依赖锥，固定显示就绪、效果使能与频谱数据输入。候选电路内部无 force 修正；仅在参考 RTL 固定输入寄存器。物理网表按位追踪打包 Slice 的依赖，保留真实厂商原语、参数及所需输入连接；同一 Slice 另一路若驱动坐标等测试切口，则仅断开该切口输出并记录到 candidate_coverage_manifest.json，避免与测试输入冲突。未使用的另一打包通道不属于验证范围。它不替代全系统 SDF 仿真或板级验证。

## 构建与资源

第一轮：r1 seed3（4914/4913 MSlice/LSlice）、r1 seed2（4929/4929）超限；r2 seed3（4880/4879）打包成功，但两处布线冲突失败；r2 seed2（4929/4929）超限。用户明确回复“给我继续跑”后开启第二轮。

r3 的综合 LUT 从 r2 的 17641 降到 17589，减少 52；r3 seed3 仍为 4913/4913 超限。最终采用同一 r3 网表、seed1、medium 布局时序努力度、routability 布线策略。约束、时钟频率及其他生产源均与 r7 相同。

最终构建：`prj/td_build/spectrum_dx_r3_seed1_medium_route_phy`。

| 资源 | 原 r7 | 修复候选 | 变化 |
|---|---:|---:|---:|
| Slice | 9757/9800 | 9775/9800 | +18 |
| LUT | 18174/19600 | 18191/19600 | +17 |
| 寄存器 | 11799/19600 | 11790/19600 | -9 |
| BRAM9K | 64/64 | 64/64 | +0 |
| BRAM32K | 16/16 | 16/16 | +0 |
| DSP | 29/29 | 29/29 | +0 |

综合告警 95 条，归一化后与 r7 完全相同，无新增或移除。仿真保留厂商网表可选端口未接、参考模块输出未接等告警；均为 Errors 0，不屏蔽功能断言。

## 最终时序

| 路径组 | r7 setup/ns | 候选 setup/ns | 候选 setup 违例端点 | 候选 hold/ns |
|---|---:|---:|---:|---:|
| video_clk -> video_clk | +0.721 | +2.560 | 0 | +0.027 |
| clk -> clk | +0.476 | +1.503 | 0 | +0.086 |
| sdr_clk -> sdr_clk | -1.854 | -0.226 | 11 | +0.095 |
| sdr_clk -> video_clk | +2.032 | +3.064 | 0 | +0.244 |
| video_clk -> sdr_clk | +0.083 | +0.848 | 0 | +0.244 |
| hdmi_5x_clk -> hdmi_5x_clk | +6.092 | +6.029 | 0 | +0.230 |
| sdr_clk -> sdr_clk_sft | -1.524 | -1.963 | 32 | +5.001 |
| sdr_clk_sft -> sdr_clk | -5.565 | -5.565 | 32 | +9.430 |

全局 setup WNS -5.565 ns、TNS -232.710 ns、75 个违例端点；hold 0 个违例端点。STA coverage 96.43%。本轮目标是修复确定的逻辑不等价，不重启此前已结束的全工程时序优化循环。

## 交付与证据

- 候选 bit：`D:\Verilog_teacher\guoyi\pro\audio_visual_upgrade_2\prj\td_build\spectrum_dx_r3_seed1_medium_route_phy\skeleton.bit`（701801 字节）。
- SHA256：`F747D22118CF701D31C3D6A32820796885C8A5AA2EAC632C392D2F8CBA5E251F`。
- 精确输入/测试/构建审计：`output/spectrum_dx_fix/verification_and_build.json`。
- 本轮状态与历史尝试：`doc/workflow/spectrum_dx_fix_state.json`。
- 原始实现报告：`prj/td_build/spectrum_dx_r3_seed1_medium_route_phy/route.qor`、`final_timing.rpt`。

复现（原构建目录保持，重跑需新 Tag）：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage syn -Tag spectrum_dx_r3 -LutStructure off
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Stage phy -Tag spectrum_dx_r3_seed1_medium_route -SynthesisTag spectrum_dx_r3 -Seed 1 -PlacementTiming medium -RouteEffort routability -GenerateBitstream
python output/spectrum_dx_fix/report_fix.py spectrum_dx_r3_seed1_medium_route_phy spectrum_dx_r3
```
