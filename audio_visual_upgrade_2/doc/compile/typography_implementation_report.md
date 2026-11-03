# 字体升级版：综合、布局布线与 bit

日期：2026-10-30。工具：Tang Dynasty 6.2.168116；器件：EG4S20BG256；顶层：`skeleton_top`。

历史TYP1字体版已经完成综合、布局布线、STA 报告和 bitgen。最终候选为 `typography_dspall1_seed3_phy`，布局布线和 DRC 通过，bit 已生成。用户已上板：换入配套字库后字幕可见，但第8行之后缺字；现已确认旧生成器只扫描前8行。完整字库TYP2进展见 `full_font_report.md`。

## 为跨过 Slice 门槛做的资源优化

初始字体版在布局阶段需要 5051/4900 MSlice，不能实现。先把精确混色从两组独立乘加改为等价的颜色差值形式，完整 256×256×16 组合自检通过；随后把 OSD 和歌词两处混色的 8×4 位乘法映射到 DSP。字体、16 级覆盖率、四舍五入规则和显示时序均未降低。

最终实现资源：

| 资源 | 使用量 | 器件总量 |
| --- | ---: | ---: |
| Slice | 9697 | 9800 |
| LUT | 18048 | 19600 |
| 寄存器 | 11228 | 19600 |
| BRAM9K | 55 | 64 |
| BRAM32K | 7 | 16 |
| DSP | 27 | 29 |
| PLL | 2 | 4 |
| GCLK | 4 | 16 |

布局门槛已满足，最终打包为 4849/4900 MSlice；物理 Slice 使用率 98.95%，只剩 103 个，后续改动余量很小。

## 时序结果

全局 setup 尚未收敛：WNS `-5.565 ns`、TNS `-474.167 ns`、282 个 setup 违例端点。hold WNS `+0.030 ns`，hold 违例 0 个；STA coverage 96.57%。主要 setup 违例为 `video_clk -> video_clk`（-4.694 ns，49 个）、`clk -> clk`（-2.039 ns，68 个）、`sdr_clk -> sdr_clk`（-2.141 ns，101 个），以及既有相移 SDRAM 路径 `sdr_clk_sft -> sdr_clk`（-5.565 ns，32 个）。未通过时序不能据此承诺最高频率或直接量产。

布线 DRC 检查通过，日志中保留两条既有 SDRAM 初始位置被工具移动的 PHY-7002 critical-warning；没有 bitgen 错误。

## 产物

- bit：`prj/td_build/typography_dspall1_seed3_phy/skeleton.bit`
- 字体卡包：`output/typography_implementation_20261029/card_typography.zip`
- bit SHA256：`F6E80A3C53B325EC3CF2954D8A482C1C1870C793508B65837286AC63778CC804`
- bit 大小：654077 字节
- 综合报告：`prj/td_build/typography_dspall1_syn/gate.qor`、`skeleton_gate.area`
- 布线报告：`prj/td_build/typography_dspall1_seed3_phy/route.qor`、`skeleton_phy.area`、`final_timing.rpt`
- 结构化记录：`output/typography_physical_20261030/physical_result.json`

该 bit 只能配套本轮 TYP1 字库卡包使用；旧 bit 与新字库不能混用。此版本已由用户上板验证；旧卡包覆盖不全，TYP2必须配新bit，不能混用。
