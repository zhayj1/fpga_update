


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				1000000000/100000000
// ★★ 2026-10-03：随 `pll_sdr.v` 一起把 SDRAM 时钟 125MHz → **100MHz** ✓
//   （APUG011 §2.5 要求：改频必须同步改这里 ✗ —— 自刷新间隔由它推算 ✓）
//   注意 `SELF_REFRESH_INTERVAL` 换算成时间 = 64e6/2**11 ns = **31.25µs** ✓，**与频率无关** ✓
//   ⇒ 降频不改变刷新时间 ⇒ 只治"读采样余量" ✗，治不了"保持/刷新" ✗。
`define   SELF_REFRESH_INTERVAL			64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)

