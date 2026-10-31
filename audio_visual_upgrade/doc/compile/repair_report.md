# 阶段5 OSD 实现阻塞记录

日期：2026-10-27。目标器件 EG4S20BG256，TD 6.2.168116。当前 RTL 保留三页 OSD，但没有合格的阶段5 bit，尚未上板验证。

## 当前证据

- 最后保留的源码与 `prj/td_build/stage5_osd_r20_syn/inputs.json` 全部源文件哈希一致。综合完成，`skeleton_gate.area` 为 18075 LUT、11601 寄存器、53 块 9K RAM、5 块 32K RAM、26 DSP。
- `prj/td_build/stage5_osd_r20_seed3_phy` 在放置打包报告 `PHY-9009`：4926 个 M-Slice，超过器件 4900 个上限 26 个；同时 4927 个 L-Slice。布线和时序未完成，没有 bit。不能用 4926+4927 作为最终 Slice 使用量。
- 阶段4已上板基线 `spectrum_floor_restore2_seed4_phy`：9383 Slice、52 块 9K RAM、4 块 32K RAM、21 DSP。阶段5当前综合相对基线新增 1 块 9K、1 块 32K、5 DSP；Slice 净增仍需成功物理实现后才能确认。
- `sim/osd_stage5_r20_final_sim_result.json`：PASS，含按键、字库、三页、字符对齐、参数上下限、曲线历史重缩放、数值条宽度等 11 场景。
- `sim/osd_core_r20_final_sim_result.json`：PASS，含真实 core 的 1920 像素边界、音量增益和色彩参数接线 3 场景。字库文件加载路径已在测试配置中修正。
- `sim/stage5_integration_r19_sim_result.json`：PASS，旧播放底座四场景。该回归使用 `en_osd=0`，不能代替带 OSD 的卡上整机验证；当前 core 与该回归的源代码仍一致。

## 修复经过

1. r17 seed3 曾生成 bit，物理结果 9796 Slice，但 `video_clk` Setup -3.068 ns、`clk` Setup -1.463 ns 和新增 Hold -0.011 ns；该 bit 不交付上板。seed1/4 路由冲突，seed5 容量失败。
2. r18/r19 对 OSD 行描述和数值数据分拍，曲线改存原始攻击量并按当前 `max(5, baseline+4*deviation)` 重画；修正 core 的一像素对齐。r19 物理打包为 4975/4900 M-Slice，停止于 `PHY-9009`。
3. r20 将数值字形改为固定右对齐字符槽，综合 LUT 从 r19 的 18261 降至 18075；物理打包降至 4926 M-Slice，但仍超限。
4. r21 行标签直查、r22 行首串行十进制转换、r23 行首串行数值条乘法均通过相关仿真，但综合分别为 18220、18301、18219 LUT，面积收益不成立。已逐项撤回，最终源码与 r20 综合哈希相同。
5. 用户明确要求继续后启动新一轮：r24 复用字库 RAM 空闲端口做标签映射，综合 18263 LUT，超过 r20 的 18075；撤回。
6. r25 复用字库 RAM 空闲端口做 0～260 全范围 BCD 查表，全范围仿真通过；综合 18136 LUT、53 块9K、5块32K、26 DSP。物理打包 4993/4900 M-Slice，`PHY-9009`，撤回。
7. r26 将固定标题和行标签预渲染到 ROM，局部与 core 仿真通过；综合 18190 LUT、53 块9K、7块32K、26 DSP。物理打包 4933/4900 M-Slice，`PHY-9009`，撤回。恢复 r20 后再次运行局部与 core 仿真均 PASS，源文件哈希与 r20 综合记录全部一致。
8. 用户再次同意继续后尝试 r27：OSD 颜色选择改用调色板编号。局部与 core 仿真通过，综合 18279 LUT，物理打包 4983/4900 M-Slice；撤回。
9. r28 将五个参数更新共用一个 9 位增减器，局部 11 场景与真实 core 3 场景 PASS；综合 18273 LUT，比 r20 增加 198。撤回。
10. r29 恢复独立参数更新，并将曲线历史地址改为逐像素递推。局部与真实 core 仿真 PASS；综合 18409 LUT，比 r20 增加 334。撤回。仅恢复地址路径后的 r30 综合仍为 18184 LUT，比 r20 增加 109；随后精确恢复 r20 控制器。现有源码全部源文件哈希再次与 r20 综合输入匹配。

按 `fpga-workflow` 的同类问题有限修复规则，用户授权的第三轮自动修复已用尽。这一轮三种新结构均无容量收益。后续需要重新设计 OSD 的面积与时序关键通路并有新依据后再做物理实现；不能通过换种子或忽略新增违例来宣称完成。阶段4的已验证 bit 保持独立可用。

