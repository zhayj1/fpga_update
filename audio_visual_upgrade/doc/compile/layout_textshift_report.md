# 文字整体下移29像素

歌名上沿y=45，与中心(160,165)、240×240封面的静态上沿对齐。歌手y=77；五行歌词顶部118/150/182/214/246，裁剪118..269。间距、横坐标、字体和滚动参数保持。

本次12个功能场景及板级编译展开通过，输入哈希与当前源码一致。
快速模型17帧和真实SDRAM争用4帧逐像素比对，覆盖标题/歌手/歌词、纵移0/16/32px、横滚、句子迁移及迟到取消。核心检查实际实例坐标及混色/OSD/HDMI行尾。

Slice 9759/9800，LUT 18317/19600，FF 11345/19600；BRAM9K 57/64、BRAM32K 7/16，DSP 27/29。

|路径组|setup/ns|setup违例|hold/ns|
|---|---:|---:|---:|
|video_clk -> video_clk|+2.094|0|+0.024|
|clk -> clk|+0.727|0|+0.032|
|sdr_clk -> sdr_clk|-0.154|9|+0.043|
|sdr_clk -> video_clk|+0.448|0|+0.244|
|video_clk -> sdr_clk|+0.257|0|+0.244|
|hdmi_5x_clk -> hdmi_5x_clk|+6.055|0|+0.285|
|sdr_clk -> sdr_clk_sft|-1.722|32|+5.001|
|sdr_clk_sft -> sdr_clk|-5.565|32|+9.430|

全局setup WNS -5.565ns，73个违例；hold 0个违例。
bit已生成，未上板；时序是否收敛以以上结果为准。此前文字花屏修复仍需实板验证。

- bit：output/layout_textshift_20261030/audio_visual_layout_textshift.bit
- SHA256：4623685fcb72beca289324f86129e358ff747255306755f8e5b4f55164bd8e4b
- SD卡字库及素材无需更新。
- 综合/布局布线：prj/td_build/textshift_r1_syn、prj/td_build/textshift_r1_congestion_seed3_phy。
- 本次仅一次综合和一次布局布线，无额外结构修复或种子重试。
