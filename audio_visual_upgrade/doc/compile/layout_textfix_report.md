# 歌词/歌名花屏修复：验证与实现

2026-10-30；EG4S20BG256；TD 6.2.168116；ModelSim 10.6e。

用户报告歌词和歌名稳定错误叠加闪烁，歌手与OSD正常。此次修复针对已确认的取字长组合路径、换字控制和视频混色时序。
功能仿真及构建结果不能直接证明上板症状已消失；新版尚未上板。

## 修改

- 高/低字节ROM分解完整字库地址运算；7540个目录地址逐项核对实际FONT.HZK。
- 简化末像素与32位字切换控制；时间戳按字节比较后寄存合并。
- 行截止使用SDR域捕获的坐标；描述符/相位迁移控制在像素域提前寄存。
- 色彩处理与精确16级文字混色分拍；文字、OSD、DE、VS、行尾同步对齐。
- OSD归一化乘积与绘图拆拍，复用外部对齐级；图片写回操作数和地址提前寄存。
- 字体、字号、字库、五行布局、14字窗口、平滑滚动、逐字变色及其他视觉效果保持。

## 验证

当前输入哈希一致的52个功能场景及板级编译展开通过。
真实SDRAM及四图像客户端争用下，四个640×480帧逐像素比较；覆盖纵移0/16/32px、切句和横滚。
完整字库7540字、两字号；争用最慢3147拍@100MHz（31.47μs），小于32μs。
OSD六帧逐像素比对及变化幅度历史检查通过；原有SD/FAT、切歌和PCM/视频回归通过。
核心混色覆盖全部16级alpha与淡入淡出端点；OSD帧163840像素、256个640像素行尾逐项核对。

## 资源与时序

|资源|上板失败版|当前|变化|
|---|---:|---:|---:|
|Slice|9791/9800|9701/9800|-90|
|LUT|18375/19600|18234/19600|-141|
|寄存器|11203/19600|11339/19600|+136|
|BRAM9K|55/64|57/64|+2|
|BRAM32K|7/16|7/16|+0|
|DSP|27/29|27/29|+0|

MSlice 4852/4900，LSlice 4849/4900。

|路径组|失败版setup/ns|当前setup/ns|当前setup违例|当前hold/ns|
|---|---:|---:|---:|---:|
|video_clk -> video_clk|-5.178|+1.592|0|+0.027|
|clk -> clk|+1.811|+0.202|0|+0.103|
|sdr_clk -> sdr_clk|-5.024|-0.722|5|+0.086|
|sdr_clk -> video_clk|-0.369|-0.223|1|+0.244|
|video_clk -> sdr_clk|+0.167|+0.878|0|+0.244|
|hdmi_5x_clk -> hdmi_5x_clk|+3.972|+4.031|0|+0.230|
|sdr_clk -> sdr_clk_sft|-1.583|-1.567|32|+5.001|
|sdr_clk_sft -> sdr_clk|-5.565|-5.565|32|+9.430|

全局setup WNS -5.565ns，TNS -206.326ns，70个违例；hold WNS +0.027ns，0个违例。
STA coverage 96.61%。未修改时钟、管脚和时序例外。

既有移相SDRAM组以外还剩6个setup违例，不能称文字问题已修复：

- `sdr_clk -> sdr_clk`：5个，最差-0.722ns；`u_core/g_aa_text$u_lyr/u_row/state_reg[3]_syn_15.clk` → `u_core/g_aa_text$u_lyr/u_row/word2_reg[13]_syn_4.ce`。
- `sdr_clk -> video_clk`：1个，最差-0.223ns；`u_core/u_pick/ttl_cnt_reg[2]_syn_4.clk` → `u_core/g_aa_text$u_lyr/s_tv_reg_syn_5.a[1]`。

完整端点与下一轮结构修复建议见doc/compile/repair_report.md；当前候选仅供验证。

三次自动结构修复已用尽，当前停止继续修改RTL或换种子；后续需新信息或用户明确授权新一轮。

## 交付与限制

- bit：`output/layout_textfix_20261030/audio_visual_layout_textfix.bit`。
- SD卡完整FONT.HZK及其他素材无需更新；旧正常版和旧失败版bit均保留。
- 综合/物理：`prj/td_build/textfix_r4_syn`、`prj/td_build/textfix_r4_congestion_seed3_phy`。
- 完整日志、输入哈希、警告和物理结果见同包verification_and_build.json。
- SHA256：`b6144c0fa2024515c0cdaef404c8b292ca2a04535643d63851e1b9fced383232`。

- Board symptoms have not been re-tested with this candidate.
- No post-route timing simulation, new-layout SD/FAT-to-HDMI boot or board download performed.
- The real SDRAM contention tests cover the simulated arbitration phases, not all possible phases.
- The core composition test drives controlled layer pixels; storage and full-layer checks are separate.
- Legacy SD/FAT/audio integration uses TYPOGRAPHY=0 and reduced image targets; complete-font and new layout checked separately.
- Existing LRC1 limits remain: 64 lines, 488 records, 19 characters per sentence and 24 for title/singer.
- Global setup timing is not closed; see clock-group results.
- 6 setup endpoints remain outside the pre-existing shifted-SDRAM groups, including the text data capture and title descriptor paths.
- The three automatic structural repairs are exhausted; further RTL/route retries are stopped pending a new authorized repair round or materially new evidence.
