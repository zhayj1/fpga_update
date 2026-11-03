# TYP2 连接矩阵

|生产者|信号|消费者|时钟/协议|
|---|---|---|---|
|asset_manager|task_base/task_capacity[19:0]|font_load|clk，任务期间保持|
|asset_manager|task_capacity[18:0]|bmp_load|clk，图片容量保证低19bit足够|
|font_load/BMP mux|cfg_words/finish_words[19:0]|load_writeback|clk→clk_sdr，稳定字段+原toggle邮箱；BMP零扩展|
|load_writeback|ld_*|sdram_arb|clk_sdr，原FWFT/ack/take/done|
|text_row_aa|px_*|原像素仲裁器|clk_sdr，一笔4word对齐读，跨块顺序第二笔|
|text_row_aa|wr_*|layer_text_aa行RAM|clk_sdr，完整行tag跨域后才可见|

卡包、RTL及TB使用相同已冻结规格，但checker独立解码字库/LRC以避免生成器同源漏检。
