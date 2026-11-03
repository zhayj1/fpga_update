# TYP2 模块职责和实施顺序

真实顶层为rtl/top/skeleton_top.v，集成为rtl/top/skeleton_core.v。

1. scripts/prepare_full_typography.py：完整编码枚举、字形光栅化、TYP2卡包与仿真金样。
2. rtl/load/font_load.v → rtl/load/load_writeback.v：扩宽20bit字计数，保留原FIFO和握手。
3. rtl/app/asset_manager.v、rtl/top/skeleton_core.v：统一紧凑布局、容量和双LRC地址映射。
4. rtl/gfx/text_row_aa.v：TYP2取行，32bit串行解包，依赖现有SDRAM读端口。
5. rtl/gfx/layer_text_aa.v：仅默认基址更新；拥有原双bank行BRAM，截止/CDC不变。

全部由当前主代理实施，无新增厂商IP。原EG_LOGIC_BRAM、FIFO、SDRAM/PLL模型及工程配置复用。验收映射见doc/spec/full_font_behavior_spec.md。
