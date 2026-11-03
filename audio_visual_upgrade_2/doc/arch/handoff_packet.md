# 完整字库实施契约

需求、字库格式、SDRAM布局、握手及FULL-01..05验收已冻结于doc/spec/full_font_behavior_spec.md。外部端口与CDC沿用现有模块，仅装载word计数扩至20bit；接口见interface_contract.yaml、连接见connection_matrix.md。无未确定硬件事实，继续生成字库、RTL、TB并按用户授权综合布局布线出bit。

rtl/top_skeleton.v只保留接口参考，不加入编译清单。真实顶层是skeleton_top。