## 后续结果（2026-10-27）

用户随后明确授权修改架构及代码以保留功能并生成 bit。`spec_bands64` 的 5 位同步历史 RAM 使综合 LUT 相比 r20 降低 354，整机四场景回归通过。同一综合网表的 seed1、seed5、seed6 生成 bit，但有新增同域 setup 违例，均不交付。

seed2 完成布局布线并生成 `prj/td_build/stage5_bands_ram_r1_seed2_phy/skeleton.bit`，9643/9800 Slice。`video_clk`、`clk`、`sdr_clk` 同域 setup 分别为 +0.156、+0.589、+0.184 ns，hold 均为正。仅余与阶段4相同的 SDRAM 相移时钟数据引脚路径组：最差 -5.565 ns；另一方向最差 -1.627 ns，阶段4基线 -1.417 ns。当前没有新增 setup/hold 违例。完整状态及上板观察项见 `output/reports/stage5_osd_status.md`；板上结果待确认。

## 按需显示与字形修复（2026-10-27）

用户上板指出 OSD 常显和汉字笔画粘连。控制器改为上电隐藏、操作时弹出和 5 秒无操作隐藏；字形改为原始 32x32 汉字及 16x32 半角位图。局部 11 场景、core 3 场景、整机 4 场景均 PASS。字库拆分后的综合为 55 块 9K、6 块 32K、26 DSP。可布性路由 seed2、seed4 均有新增 setup 违例，不交付；seed3 最终 9717/9800 Slice，所有非 SDRAM 相移数据引脚路径组 setup/hold 均为正，bit 哈希和完整数据见 `output/reports/stage5_osd_status.md`。既有 SDRAM 数据路径另一方向从上一版 -1.627 ns 变为 -1.889 ns，需在上板观察中留意读写稳定性。

## BMP 缩小功能实现（2026-10-29）

用户授权“继续综合布局布线”。`bmp_downscale_r1_syn` 综合完成；固定输出几何使全工程 DSP 从26降为24，RAM保持55块9K和6块32K。本轮未改RTL或约束，现有33个自检场景的输入哈希保持一致。

首次 seed1 完成并生成bit，但视频同域 −0.430 ns、SDRAM同域 −1.489 ns，以及视频→SDRAM −0.174 ns。随后有限比较三个种子：seed3、seed2、seed4，均完成布线和bit生成；SDRAM同域最差裕量依次为 −0.323、−0.513、−0.658 ns，仍未消除新增违例。本轮停止继续换种子，保留全部证据。

当前候选 `bmp_downscale_r1_seed3_phy`：9420/9800 Slice、24 DSP、61 RAM。视频同域 +3.105 ns、50MHz同域 +0.757 ns，hold无违例；SDRAM同域9个setup违例，最差是歌词行 `u_core/u_lyr/u_row/wd_reg[26]` → `err_t_reg[1]`，−0.323 ns。原有64个SDRAM移相路径违例仍在，全局WNS −5.565 ns。该bit仅为待处理时序的候选，不能称时序通过或上板通过。

完整资源、各组时序、四种子比较及bit哈希见 `doc/compile/bmp_downscale_implementation_report.md` 和相邻结构化结果JSON。后续应依据实际负裕量路径进行结构优化、重跑受影响仿真及物理实现；本轮没有下载板卡。

## 五行布局后的歌词/歌名花屏修复（2026-10-30）

用户报告：只有歌词、歌名稳定显示错误叠加花屏闪烁；歌手和OSD正常。此前完整字库版上板正常；五行布局版失败。症状本身不能证明唯一根因，以下只记录已由STA确认的缺陷和实际修复结果，尚未重新上板确认。

### 三次结构修复与实际证据

1. `textfix_r2_congestion_seed3_phy`：用512×18双端口ROM分解GB2312字库地址，移除换字空拍。7540个目录与当前FONT.HZK逐项比对通过。Slice9757，setup162，视频域−3.880 ns，SDR域−1.633 ns；取字与视频相关违例尚存。
2. `textfix_r3_congestion_seed3_phy`：缩短32位字装载控制，时间戳分字节比较，跨域坐标先捕获，色彩处理与精确16级文字混色分拍且对齐有效信号。Slice9720，setup116，视频域−1.253 ns，SDR域−2.673 ns；SDR→video +2.000 ns、video→SDR +0.110 ns；hold无违例。剩余主路径是OSD归一化、图片写回共享加减及文字合法性/描述符校验。
3. `textfix_r4_syn` / `textfix_r4_congestion_seed3_phy`：OSD乘积与绘图拆拍并复用原对齐级，保留全部精度；图片写回预寄存步长、地址和剩余计数；提前寄存字合法性和标题变化。最终Slice9701/9800（MSlice4852/4900、LSlice4849/4900），LUT18234，FF11339，57块9K+7块32K RAM，27 DSP。视频域+1.592 ns，控制域+0.202 ns，video→SDR +0.878 ns，HDMI串行域+4.031 ns；SDR域−0.722 ns，SDR→video −0.223 ns。setup70个端点，hold0个；全局WNS−5.565 ns、TNS−206.326 ns，其中既有移相SDRAM两组64个端点。

