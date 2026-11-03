# BMP downscale 验证记录

日期：2026-10-29。实际工程 `D:/Verilog_teacher/guoyi/pro/audio_visual_upgrade`。

结论：已完成代码、整板编译展开和 33 个功能自检场景。当前源码及测试输入哈希与最终 PASS 记录一致。用户追加授权后已执行 TD 综合、布局布线及 bit 生成，资源与时序结果见 [实现报告](bmp_downscale_implementation_report.md)。未下载上板。

## 实现

`bmp_load` 增加加载期最近邻缩小：源像素计数与写出计数分离，中心抽样，正/负 BMP 高度具有相同逻辑图像。背景固定 640×480、封面固定 240×240；原图上限单边 4096，文件 64 MiB。格式保持 BMP3/24-bit/uncompressed；拒绝放大和比例不符输入。

`skeleton_core` 默认开启；从 catalog resource ID 的低三位确定背景/封面，loader 在 start 锁存。`resource_catalog` 提高原文件大小门限；SDRAM 容量仍按目标几何检查。现有 display/SDRAM 布局、播放器和封面 pop 机制沿用。

数据路径只增加坐标误差累加/比较，无新行/帧 RAM、无逐像素乘除法。目标行跨度/总字数选择常量，启用缩小时消除旧的可变图像 span 乘法。TD 综合确认 loader 的 DSP 从 2 个降为 0 个，全工程 DSP 从 26 个降为 24 个，RAM 总数保持 61 块；物理资源以实现报告为准。

额外修复：紧凑测试图片更早出图，暴露 `layer_fft64` 在第一组频谱完成前读取未初始化 heights RAM 的旧问题。新增一个 `active_valid`，首组完整频谱在帧边界提交之前禁止其像素有效，复位时清除有效位，保留 RAM 推断。独立旧版失败日志 `sim/downscale_fft_init_before_sim.log` 在 x=1,y=157 得到 `actual=x expected=0`。

## 场景与证据

| 层级 | 自检内容 | 当前证据 |
| --- | --- | --- |
| 生产尺寸缩小器 | identity、整数/非整数、方向、透明色、输入/FIFO停顿、4096×3072完整背景、4096×4096方图开头截断、槽末边界、过小/比例/超限拒绝、EOF/流错/超时/复位恢复 | `sim/downscale_unit_r2_sim_result.json`：6/6 PASS |
| 实际写回链 | 独立50/100 MHz时钟、真实BRAM模型及异步FIFO、writeback、ld ACK/取数停顿，核对每个地址与32位字；小目标的非零行补齐及跳过源行 | `sim/downscale_writeback_r2_sim_result.json`：3/3 PASS |
| 旧BMP路径 | 关闭缩小，原格式/错误优先级/容量/截断/复位回归 | `sim/downscale_legacy_r1_sim_result.json`：5/5 PASS |
| 资源目录 | 16首×128种文件组合、索引、重复优先、64 MiB边界、并发端口、取消 | `sim/downscale_catalog_r1_sim_result.json`：8/8 PASS |
| 频谱首次出图 | 未有完整bank时保持透明、reset丢弃旧有效性、原柱形/换bank/尖峰/衰减 | `sim/downscale_fft_init_r1_sim_result.json`：7/7 PASS |
| 整板源编译 | 实际 `skeleton_top`、当前参数和厂商依赖编译展开，未执行 run | `sim/downscale_board_compile_r2_sim_result.json`：COMPILE_PASS |
| 整机缩小集成 | SPI/FAT原文件读取、实际装载/SDRAM、显示、手动/轮播/自然切歌、槽保护、PCM与AXIS完整性 | `sim/downscale_system_r3_sim_result.json`：4/4 PASS |

整机数据由 `scripts/setup_downscale_tests.py` 生成，保留原 FAT 镜像音频/歌词/字库，仅替换12张 BMP。为控制 SPI 仿真时间，整机使用背景 12×9 → 8×6、封面 8..10方图 → 5×5；正/负高度均有。几何小目标仅在 TB 的 defparam 中覆盖，实际整板默认仍为 640×480、240×240。整机原有 undersized 图像配置显式 `BMP_DOWNSCALE=0`，不作为新缩小功能的证据。

新 TB 的预期由整数除法坐标公式计算，与 RTL 误差累加实现独立。源码/模型/fixture hash、编译与仿真退出码、实际场景集合、命令和工具版本记录在各 `*_sim_result.json`。未生成波形；保留全部失败日志。

## 复现

在项目根目录使用已安装的 ModelSim SE-64 10.6e：

```powershell
python scripts/setup_downscale_tests.py
python scripts/verify_downscale.py unit
python scripts/verify_downscale.py writeback
python scripts/verify_downscale.py legacy
python scripts/verify_downscale.py catalog
python scripts/verify_downscale.py fft_init
python scripts/verify_downscale.py board
python scripts/verify_downscale.py system
python scripts/report_downscale.py
```

`--compile-only` 只编译和展开；`--suffix` 保存独立运行记录。系统测试上限 1500 秒，内部仿真超时 550 ms；其余测试具有各自 timeout 和严格 SCENARIO_PASS/TEST_PASS 校验。

## 修复过程

- TB 超时常量：首次超出默认32位，第一次修复缺少延时表达式括号；第二次改为 `#(64'd5000000000)` 后编译通过。
- unit r1：复位测试的手动启动未更新预期 CFG，误用上一张封面的跨度。将 prepare 的参考配置初始化补全；r2 全部场景通过，RTL 无需修改。
- system r1/r2：首屏叠加层出现 X，r2 增加诊断确认图像层正常、overlay有效性未知。独立 FFT 测试复现，增加 active_valid 后7个场景通过，system r3 的4个场景全部通过。未屏蔽未知像素断言。

## 物理验证边界

用户于 2026-10-29 授权继续综合、布局布线，已生成包含缩小功能的新 bit。对照采用修改前 `uartless_r1_seed1_phy` 的 9581/9800 Slice；使用相同管脚和时序约束，保留 SDRAM 移相路径分析。各布局种子的资源、setup/hold、bit 哈希及选择依据见 [实现报告](bmp_downscale_implementation_report.md)。工具完成不等于全工程时序收敛，亦不等于上板通过。

ModelSim 模块测试只有既有 `-novopt` 提示；整板/系统另有既有未接观察输出及 TB key2/key3 端口提示。厂商 SDRAM 仿真采用原工程的 `+notimingchecks`，系统沿用150 MHz仿真配置；TD 当前实现报告的 SDRAM 时钟为100 MHz，其物理时序见实现报告。HDMI为stub，未验证真实TMDS。

尚未执行下载和实板验证。读卡延迟、切歌时资源是否就绪及实图质量仍需上板确认。大图仍完整顺序读取，最近邻可能混叠。
