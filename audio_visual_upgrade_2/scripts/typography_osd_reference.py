"""Independent pixel oracle from approved fonts and panel geometry (no RTL reads)."""
from pathlib import Path
import importlib.util
import json
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('preview',root/'output/typography_preview_20261029/render.py')
p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
from PIL import Image,ImageDraw
out=root/'output/typography_implementation_20261029'

def text(im,value,x,y,color):
    mask=p.text_mask(value,'youyuan',16,16)
    im.paste(Image.new('RGB',mask.size,color),(x,y),mask)

def reference(page,extreme):
    im=Image.new('RGB',(640,256),'#070e13'); d=ImageDraw.Draw(im)
    d.rectangle((424,16,623,239),outline='#48636a')
    d.line((436,55,611,55),fill='#48636a')
    text(im,['攻击检测','实时声学','音量色彩'][page],436,28,'#e7f0f0')
    for value,x,color in [('<',556,'#49ded4'),(str(page+1)+'/3',572,'#ffb347'),('>',604,'#49ded4')]: text(im,value,x,28,color)
    if page==0:
        labels=['灵敏','触发']; values=['40' if extreme else '16','3']; bars=[176 if extreme else 64,None]
    elif page==1:
        labels=['频谱强度','相对音量','饱和度','对比度']
        values=['99%','99%','260%','170%'] if extreme else ['62%','46%','145%','120%']
        bars=[175]*4 if extreme else [110,82,82,82]
    else:
        labels=['音量','饱和基准','饱和上限','对比基准','对比上限']
        values=['100%','150%','260%','130%','170%'] if extreme else ['0%','60%','100%','80%','100%']
        bars=[176]*5 if extreme else [0]*5
    for i,(label,value,bar) in enumerate(zip(labels,values,bars)):
        y=66+32*i
        color='#b6c6c9' if page==2 and i!=2 else '#e7f0f0'
        text(im,label,436,y,color)
        text(im,value,612-8*len(value),y,'#ffb347' if page==0 and i==1 else '#49ded4')
        if page==2 and i==2: d.rectangle((428,y+1,430,y+14),fill='#49ded4')
        if bar is not None:
            d.rectangle((436,y+22,611,y+24),fill='#405258')
            if bar: d.rectangle((436,y+22,435+bar,y+24),fill='#49ded4')
    if page==0:
        d.line((435,129,612,129),fill='#24303b'); d.line((435,196,612,196),fill='#24303b')
        d.rectangle((436,130,611,195),fill='#070b10')
        d.line((436,179,611,179),fill='#35d0c4')
        for x in range(436,612):
            if x%8<4: d.point((x,187),fill='#b8893c')
            if ((x-436)*320//176)<3: d.line((x,130,x,195),fill='#ffb347')
    words=[]
    for y in range(256):
        for x in range(640):
            rgb=im.getpixel((x,y)); valid=424<=x<624 and 16<=y<240
            words.append((int(valid)<<24) | rgb[0]<<16 | rgb[1]<<8 | rgb[2])
    return im,words

def main():
    all_words=[]
    for extreme in (False,True):
        for page in range(3):
            im,words=reference(page,extreme); all_words+=words
            im.save(out/f'osd_reference_{int(extreme)}_{page}.png')
    (root/'sim/typography_osd_golden.mem').write_text(''.join(f'{x:07x}\n' for x in all_words),encoding='ascii')
    # Also verify every ROM pixel against the approved font, independent of packing.
    mapping=json.loads((out/'manifest.json').read_text(encoding='utf-8'))['osd_mapping']
    values=[]
    for glyph in range(44):
        char=mapping.get(str(glyph)) if glyph<30 else '0123456789%/<>'[glyph-30]
        mask=p.text_mask(char,'youyuan',16,16) if char else None
        for y in range(16):
            for x in range(16): values.append(mask.getpixel((x,y))//17 if mask and x<mask.width else 0)
    (root/'sim/typography_osd_glyphs.mem').write_text(''.join(f'{v:x}\n' for v in values),encoding='ascii')
    print('Generated six complete OSD pixel references and 44 ROM glyph references')
if __name__=='__main__': main()
