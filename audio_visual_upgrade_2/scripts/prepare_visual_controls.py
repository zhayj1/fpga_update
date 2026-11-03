"""Build deterministic coverage/colour/font ROMs and S01 edge-colour assets."""
from pathlib import Path
import math, json, sys, importlib.util, hashlib, zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'music_screen/.pylibs'))
from PIL import Image
OUT=ROOT/'output/visual_controls_aa_20261031'
SIZES=(240,250,256,260)
DEFAULTS=(0xD97A26,0xFFE8AA,0xE8E4FF,0xFFFFFF,0xBCC4D2,0x5EE8ED)
BASE=(0xFFFFFF,0x000000,0xE7E6E6,0x44546A,0x4472C4,0xED7D31,0xA5A5A5,0xFFC000,0x5B9BD5,0x70AD47)
STANDARD=(0xC00000,0xFF0000,0xFFC000,0xFFFF00,0x92D050,0x00B050,0x00B0F0,0x0070C0,0x002060,0x7030A0)

def palette():
    values=list(BASE)
    for row in range(5):
        for col,rgb in enumerate(BASE):
            # Familiar office theme palette: light shades above dark shades.
            amount=((.05,.15,.25,.35,.5)[row] if col==0 else
                    (-.5,-.35,-.25,-.15,-.05)[row] if col==1 else
                    (-.8,-.6,-.4,.25,.5)[row])
            def shade(c):
                return round(c*(1-amount)) if amount>=0 else round(c+(255-c)*-amount)
            values.append(sum(shade((rgb>>s)&255)<<s for s in (16,8,0)))
    return values+list(STANDARD)

def coverage(size,x,y):
    # 16x16 subpixel point coverage of the exact analytic ellipse.
    rx=size*5/12; ry=size/2; count=0
    for sy in range(16):
        dy=(y+(sy+.5)/16-ry)/ry
        half=rx*math.sqrt(max(0,1-dy*dy))
        left=ry-half; right=ry+half
        for sx in range(16):
            px=x+(sx+.5)/16
            count+=left<=px<right
    return (count*15+128)//256

