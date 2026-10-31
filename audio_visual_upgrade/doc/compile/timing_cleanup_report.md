# 时序优化结果

最终选择R1。

本轮综合、布局布线及bit生成完成。Setup违例端点 152 → 69，hold违例 0；非移相组剩余setup端点 5。
全局时序仍未闭合，不能把bit生成或功能仿真通过写成时序通过。

## 修改与功能验证

OSD末级实时RGB混色改为1024×32同步色表；保持三拍输出延迟、全部16级覆盖率、各层优先级以及逐通道精确颜色值。色表全1024项独立算式检查通过。
GB2312合法性拆为高低字节并行登记，在原ADDRESS拍合并，不增加取字周期。描述符合法性在SDR源域登记后随原toggle稳定采样，保留全宽非法输入检查。
最终选择R1；已精确恢复R1综合manifest中的源码并逐项核对SHA256。R2/R3/R4的选句、仲裁器、字库头、频谱改动均保存在候选备份，不进入最终bit。
五行位置118/154/190/226/261、36/36/36/35行距、平滑滚动、横滚、完整7540字库及抗锯齿效果保持。
37个自检场景及板级编译展开通过，源码/ROM/config哈希均为当前。
包括OSD逐像素及延迟、全7540字、异常和恢复、五行快速像素参考、真实SDRAM争用；追加1342次描述符提交，覆盖四种源/像素相位、488字符边界、19/24长度上限、高位非法、vld=0及复位恢复。

仲裁器与保存的R1 RTL对照129笔事务、三种MAX_BURST参数，逐拍核对全部输出；覆盖0..7及65535等长度、clamp、暂停恢复、地址回绕和同时请求。选句追加385组全宽边界及六槽验证。

R4候选另通过1,709,568次频谱输出对照及7个bank/爆点场景；该候选未选中，其记录保留在sim/timing_fft_r4_sim_result.json和sim/layer_fft64_r4_sim_result.json，不算作当前源码测试。

## 实际布局资源

|资源|修改前|本轮|变化|
|---|---:|---:|---:|
|Slice|9683/9800|9649/9800|-34|
|LUT|18253/19600|18173/19600|-80|
|FF|11342/19600|11330/19600|-12|
|BRAM9K|57/64|57/64|+0|
|BRAM32K|7/16|9/16|+2|
|DSP|27/29|25/29|-2|

MSlice 4824/4900、LSlice 4825/4900。以上均取最终物理报告，同一统计口径。

## 布线后时序

|路径组|原setup/ns|本轮setup/ns|原违例|本轮违例|本轮hold/ns|
|---|---:|---:|---:|---:|---:|
|video_clk -> video_clk|-6.136|+1.028|51|0|+0.024|
|clk -> clk|+0.415|+1.591|0|0|+0.032|
|sdr_clk -> sdr_clk|-5.826|-0.348|35|5|+0.032|
|sdr_clk -> video_clk|-1.036|+2.839|2|0|+0.244|
|video_clk -> sdr_clk|+1.305|+0.661|0|0|+0.244|
|hdmi_5x_clk -> hdmi_5x_clk|+6.075|+5.468|0|0|+0.239|
|sdr_clk -> sdr_clk_sft|-1.704|-1.547|32|32|+5.001|
|sdr_clk_sft -> sdr_clk|-5.565|-5.565|32|32|+9.430|

全局setup WNS -5.565ns、TNS -203.465ns；hold WNS +0.024ns，STA覆盖率 96.58%。
控制50MHz、像素25MHz、SDRAM100MHz、HDMI串行125MHz。PLL、管脚和SDC均未改，未新增false path或multicycle。

## 剩余负裕量路径

- sdr_clk -> sdr_clk：5端点，最差 -0.348ns；`u_core/u_arb/ctl_data_reg[23]_syn_4.clk` → `u_core/u_pick/f4_v_reg_syn_10.a[0]`。
- sdr_clk -> sdr_clk_sft：32端点，最差 -1.547ns；`u_core/u_phy/u2_ram/u1_init_ref/sdr_init_cnt_reg[1]_syn_3.clk` → `u_core/u_phy/sdram.dq[17]`。
- sdr_clk_sft -> sdr_clk：32端点，最差 -5.565ns；`u_core/u_phy/sdram.dq[0]` → `u_core/u_phy/sdram_syn_1.bpad`。

