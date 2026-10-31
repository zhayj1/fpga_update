# 左封面、右侧五行歌词布局

2026-10-30。用户已同意实施；当前完整 TYP2 版本已由用户确认上板正常。

- HDMI 640×480、字体、字号、16级覆盖率及完整GB2312字库保持。封面中心(160,165)，原尺寸和缩放规则保持；两路封面和节拍圆环共同移动。
- 标题/歌手窗口 x=336..623，y=45/77。歌词 x=296..631，宽336px=14个24px中文；短句居中，超宽句按现有跑马灯节拍水平滚动，当前19字的行格式上限保持。
- 五行顶部118/154/190/226/261，第三行中心y=202。上下各两句；不足留空。下一句前0.3s平滑上移一行（36px，末段35px），下一句进入第三行。底部预取第六条描述符，确保过渡时连续；窗口外裁剪。
- 当前句保留逐字变色；上下文保留原非当前句颜色。每句水平相位跟随其fc/cnt身份，纵向换行不重置同一句；新进入窗口的句子从头开始，切歌/跳转重置。
- clk_sdr100MHz、clk_pix25MHz。时间轴每帧仍一次136word突发；在流式扫描中保留前两句和后三句，不缓存全表。描述符done后保持到下一次提交；像素域toggle捕获，行请求保持到ack。
- 共用一个text_row_aa和2048×8双bank BRAM。每个扫描行只渲染一个文本行。迟到取消、tag/帧/行校验、DE期间元信息冻结保持。无全帧缓存，无新增字库槽。
- 对比基线 Slice9721/9800、BRAM9K55/64、BRAM32K7/16、DSP27/29；先缩窄有严格范围的文字描述符，避免五份渲染器。最终资源以真实工具结果为准。
- 资源约束实现：歌词描述符first/count为9/5位，先校验完整16位输入的范围再使用；取字引擎索引与看门狗按488记录、MAX_CH和超时阈值定宽。FIVE_LINES=1的纵坐标为10位，约束为640×480/525总行，消隐区下溢值在可见区域外；FIVE_LINES=0保留原16位坐标。六句横滚相位共用加法/比较电路，六个像素时钟完成一次更新。
- 封面左移后，远端像素距离平方需要24位（原中心260时23位足够）；圆环距离递推保留完整范围，防止右边出现溢出伪环。
- 当前行距36/36/36/35px，字格仍高24px；共用相对纵坐标和槽基址减法得到字形行，窗口裁剪到118..284。原32px模式保留位选择优化。
- 水平寻址和几何有效位共用一套源坐标及环回运算；几何有效位与同步行RAM像素同拍寄存，避免为当前像素再复制一次减法/比较电路。像素对齐、裁剪边界和横滚周期保持。
- 六句横滚相位/行宽采用循环起点映射；正常切句只推进起点并清空新尾槽，避免114位寄存器整体搬移的多路选择。跳转/换歌清空；同拍切句优先于宽度提交与相位更新。逐像素回归增加连续8句跨循环起点环回场景。

验收：LAY-01选行(0/1/2/中间/末尾/64行/重复时间戳/换歌/坏表/截短/复位)；LAY-02五行逐像素与短句居中；LAY-03十四/十五/十九字、水平环回/停留/随句迁移；LAY-04纵向0/18/36px与第六行进入；LAY-05迟到/取消/恢复和bank保护；LAY-06封面与圆环同中心、核心叠层/OSD/字库地址回归；LAY-07真实SDRAM争用截止。测试使用独立槽表与像素参考，不以内部状态作为golden。

本变更不修改已交付完整字库及原bit。功能仿真、综合、布局布线、时序、上板状态分别记录，不以bit生成代替时序通过。

2026-10-30布局微调：歌名、歌手和歌词整体下移29px，保留相对间距。歌名窗口上沿y=45，与中心(160,165)、240×240封面的静态上沿一致；文字不跟随节拍缩放跳动。仅调整编译期纵坐标参数。

## 上板文字异常修复契约（2026-10-30）

- 取字地址由512×18双端口ROM分别查询高、低字节贡献，在DIRECTORY/ADDRESS两拍完成相加；18位模加必须与完整FONT.HZK的7540个目录项一致。ROM实际占用以TD物理报告为准。
- 每个字形行只在WRITE装入首个32位字，之后每8个nibble直接装入下一字；跳过小字号奇数行的前4个nibble不改变计数。像素剩余计数到1时结束字符，最后一个像素后的预装无可观察作用。
- 歌词时间戳按高/中/低字节分别比较并寄存，再于DIRECTORY合成逐字变色标记；结果必须与无符号24位时间戳<=played一致。
- 行截止以SDR域捕获后的now_y/now_frame判断；较此前直连line mailbox路径晚一个100MHz时钟（10ns），取消仍在HS消隐期完成，DE内不得写正在读的bank。描述符变更/连续切句判断先在像素域寄存，再由同步toggle提交；横滚相位迁移语义保持。
- TYPOGRAPHY=1的颜色处理输出增加一拍，再做原有精确/15混色；文字RGB/alpha、OSD/诊断覆盖、DE、VS、行尾标记同步增加一拍。可见像素位置、16级覆盖率、色彩运算结果保持；TYPOGRAPHY=0路径延迟保持。
- 新增FIX-01：真实SDRAM控制器及器件模型、四个图像客户端争用时，完整640×480帧逐像素比较文字颜色/alpha，包括标题、歌手和五行歌词。
- 新增FIX-02：争用相对HS偏移0/40/120/3个SDR时钟，验证0/16/32px纵移及切句横滚四帧，无迟到取消；保留原快速模型的故意迟到/取消/恢复场景。
- 核心叠层测试逐像素核对新增流水线后的背景、频谱、文字和OSD；覆盖16级alpha与淡入淡出端点，不以DE延后代替RGB/控制信号对齐。
- 新增FIX-03：在HDMI输入AX输出逐拍比较有效信号、RGB与独立行计数；核对256行共163840像素及每行第640像素的last，防止新流水线导致行尾偏移。

### Third structural repair contract

- Glyph validity subconditions are captured in DIRECTORY and consumed in ADDRESS without adding row cycles. Title/singer descriptor-change resets are registered one SDR clock later, within blanking.
- OSD normalizer has a registered full-precision product. Drawing coordinates, coverage and hit flags advance with it; the existing outer OSD alignment register moves inside, so overall core latency is unchanged. FIX-04 checks varying 320-sample scope history independently at all scope pixels.
- Writeback prepares signed row steps and offset operands before a shared adder, then captures burst address before FIFO-ready arbitration. Remaining/row counts update independently; a freshness flag prevents using stale accounting after CFG/END/ACCOUNT. No burst data, address order or final exact-granule semantics change.

## 歌词行距微调（2026-10-30）

第一行y=118不动；四段行距为36/36/36/35px，第五行y=261..284，与封面y=45..284的静态下沿一致。歌名/歌手y=45/77保持。滚动相位0..36，第五槽在首个相位停留1px后累计上移35px；其他槽累计上移36px，末相位与切句后的槽位置完全相接。预取第六行y=297，滚动末端落至261。字体尺寸、抗锯齿、横滚和0.3s时长保持，不裁掉末行字形。

验收复用LAY-02/03/04/05、FIX-01/02、核心及板级编译；快速帧增加相位1和35以检查短1px间隔的首尾边界。此为独立布局需求，既有文字花屏结构修复预算不变。
