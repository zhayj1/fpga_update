# BMP 装载时缩小（2026-10-29）

本次授权：在 audio_visual_upgrade 实现图片缩小，完成编译、自检仿真和受影响回归；用户于 2026-10-29 追加授权继续综合、布局布线及生成 bit。实现结果见 `doc/compile/bmp_downscale_implementation_report.md`，本轮不下载。旧上板结论不适用于本次修改。

## 输入与目标

- BMP3：54 字节起的 BITMAPINFOHEADER（40 字节），24 bit BGR、无压缩，支持正高 bottom-up 和负高 top-down、像素前间隔及行末 4 字节补齐。
- 背景严格 4:3，宽高至少 640×480，输出 640×480；封面严格正方形且至少 240×240，输出 240×240。同尺寸逐像素通过。
- 默认源宽高各不超过 4096，文件不超过 64 MiB。非整数缩小比例合法。过小或比例错误不放大、不拉伸，报错且该资源无效。
- 封面身份由资源 ID 的低三位 3..5 确定，启动时锁存；0..2 是背景。SDRAM 槽、stride、图层位置、透明键 FF00FF、原封面 pop 动画保持既有契约。

## 抽样定义与接口

目标像素 (x,y) 对应逻辑从上至下原图：

`sx=floor((2*x+1)*source_width/(2*target_width))`

`sy=floor((2*y+1)*source_height/(2*target_height))`

使用中心最近邻。硬件为源像素/行推进的误差累加、减法、比较；无逐像素除乘法，无源行/整图缓存。bottom-up 行抽样在整除边界采用互补相位，确保两种存储方向得到相同画面。

`bmp_load.DOWNSCALE=1` 启用，`target_cover` 在 start 被接受时采样。默认 DOWNSCALE=0 保留旧接口几何语义供旧模块测试/复用。系统顶层默认启用缩小；缩小目标参数允许测试使用成比例的小尺寸。

## 流、缓存与错误

- clk=50 MHz，沿用 clk_sdr 共享 load_writeback；未增加 CDC。lo 数据只在 valid && ready 消费；FIFO 仅非 full 时写。PX_PUSH 保持 RGB 直到全部三个字节写完。
- 分离源行字节计数与目标 FIFO 字节数；未选择的行和像素仍从文件顺序消费。BMP padding 丢弃，目标行补零到 16 字节。
- cfg_first/cfg_words/cfg_wpr/cfg_down 和 img_w/img_h 全部描述目标图。finish_words 只报告已实际写出的完整 32 bit 字数。槽越界、错误路径不得提交有效资源。
- 保留流 EOF/错误排空、backend done、watchdog、复位取消契约。读卡耗时仍与原图文件长度有关。
- 新错误码 07：比例不符；08：尺寸不足；09：文件超过上限。其余沿用原错误码（01 头、02 宽/槽、03 截断、04 流错误/超时、05 格式、06 高度）。

## 验收

1. identity：两目标同尺寸、RGB/key/padding 完整通过。
2. ratio：整数与非整数缩小逐字节对比独立除法 golden。
3. orientation：同一逻辑图的正/负高结果一致，包括抽样恰好落在边界。
4. bounds：4096 上限、奇数方图行补齐、文件间隔、target metadata、容量/槽边界。
5. errors：过小、比例、宽高上限、文件上限、非法格式、截断、lo error、watchdog、reset，后续成功恢复。
6. stalls：独立输入停顿与 FIFO full，done 单脉冲、每笔一个 cfg/finish、读至 EOF。
7. writeback：真实异步 FIFO + writeback + ld 握手，核对每个 SDRAM 地址、字节和行方向。
8. catalog/top：大图目录可枚举且超限拒绝、first-wins；真实系统源依赖编译及可行的集成回归。

最近邻不会增加颜色插值，但细节可能混叠。无 JPEG/PNG 解码、任意比例裁剪或加边功能。资源适配和加载延迟以实际实现报告及上板为准。