全部剩余普通setup端点（含同一寄存器不同内部端点）：

|Slack/ns|起点|终点|数据路径|
|---:|---|---|---|
|-0.348|u_core/u_arb/ctl_data_reg[23]_syn_4.clk|u_core/u_pick/f4_v_reg_syn_10.a[0]|9.996ns (cell 3.759ns (37%), net 6.237ns (63%))|
|-0.136|u_core/u_arb/ctl_data_reg[23]_syn_4.clk|u_core/u_pick/f4_v_reg_syn_10.d[1]|9.784ns (cell 3.547ns (36%), net 6.237ns (64%))|
|-0.029|u_core/u_arb/n_reg[1]_syn_4.clk|u_core/u_arb/settle_reg[3]_syn_7.a[0]|9.749ns (cell 4.519ns (46%), net 5.230ns (54%))|
|-0.029|u_core/u_arb/n_reg[1]_syn_4.clk|u_core/u_arb/settle_reg[3]_syn_7.a[1]|9.749ns (cell 4.519ns (46%), net 5.230ns (54%))|
|-0.013|u_core/g_aa_text$u_lyr/u_row/state_reg[1]_syn_30.clk|u_core/g_aa_text$u_lyr/u_row/time_lo_le_reg_syn_26.d[0]|9.733ns (cell 3.075ns (31%), net 6.658ns (69%))|

后续普通路径优化应先降低拥塞与关键控制网扇出，释放布局空间；本轮仅缩短局部算术链的三种尝试均引入了其他路径回退，不能继续盲目累加修改。

移相接口读取路径经过EG_PHY_SDRAM_2M_32硬宏及IO输入寄存器；写入路径经过加密sdr_wrrd及IO三态驱动。这部分不是OSD或文字普通组合逻辑，不能用同样的拆分方法直接改写。厂商参考也存在同类64端点只作对照，不构成时序豁免或稳定性证明。
保留板上已验证的100MHz/5ns相移；历史2.5ns曾出现整块读错，不能为报告好看盲扫相位。后续须核实厂商SIP时序模型和加密控制器的实际DQ采样/输出使能关系，或更换可审计控制器再做接口验证。
本轮没有硬件电压/温度长期验证，没有下载或上板。

## 产物和证据

- bit：output/timing_cleanup_20261030/audio_visual_timing_cleanup.bit
- SHA256：74eae6d6e8736d2304d594be93591817e9fdb4eee1eec561e312b5a96054e779
- SD卡字库、歌词和图片无需更新。
- 布线报告：prj/td_build/timingclean_r1_congestion_seed3_phy/final_timing.rpt
- 结构化证据：output/timing_cleanup_20261030/verification_and_build.json
- 修改前源码：output/timing_cleanup_20261030/source_before_r1/
- 修改前R2源码：output/timing_cleanup_20261030/source_before_r2/
- 修改前R3源码：output/timing_cleanup_20261030/source_before_r3/
- 修改前R4源码：output/timing_cleanup_20261030/source_before_r4/
- 所有旧bit和修复预算记录保留，本轮完成四次结构修改和四次物理实现，未盲扫种子或改相位。
- 各轮结果以以下最终物理报告对照为准：

|轮次|Setup端点|普通路径端点|TNS/ns|Slice|选择|
|---|---:|---:|---:|---:|---|
|R1|69|5|-203.465|9649|保留|
|R2|123|59|-233.139|9773|未选中|
|R3|93|29|-213.358|9640|未选中|
|R4|72|8|-200.360|9730|未选中|

综合/物理告警完整记录于结构化证据。保留厂商SDRAM未驱动脚、FFT初始化及既有放置告警；新增u_palette bea/beb告警：RTL均接常量0，BYTE_ENABLE=0且双口写使能为0，属于只读ROM不使用的字节写掩码；综合将未驱动项置0。独立色表和逐像素仿真均已核对。
