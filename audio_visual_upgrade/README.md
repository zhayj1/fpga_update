# Audio Visual Upgrade

当前上板版本：封面轮廓抗锯齿、颜色设置和效果开关。用户已于 2026-10-31 反馈上板正常。

## 烧录与 SD 卡

- bit：`output/visual_controls_aa_20261031/audio_visual_controls_aa.bit`，SHA256 `7ebe67672b356b45dcefed25f7134388f49b9e23f77f1bfde865635eb3d6ffa1`。
- SD 卡使用 `card/FONT.HZK` 完整 TYP2 字库（3,856,960 字节）以及 `card/S01CV1.BMP`、`S01CV2.BMP`、`S01CV3.BMP` 新封面。`card/manifest.json` 列出全部卡文件及哈希。
- 仅需更新现有 SD 卡的三张 S01 封面时，可使用 `output/visual_controls_aa_20261031/S01_cover_aa.zip`。S02 封面仍是旧示例，后续素材按 S01 的 240×240 画布和轮廓标准制作。

## OSD 操作

- KEY4 长按约 0.6 秒显示或隐藏 OSD；显示时短按切换项目，末项目后翻页。隐藏时短按仍切换图片。
- KEY2/KEY3 对当前设置减/加；效果页分别为关闭/开启。
- 原三页后新增颜色页和效果页。颜色页可调频谱白色到所选色的渐变终点、歌词已唱色、歌词其余色、歌名、歌手和波纹；效果页可独立控制圆环、封面回弹、柱顶尖峰、频谱柱、色彩联动。
- 设置在切歌后保留，复位后恢复默认。

## 验证

55 个自检场景及板顶层编译通过；Slice 9536/9800、LUT 17753/19600。物理报告仍有 SDRAM 移相接口的 64 个 Setup 违例，其他路径组和 Hold 无违例。上板正常是用户实测结果，不表示静态时序已闭合。详见 `doc/compile/visual_controls_aa_report.md` 和 `output/visual_controls_aa_20261031/verification_and_build.json`。