def make_cover():
    rows=[]; gold=[]; max_partial=0
    for size in SIZES:
        allrows=[]
        for y in range(size//2):
            row=[coverage(size,x,y) for x in range(size//2)]
            start=next(x for x,a in enumerate(row) if a)
            end=next(x for x,a in enumerate(row) if a==15)
            partial=row[start:end]
            max_partial=max(max_partial,len(partial))
            assert len(partial)<=14,(size,y,start,end)
            word=start
            for i,a in enumerate(partial+[15]*(14-len(partial))): word|=a<<(8+4*i)
            rows.append(word)
            allrows.append(row+row[::-1])
        allrows+=allrows[::-1]
        gold.extend(a for row in allrows for a in row)
    # One 32K block: both ports fetch the two halves of a 64-bit row.
    rows += [0]*(512-len(rows))
    (ROOT/'rtl/gfx/cover_coverage.dath').write_text(''.join(f'{(w>>(32*lane))&0xffffffff:08x}\n' for w in rows for lane in range(2)))
    (ROOT/'sim/cover_coverage_golden.mem').write_text(''.join(f'{a:x}\n' for a in gold))
    card=OUT/'sd_card'; card.mkdir(parents=True,exist_ok=True)
    manifest=[]
    for path in sorted((ROOT/'card').glob('S01CV*.BMP')):
        im=Image.open(path).convert('RGB'); assert im.size==(240,240)
        original=im.copy()
        # Expand RGB locally by four pixels. Coverage is applied in hardware,
        # including scaled boundary samples; no purple enters a mixed pixel.
        for y in range(240):
            for x in range(240):
                if original.getpixel((x,y))!=(255,0,255): continue
                near=[(dx*dx+dy*dy,x+dx,y+dy) for dy in range(-4,5) for dx in range(-4,5)
                      if 0<=x+dx<240 and 0<=y+dy<240 and original.getpixel((x+dx,y+dy))!=(255,0,255)]
                if near:
                    _,xx,yy=min(near); im.putpixel((x,y),original.getpixel((xx,yy)))
        im.save(card/path.name)
        for size in SIZES:
            # Match fetch_line_scene P_RUN/P_REPEAT: emit the source pixel,
            # then repeat it when the accumulated enlargement reaches 240.
            source_x=[]; phase=0
            for sx in range(240):
                source_x.append(sx); phase+=size-240
                if phase>=240:
                    source_x.append(sx); phase-=240
            assert len(source_x)==size
            for y in range(size):
                for x in range(size):
                    if gold[sum(s*s for s in SIZES[:SIZES.index(size)])+y*size+x]:
                        assert im.getpixel((source_x[x],y*240//size))!=(255,0,255),(path,size,x,y)
        manifest.append({'file':path.name,'sha256':hashlib.sha256((card/path.name).read_bytes()).hexdigest()})
    return {'sizes':SIZES,'max_partial':max_partial,'assets':manifest}

def make_fonts():
    spec=importlib.util.spec_from_file_location('preview',ROOT/'output/typography_preview_20261029/render.py')
    p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
    old=json.loads((ROOT/'output/typography_implementation_20261029/manifest.json').read_text(encoding='utf-8'))['osd_mapping']
    mapping={v:int(k) for k,v in old.items()}
    needed='颜色设置频谱柱歌词已唱其余歌名歌手波纹效果扩散圆环封面回弹柱顶尖峰色彩联动默认'
    extra=[]
    for c in needed:
        if c not in mapping:
            mapping[c]=64+len(extra); extra.append(c)
    assert len(extra)<=32
    words=[0]*1024
    for c in extra:
        mask=p.text_mask(c,'youyuan',16,16)
        for y in range(16):
            bits=0
            for x in range(16): bits=(bits<<4)|(mask.getpixel((x,y))//17)
            addr=(mapping[c]-64)*32+y*2
            words[addr]=bits>>32;words[addr+1]=bits&0xffffffff
    (ROOT/'rtl/gfx/osd_youyuan_extra.dath').write_text(''.join(f'{v:08x}\n' for v in words))
    return mapping

def make_pixel_font():
    words=[]
    def read(name): return [int(v,16) for v in (ROOT/('rtl/gfx/'+name+'.dath')).read_text().split()]
    ch,asc,extra=map(read,('osd_youyuan_ch','osd_youyuan_ascii','osd_youyuan_extra'))
    for g in range(128):
        for y in range(16):
            if g==0: bits=0
            elif g<30: bits=(ch[(g&31)*32+y*2]<<32)|ch[(g&31)*32+y*2+1]
            elif g<64: bits=asc[((g-14)&15)*16+y]<<32
            else: bits=(extra[(g&31)*32+y*2]<<32)|extra[(g&31)*32+y*2+1]
            words.extend((bits>>((15-x)*4))&15 for x in range(16))
    (ROOT/'rtl/gfx/osd_youyuan_pixel.dath').write_text(''.join(f'{(words[i]<<4)|words[i+1]:02x}\n' for i in range(0,len(words),2)))
    # IDs 96..127 used to alias the 32-slot row ROM. Fill the new pixel-only
    # glyphs explicitly after packing; do not enlarge the legacy row ROM.
    from prepare_transition_assets import install_font
    install_font()

def make_numeric_tables():
    bcd=[];bar=[]
    for v in range(512):
        h=2 if v>=200 else 1 if v>=100 else 0
        r=v-h*100;t=min(9,r//10)
        bcd.append((h<<8)|(t<<4)|((r-t*10)&15))
    for k in range(8):
        for v in range(512):
            offset=(2,0,0,60,100,80,100,0)[k]
            factor=(1186,176,451,501,282,902,644,0)[k]
            bar.append(min(176,(((v-offset)&511)*factor)>>8))
    (ROOT/'rtl/gfx/osd_bcd.dath').write_text(''.join(f'{v:03x}\n' for v in bcd))
    (ROOT/'rtl/gfx/osd_bar.dath').write_text(''.join(f'{v:02x}\n' for v in bar))

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    colors=palette(); assert len(colors)==70
    # Default entries 70..75 are independent of the theme swatches.
    colors+=list(DEFAULTS); colors+=[0]*(256-len(colors))
    (ROOT/'rtl/gfx/visual_palette.dath').write_text(''.join(f'{v:08x}\n' for v in colors))
    metadata=make_cover();metadata['glyphs']=make_fonts(); make_pixel_font(); make_numeric_tables(); metadata['colors']=colors[:76]
    (OUT/'generated.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in metadata.items() if k!='colors'},ensure_ascii=False))

if __name__=='__main__': main()
