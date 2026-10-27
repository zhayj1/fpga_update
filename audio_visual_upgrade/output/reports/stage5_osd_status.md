# 阶段 5 OSD 按需显示与字形修复上板候选

日期：2026-10-27。状态：局部、core、整机仿真通过，TD 布局布线和 bit 生成完成；用户确认本次 bit 上板无问题。

## 本次修复

- 上电隐藏 OSD；长按 KEY4 显隐，停止操作约 5 秒自动隐藏。隐藏时 KEY2/KEY3 调整音量并打开设置页；隐藏时短按 KEY4 仍用于切图。
- OSD 汉字直接绘制卡中字库的 32x32 原始位图，半角字符使用 16x32 原始位图，取消此前 2x2 OR 压缩后再放大的做法。字库常量烧入片上 ROM，运行时无需额外读卡。
- 原有三页内容、攻击曲线与触发标记、灵敏度、音量和色彩参数、播放及五种音画效果继续保留。

## 候选 bit 与资源

- 文件：`prj/td_build/stage5_font_split_r1_seed3_phy/skeleton.bit`，651749 字节。
- SHA-256：`1888055E210DF5EFF9094E9CD27D3F78A201681D646FD0C4F52722B4A1A205E0`。
- TD 6.2.168116 最终物理占用：9717/9800 Slice（99.15%，余 83），55/64 块 9K RAM，6/16 块 32K RAM，26/29 DSP。
- 相比上一版阶段 5 `stage5_bands_ram_r1_seed2_phy`：Slice +74（9643→9717），9K RAM +2，32K RAM +1，DSP 不变。字库拆分并未减少实际 RAM；当前余量很紧，后续改动须重新物理实现。

## 验证

- OSD 局部 11 场景：`sim/stage5_font_split_osd_r1_sim_result.json`，PASS，含上电隐藏、按键调节与自动隐藏、三页排版及原始字形位图断言。
- 带真实 core 的 OSD 3 场景：`sim/stage5_font_split_core_r1_sim_result.json`，PASS。
- 整机 4 场景：`sim/stage5_font_split_integration_r1_sim_result.json`，PASS，含真实 SPI 启动、播放、切图渐变、跨歌与音视频流完整性；输入哈希在运行期间保持一致。
- seed3 最终时序：`video_clk`、`clk`、`sdr_clk` 同域 setup 分别 +1.106、+0.122、+0.010 ns；`video_clk→sdr_clk` +0.003 ns，`sdr_clk→video_clk` +1.722 ns；同域及跨域 hold 均为正，全局 hold +0.030 ns。
- 全局 setup -5.565 ns 仍为既有 SDRAM 相移时钟 `dq` 路径。该既有路径另一方向为 -1.889 ns，上一版为 -1.627 ns，恶化 0.262 ns；端点仍为 SDRAM 数据引脚。没有新增路径组的 setup/hold 违例。
- seed2、seed4 虽出 bit，但出现新增时钟路径 setup 违例，不用于上板。

## 上板观察

1. 上电应看不到 OSD；长按 KEY4 打开三页 OSD，约 5 秒无操作后自动隐藏。隐藏时按 KEY2/KEY3 应调整音量并弹出设置页；隐藏时短按 KEY4 应切图。
2. 检查“攻击检测、实时声学、音量色彩”等汉字是否保留笔画间隙，数字和百分号是否清晰，三页内容有无错位。
3. 检查音频连续、图片无缺行、切图及跨歌渐变正常；频谱、尖峰、封面回弹、圆环和色彩联动同时运行。

上一版阶段 5 和已验证阶段 4 bit 均未覆盖。用户于 2026-10-27 确认上述上板观察无问题。
