完整GB2312字库TYP2上板文件

1. 烧录本目录 audio_visual_full_font.bit。
2. 将 sd_card/FONT.HZK 覆盖到SD卡根目录，必须为3,856,960字节；或使用card_typography_full.zip整包素材。
3. 重新上电，等待SD卡装载完成。旧TYP1 bit不能配此字库。

以后换歌：保留FONT.HZK不动，准备项目支持的WAV与LRC1文件即可；换歌无需生成字库或重新综合。
覆盖GB2312全部7445字符及95个可打印ASCII，共7540字；非GB2312的Unicode生僻字不包含。
24px歌词/歌名、20px歌手、16级抗锯齿保持。OSD幼圆16px不变。
现有LRC1行数、字数及单行显示长度限制仍适用。随包音频仍是原45秒demo。

验证：34个功能场景、4项独立素材检查、板级展开通过；综合/布局布线/bitgen完成。
实际资源：Slice 9721/9800，LUT 18125/19600，BRAM9K 55/64，BRAM32K 7/16，DSP 27/29。
setup时序尚未收敛：WNS -5.565ns，185个违例端点；hold违例0。此新bit尚未上板验证。

bit SHA256: 4BE042262FAD8A3F725DBCEBDACDCF2ABC33ECE789CD9CED601BE105CB08C9B0
FONT SHA256: 6b399399d46dee95717d1fdefefa5cbcc97839c56ecbfd31d092dc77cfa2d3c2
完整报告：../../doc/compile/full_font_report.md
