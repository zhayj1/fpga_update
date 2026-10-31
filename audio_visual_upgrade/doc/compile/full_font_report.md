# 完整 GB2312 字库 TYP2：实现与验证

日期：2026-10-30；EG4S20BG256；Tang Dynasty 6.2.168116；ModelSim 10.6e。

完整字库、RTL、功能仿真、综合、布局布线和bit已生成。以后更换GB2312范围内中文歌曲无需重建字库。 新TYP2尚未上板；全工程时序尚未收敛，不能把生成bit当作时序通过。

## 交付与换卡

- bit：`prj/td_build/typography_full_r1_congestion_seed3_phy/skeleton.bit`
- 完整卡包：`output/typography_full_20261030/card_typography_full.zip`
- 字库单文件：`output/typography_full_20261030/sd_card/FONT.HZK`，3,856,960字节。
- 本次必须同时更新bit与FONT.HZK，TYP1旧bit不兼容。其他卡素材可保留。
- 后续换歌只需按项目要求准备WAV、LRC1和图片；不需重新生成字库或综合。
- 范围为GB2312全部7445字符（6763汉字、682符号）与ASCII 0x20..0x7E；不是全Unicode。
- 现有LRC1格式64行、488字记录、歌词每行19字、歌名/歌手各24字等限制不改变。
- 随包仍是原45秒demo音频；45行全歌歌词均有字形，但字库不会延长音频。

## 显示与资源

华文琥珀24px歌词/歌名、20px歌手及16级覆盖率保留；OSD幼圆16px不变。独立比较原70个字形的64,280个有效像素，全部相同。新增少数字形仅平移不到一个显示像素以避免越界，未裁切或缩字。

四组640×480背景、四组240×240封面、两份歌词表与完整字库共8,243,456字节，8MiB SDRAM剩余145,152字节（141.75KiB）。字形去掉32像素行填充；保留固定编码槽直接寻址，省去逐字目录读取；共用32bit移位器及一笔LRC读取的两条记录，无新增BRAM/DSP。

|资源|TYP1物理结果|TYP2物理结果|变化|
|---|---:|---:|---:|
|Slice|9697/9800|9721/9800|+24|
|LUT|18048/19600|18125/19600|+77|
|寄存器|11228/19600|11146/19600|-82|
|BRAM9K|55/64|55/64|+0|
|BRAM32K|7/16|7/16|+0|
|DSP|27/29|27/29|+0|

综合口径：LUT17668→17711，寄存器11218→11134；与表中布局布线后的物理口径分开统计。

## 验证与时序

34个功能自检场景、4个独立素材检查及板级展开通过，输入哈希与当前文件一致。
PC检查全部7540字形的两字号，共7,359,040个存储像素；使用独立字节解析器验证两份LRC各45行，纠正旧生成器把8word头长度当行数的问题。
真实3,856,960字节文件经font_load和公共FIFO/writeback逐字比对，覆盖2MiB边界、尾部、补零、短文件、容量/地址/整数溢出拒绝与恢复。
真实厂商加密SDRAM控制器与IS42s32200模型运行100MHz：完整字库写入后读遍7540字符两字号；首末字形全部行、LRC最后记录、四路图片争用均自检。
争用测试同时读取两背景及两封面共1320word，覆盖19/24字符、两字号、中文/ASCII/符号、每一字形行及奇偶LRC起点；最慢3148拍，即31.48μs，小于32μs行周期。该数值是模型场景结果，不是板级时序证明。
TYP2装载/显示映射、四槽轮转、双歌词切换、混色/OSD对齐、取消与迟到恢复均验证。旧模式真实SPI/FAT/音频/图片切换回归另行通过。
未做TYP2从SD/FAT启动到字幕的完整整机仿真，也未做新bit上板验证；上述验证层级不混同。

setup WNS -5.565ns，TNS -333.047ns，违例端点185个；hold WNS +0.024ns，违例0个。STA coverage 96.63%。

|时钟组|setup WNS/ns|setup违例端点|
|---|---:|---:|
|video_clk -> video_clk|-3.206|44|
|clk -> clk|+0.460|0|
|sdr_clk -> sdr_clk|-2.450|76|
|video_clk -> sdr_clk|-0.012|1|
|sdr_clk -> video_clk|+2.422|0|
|hdmi_5x_clk -> hdmi_5x_clk|+5.275|0|
|sdr_clk -> sdr_clk_sft|-0.964|32|
|sdr_clk_sft -> sdr_clk|-5.565|32|

未通过全部setup时序时，本bit仅作为待上板验证的功能候选。首轮在x23y59_local6发生两条复位网的局部布线冲突；保持综合网表和种子3，针对拥塞改用routability布线策略。未修改约束来隐藏违例，也未循环更换布局种子。

## 证据

- 资源/时序：`prj/td_build/typography_full_r1_congestion_seed3_phy/route.qor`、`skeleton_phy.area`、`final_timing.rpt`。
- 汇总及每项日志：`output/typography_full_20261030/verification_and_build.json`。
- 全字库像素、LRC和包校验：`output/typography_full_20261030/asset_check.json`。
- 冻结格式与存储契约：`doc/spec/full_font_behavior_spec.md`。
- bit SHA256：`4BE042262FAD8A3F725DBCEBDACDCF2ABC33ECE789CD9CED601BE105CB08C9B0`。
- 卡包 SHA256：`813d9dc6b9d2c208dcb6cda22300e852a200cf28035f661b0da7c6be0fc3d230`。