第三次修复后52个功能场景及板级编译展开通过，全部输入哈希与当前源码一致。完整7540字、两字号真实SDRAM争用测试最慢3147拍@100MHz=31.47μs，小于32μs；四个640×480帧真实SDRAM整层逐像素比对、切句、横滚、OSD变化幅度历史、混色与行尾检查均通过。旧SD/FAT/音频整机回归已重新执行并通过，但采用TYPOGRAPHY=0、缩小图片和HDMI stub；新版完整字库SD/FAT到HDMI启动、后仿和新bit上板未验证。

### 剩余6个非移相setup端点

|路径|数量|最差裕量|含义|
|---|---:|---:|---|
|text_row_aa state → word2接收使能|1|−0.722 ns|RX状态、skip_words、stored译码组成字数据写使能；最差10.470 ns中布线占8.850 ns，不能只继续压算术逻辑。|
|sdram_arb n → settle|4|−0.170 ns|16位n+1与len比较和状态控制扇入；另两个端点为−0.046 ns。|
|lyric_pick ttl_cnt → layer_text_aa s_tv|1|−0.223 ns|完整描述符校验含fc+cnt及边界比较，直接进入视频域快照有效位。|

精确端点和延迟见`doc/compile/layout_textfix_remaining_paths.json`；原始报告为`prj/td_build/textfix_r4_congestion_seed3_phy/final_timing.rpt`。未修改时钟、管脚、false path或multicycle约束。综合告警归一化后与第二轮相同，无新增告警类型。

### 当前停止条件和下一步

依据`fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md`：“预算用尽写 doc/compile/repair_report.md，说明尝试、剩余错误、证据和下一步，停止自动重试。”同问题三次自动结构修复已用尽，跨轮继续不重置次数；当前停止RTL修改和换种子，不将仿真通过或已生成bit写成硬件问题已修复。

下一轮有据可查的方向：

- 将取字RX接收资格预译码为独立寄存控制，分开紧急取消与字写使能，降低word寄存器组使能扇出；保持每拍接收、取消排空和最长行时限契约。
- 先捕获原始描述符，在目标域分拍完成范围与fc+cnt校验，校验结果就绪后才提交；保持desc_tgl的稳定窗口和快照原子性，并对五行、标题、歌手共用同一规则。
- 对仲裁器提前计算末字条件，保持首字地址、刷新暂停恢复、写后间隔和客户握手的逐拍行为；必须重新执行仲裁器协议/器件模型验证及全部受影响集成回归。

以上为建议，尚未实施。继续修复需要用户明确授权新一轮或实质新信息；候选bit与报告已整理到`output/layout_textfix_20261030`。SD卡完整字库与素材格式未改，无需换卡文件。原正常版和原失败版bit均保留。


## 2026-10-30 时序违例专项收敛

最终选择R1；setup端点152→69，hold为0。普通路径剩5端点；全局WNS -5.565ns。

|轮次|Setup端点|普通路径端点|TNS/ns|Slice|选择|
|---|---:|---:|---:|---:|---|
|R1|69|5|-203.465|9649|保留|
|R2|123|59|-233.139|9773|未选中|
|R3|93|29|-213.358|9640|未选中|
|R4|72|8|-200.360|9730|未选中|

综合/物理告警完整记录于结构化证据。保留厂商SDRAM未驱动脚、FFT初始化及既有放置告警；新增u_palette bea/beb告警：RTL均接常量0，BYTE_ENABLE=0且双口写使能为0，属于只读ROM不使用的字节写掩码；综合将未驱动项置0。独立色表和逐像素仿真均已核对。


本轮初次结构修改及3次自动重试已用尽。依据`C:/Users/Lenovo/.codex/skills/fpga-workflow/workflow/rules/50-fpga-compile-fail-routing.md`：“预算用尽写 doc/compile/repair_report.md，说明尝试、剩余错误、证据和下一步，停止自动重试。”

停止自动修改/实现；没有新增例外、降低频率、调整PLL或下载。剩余普通路径按本轮timing_cleanup_report中的实际端点处理；SDRAM移相路径须核实厂商硬宏模型与DQ读/写/三态采样契约，再决定控制器结构，不能仅凭实板正常或厂商参考也报错予以豁免。

完整报告：doc/compile/timing_cleanup_report.md；证据：output/timing_cleanup_20261030/verification_and_build.json。
