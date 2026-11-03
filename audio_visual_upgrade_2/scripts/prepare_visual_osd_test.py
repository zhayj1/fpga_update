"""Independent text/layout reference for extended OSD pages 4, 5 and 6."""
from pathlib import Path
import importlib.util,json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'music_screen/.pylibs'))
from PIL import Image
preview=ROOT/'output/typography_preview_20261029/render.py'
if not preview.exists(): preview=ROOT.parent/'audio_visual_upgrade/output/typography_preview_20261029/render.py'
spec=importlib.util.spec_from_file_location('preview',preview)
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
meta=json.loads((ROOT/'output/visual_controls_aa_20261031/generated.json').read_text(encoding='utf8'))
old=[int(v,16) for v in (ROOT/'sim/typography_osd_glyphs.mem').read_text().split()]
glyphs={c:[old[g*256+(y*16+x)] for y in range(16) for x in range(16)]
        for c,g in meta['glyphs'].items() if g<44}
for c,g in meta['glyphs'].items():
    if g>=64: glyphs[c]=[a//17 for a in p.text_mask(c,'youyuan',16,16).getdata()]
for c,g in zip('0123456789%/<>',range(30,44)):
    glyphs[c]=old[g*256:(g+1)*256]
colors=meta['colors']; allpixels=[]
from prepare_transition_assets import GLYPHS,glyph_mask
for c in GLYPHS: glyphs[c]=list(glyph_mask(c).getdata())
OUT=ROOT/'output/transitions_20261102_r1'
OUT.mkdir(exist_ok=True,parents=True)
for frame in range(40):
    selected=frame if frame<6 else frame-6 if frame<8 else (frame-8)%2
    page=3 if frame<6 else 4 if frame<8 else 5
    im=Image.new('RGB',(200,224),(7,14,19))
    def put(x,y,c): im.putpixel((x-440,y-256),((c>>16)&255,(c>>8)&255,c&255))
    def rect(x,y,w,h,c):
        for yy in range(y,y+h):
            for xx in range(x,x+w): put(xx,yy,c)
    def text(s,x,y,fg=0xe7f0f0,ascii=False):
        for c in s:
            mask=glyphs[c]
            for yy in range(16):
                for xx in range(8 if ascii else 16):
                    a=mask[yy*16+xx];bg=im.getpixel((x+xx-440,y+yy-256))
                    out=tuple((b*(15-a)+((fg>>sh)&255)*a+7)//15 for b,sh in zip(bg,(16,8,0)))
                    im.putpixel((x+xx-440,y+yy-256),out)
            x+=8 if ascii else 16
    rect(440,256,200,1,0x48636a);rect(440,479,200,1,0x48636a)
    rect(440,256,1,224,0x48636a);rect(639,256,1,224,0x48636a)
    rect(452,295,176,1,0x48636a)
    text(('颜色设置','效果设置','转场设置')[page-3],452,268)
    text('<',572,268,0x49ded4,True);text(f'{page+1}/6',588,268,0xffb347,True);text('>',620,268,0x49ded4,True)
    if page==3:
        text(('频谱柱','歌词已唱','歌词其余','歌名','歌手','波纹')[selected],452,306)
        index=(0,13,27,45,69,70)[selected]
        for k in range(70):
            x=460+k%10*16;y=330+k//10*16
            if k==index:rect(x+1,y+1,14,14,0xffffff)
            rect(x+2,y+2,12,12,colors[k])
        text('默认',452,452)
        if index==70:rect(504,452,32,16,0xffffff)
        rect(506,454,28,12,colors[70+selected])
    elif page==4:
        for k,s in enumerate(('扩散圆环','封面回弹','柱顶尖峰','频谱柱','色彩联动')):
            y=306+k*32
            if k==selected:rect(444,y+1,3,14,0x49ded4)
            text(s,452,y,0xe7f0f0 if k==selected else 0xb6c6c9)
            rect(604,y,16,16,0x48636a)
            rect(607,y+3,10,10,0x49ded4 if frame==7 else 0x070e13)
    else:
        effect=(frame-8)//8;speed=((frame-8)//2)%4
        values=(('淡入淡出','擦除','溶解','百叶窗')[effect],('快速','标准','慢速','很慢')[speed])
        for k,label in enumerate(('转场效果','转场速度')):
            y=306+32*k
            if k==selected: rect(444,y+1,3,14,0x49ded4)
            text(label,452,y,0xe7f0f0 if k==selected else 0xb6c6c9)
            text(values[k],548,y,0x49ded4 if k==selected else 0xb6c6c9)
    im.save(OUT/f'osd_expected_{frame}.png')
    allpixels.extend((r<<16)|(g<<8)|b for r,g,b in im.getdata())
(ROOT/'sim/visual_osd_golden.mem').write_text(''.join(f'{c:06x}\n' for c in allpixels))
config=json.loads((ROOT/'sim/modelsim_typography_osd.json').read_text())
config['dut_top']='work.tb_visual_osd';config['tb_top']='work.tb_visual_osd'
for lib in config['libraries']:
    for s in lib['sources']:
        if s['path']=='tb/tb_osd_typography.v':s['path']='tb/tb_visual_osd.v'
config.setdefault('data_files',[]).append('sim/visual_osd_golden.mem')
(ROOT/'sim/modelsim_visual_osd.json').write_text(json.dumps(config,indent=2)+'\n')
