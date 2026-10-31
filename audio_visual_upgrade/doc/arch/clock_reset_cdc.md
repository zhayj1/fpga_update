# TYP2 时钟复位

沿用现有 clk/rst_n（50MHz）、clk_sdr/rst_sdr_n（100MHz）、video_clk/rst_pix_n。没有新增时钟、复位、CDC或RAM。font_load配置和完成字段保持到后端done；load_writeback同步事件toggle并采样稳定字段。字节数据仍经原异步FIFO。text_row_aa全部在SDRAM域，layer_text_aa仍以原tag/toggle跨域发布完整行，双bank行RAM不变。FULL-03检验扩宽后的异步装载，FULL-04检验像素行发布和取消。
