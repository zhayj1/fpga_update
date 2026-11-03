from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
out=root/'output/capsule_ui_20261101_r1'
v=json.loads((out/'verification_and_build.json').read_text(encoding='utf-8'))
r=v['resources'];t=v['timing'];b=v['bitstream']
s=f'''# 圆点 / 圆头频谱 r1

2026-11-01。已完成修改、仿真、综合、布局布线与 bit 生成，待用户上板。

## 显示行为

- 保留 64 个频段，改为等宽、两端圆头的柱体；短柱自然成为小圆点，完全静音仍保留 64 个圆点。关闭频谱开关时整体隐藏。
- 沿用现有渐变色、颜色选择、尖峰效果、频谱开关与横向 6:5 显示补偿。
- 圆头半径约 3 屏幕像素，边缘采用 16 级覆盖率抗锯齿。
- 中间封面、顶部标题/歌手、底部单行高亮歌词、OSD、切歌、回弹、波纹与音频播放继续保留。
- 几何使用小 ROM、移位与共享加法；不新增 DSP 或 SDRAM 访问。抗锯齿混合与色彩处理分开一个像素时钟，文字、OSD、有效信号及行尾同步延迟，画面坐标不变。
- 字库格式与字形行宽条件在既有前一状态中预先判断，缩短歌词控制路径；字形像素、出错判定和处理周期保持。

## 交付

bit：`audio_capsule_ui_r1.bit`，{b['bytes']} 字节。

SHA256：`{b['sha256']}`

实际综合：`{v['selected_synthesis']}`；布局布线：`{v['selected_physical']}`。工具为 Tang Dynasty 6.2.168116。

`verification_and_build.json` 汇总实际结果；`sources_and_tests.zip` / `source_manifest.json` 保存并逐文件校验实际源码、ROM、测试和脚本。`baseline_sources.zip` 保存改动前源码，`changes_from_circular.patch` 提供已有文件差异；失败和中间构建保留原编号。

沿用当前已经修正的 TF 卡素材。本次未下载硬件、未写 TF 或 Flash。

## 资源与验证

|资源|前一圆形版本|本次圆头版本|
|---|---:|---:|
|Slice|9277/9800|{r['slices']}/9800|
|LUT|17467/19600|{r['lut']}/19600|
|寄存器|11195/19600|{r['reg']}/19600|
|BRAM9K|61/64|{r['bram']}/64|
|BRAM32K|16/16|{r['bram32k']}/16|
|DSP|28/29|{r['dsp']}/29|

频谱 8 项、画面合成 6 项、真实 SDRAM 歌词 5 项、原系统播放/切换 4 项通过；另有字库异常/恢复 3 项、全 7540 字符两种字号采样行与争用 2 项通过，板级顶层编译展开通过；交付源码与上述最终验证输入哈希一致。日志见 `simulation/`。

最终 STA：setup 违例 {t['setup_violations']}，WNS {t['setup_wns_ns']} ns；非移相路径 setup 违例 {t['non_shifted_setup_violations']}，hold 违例 {t['hold_violations']}，覆盖率 {t['coverage']}。原 SDRAM 移相接口欠项仍保留，不能称为全工程时序闭合。未修改时钟、约束或加入时序例外。

## 验证边界

扩展的 100 MHz / 180°、正式显示开关启动探针（在 r4、加入字库预判寄存器之前执行）未通过：小图夹具出现背景未知 RGB。改动前源码对照也在相应像素出现相同结果，尚未定位根因，不把它计作通过。最终流水级使输出比对照多延迟 40 ns；具体时刻见日志。原系统回归采用既有 150 MHz、小图与旧显示配置；新频谱、正式合成路径及文字分别验证，完整生产字库装载、PLL/TMDS 和新 bit 实际效果仍需上板确认。

用户已明确先前黑屏/固定音调由 TF 文件格式造成并已修改；这与上述仿真未决项分开记录，也不等于本次新 bit 已验收。

## 预览与复现

`silence_and_music_preview.png` 使用真实 RTL 仿真频谱像素叠加当前背景/封面：左静音、右测试电平。为外形预览，省略文字，非板测截图。

ROM：`python -B scripts/prepare_capsule_ui.py`。旧 `prepare_circular_ui.py` 已增加兼容保护，避免生成错误 ROM。

回归：`python -B scripts/verify_capsule_ui.py <spectrum|core|board|text_sdram|system> --suffix <新编号>`。

构建：`scripts/build.ps1 -Stage syn -Tag <新编号>`，再运行 `scripts/build.ps1 -Stage phy -Tag <新物理编号> -SynthesisTag <综合编号> -RouteEffort routability -Seed 5 -GenerateBitstream`。不要覆盖已有构建目录。
'''
(out/'README.md').write_text(s,encoding='utf-8')
p=root/'README.md';old=p.read_text(encoding='utf-8');marker='# 圆点 / 圆头频谱候选（2026-11-01）'
if not old.startswith(marker):p.write_text(marker+'\n\n已完成圆头等宽频谱、16 级抗锯齿和静音小圆点；原设置与功能保留，待上板。\n\n- bit：`output/capsule_ui_20261101_r1/audio_capsule_ui_r1.bit`\n- 说明、资源、验证限制：`output/capsule_ui_20261101_r1/README.md`\n\n以下为历史版本记录。\n\n'+old,encoding='utf-8')
p=root/'doc/workflow/state.json';state=json.loads(p.read_text(encoding='utf-8-sig'))
state['capsule_ui']={k:v[k] for k in ['date','status','scope','bitstream','selected_synthesis','selected_physical','board_validation','timing_clean']}
state['capsule_ui'].update(evidence='output/capsule_ui_20261101_r1/verification_and_build.json',active_writer='implementation complete; awaiting user board feedback',startup_probe='baseline-equivalent unknown background RGB, see report')
state['circular_ui']['user_latest_feedback']='User attributes earlier black screen/fixed tone to TF file format and has corrected it; subsequent request concerns visible spectrum shape.'
p.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Wrote delivery README and updated local workflow state; no board acceptance implied.')
