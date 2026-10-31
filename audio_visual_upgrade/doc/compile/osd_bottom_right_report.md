# OSD 右下角贴边

OSD 从 x=424..623、y=16..239 移到 x=440..639、y=256..479，保持 200×224 像素。右边框与下边框贴住有效画面最后一列、最后一行。

仅修改 osd_layer_small.v 的绝对几何常量。三个页面、字体与抗锯齿、色值、曲线与数值、三拍延迟保持。歌词、歌名、歌手和封面代码未变；OSD 显示时仍按原优先级覆盖下层。

8 个自检场景及板级编译展开通过：六个完整 640×480 帧共 1,843,200 个光栅位置，独立原图反向平移对照；动态历史曲线；隐藏/消隐及历史状态；完整合成链路 307,200 像素、480 行和 AX 行尾核对。

综合、布局布线、bit 生成完成，一次实现，seed=3、routability。未下载或上板，SD 卡无需更新。

|资源|上一版|本版|
|---|---:|---:|
|Slice|9649/9800|9665/9800|
|LUT|18173/19600|18083/19600|
|FF|11330/19600|11336/19600|
|BRAM9K|57/64|57/64|
|BRAM32K|9/16|9/16|
|DSP|25/29|25/29|

Setup 违例 69 → 69，本版非移相组 5，Hold 违例 0；全局 WNS -5.565 ns、TNS -205.473 ns。

时序尚未闭合。用户确认上一版实板正常不等于本版时序通过。没有添加 false path/multicycle，没有改变 PLL、频率、管脚和 SDC。本次只完成布局调整，不继续上一轮已停止的时序优化。

|路径组|本版 Setup/ns|违例端点|
|---|---:|---:|
|video_clk -> video_clk|+0.690|0|
|clk -> clk|+2.132|0|
|sdr_clk -> sdr_clk|-0.406|5|
|sdr_clk -> video_clk|+2.258|0|
|video_clk -> sdr_clk|+0.102|0|
|hdmi_5x_clk -> hdmi_5x_clk|+5.283|0|
|sdr_clk -> sdr_clk_sft|-1.477|32|
|sdr_clk_sft -> sdr_clk|-5.565|32|

综合、物理与仿真告警保留于 verification_and_build.json 及原始日志；综合告警与上一版一致，物理告警存在差异，见证据。

bit：output/osd_bottom_right_20261030/audio_visual_osd_bottom_right.bit
SHA256：58bfc66ca85e42400f6e950dc1c5b51e84a1bfde94e16a20eb7c04a71ed26c4a
物理报告：prj/td_build/osdcorner_r1_congestion_seed3_phy/final_timing.rpt
证据：output/osd_bottom_right_20261030/verification_and_build.json
源文件备份：output/osd_bottom_right_20261030/source_before/
