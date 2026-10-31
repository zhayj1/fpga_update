"""Build complete GB2312+printable ASCII TYP2 assets, independent of song text."""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import shutil
import struct
import zipfile
from functools import lru_cache

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/typography_full_20261030'
CARD=OUT/'sd_card'
spec=importlib.util.spec_from_file_location('typography_base',ROOT/'scripts/prepare_typography.py')
base=importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
p=base.preview
FONT_WORDS=964240
FONT_BASE=0x10BBB0
FONT_CAPACITY=0x200000-FONT_BASE
ALIASES={'\u30fb':'\u00b7','\u2015':'\u2014'}
SHIFTS={}
# Approved raster scale and baseline are fixed, independent of future songs.
RASTER={24:(190,148),20:(159,124)}

@lru_cache(maxsize=None)
def raster_font(size):
    return p.ImageFont.truetype(str(p.FONTS['hupo']),RASTER[size][0])


def repertoire():
    result=[]
    for a in range(0xA1,0xF8):
        for b in range(0xA1,0xFF):
            try: result.append(bytes((a,b)).decode('gb2312'))
            except UnicodeDecodeError: pass
    assert len(result)==7445
    result+=list(map(chr,range(32,127)))
    return result


@lru_cache(maxsize=None)
def mask(char,size):
    """Retain approved raster scale; move only overflowing ink, never crop it."""
    render=ALIASES.get(char,char)
    f=raster_font(size); ss=p.SS
    baseline=RASTER[size][1]
    bounds=f.getbbox(render,anchor='ls'); left=min(0,bounds[0])
    span=max(f.getlength(render),bounds[2])-left
    width=size if ord(char)>127 else max(4,math.ceil(span/ss))
    assert width<=size,(char,size,width)
    pad=6*ss
    im=p.Image.new('L',((width+12)*ss,(size+12)*ss))
    p.ImageDraw.Draw(im).text((pad+(width*ss-span)/2-left,pad+baseline),
                             render,font=f,anchor='ls',fill=255)
    bb=im.getbbox(); dx=dy=0
    if bb:
        assert bb[2]-bb[0]<=width*ss and bb[3]-bb[1]<=size*ss,(char,size,bb)
        dx=max(pad-bb[0],0)+min(pad+width*ss-bb[2],0)
        dy=max(pad-bb[1],0)+min(pad+size*ss-bb[3],0)
        assert pad<=bb[0]+dx and bb[2]+dx<=pad+width*ss
        assert pad<=bb[1]+dy and bb[3]+dy<=pad+size*ss
    if dx or dy: SHIFTS[f'{ord(char):04X}/{size}']=[dx,dy]
    im=im.crop((pad-dx,pad-dy,pad-dx+width*ss,pad-dy+size*ss))
    im=im.resize((width,size),p.Image.Resampling.LANCZOS)
    return im.point([min(range(0,256,17),key=lambda v:abs(v-x)) for x in range(256)])


def packed(mask,size):
    data=bytearray()
    for y in range(size):
        row=[mask.getpixel((x,y))//17 for x in range(mask.width)]+[0]*(size-mask.width)
        data.extend((row[x]<<4)|row[x+1] for x in range(0,size,2))
    return data


def storage_index(char):
    index=base.code_index(char)
    return index if index<846 else index-564


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def package():
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    meta=json.loads((ROOT/'card/manifest.json').read_text(encoding='utf-8'))
    meta['format']='audio_visual_upgrade_typography_card_v2'
    meta.pop('preview',None)
    meta['typography']={'format':'TYP2','font_bytes':3856960,'glyph_count':7540,
        'coverage_bits':4,'title_lyrics_px':24,'singer_px':20,'osd_px':16,
        'character_policy':'完整GB2312（7445字符）及ASCII 0x20..0x7E；换歌无需重建字库',
        'asc_loaded':False,'compatibility':'仅配TYP2完整字库固件，TYP1旧bit不可用'}
    for entry in meta['files']:
        path=CARD/entry['name']; entry.update(bytes=path.stat().st_size,sha256=digest(path))
    (CARD/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (CARD/'README_typography.txt').write_text(
        '完整字库TYP2配套素材；复制sd_card内文件到FAT32卡根目录，保持8.3文件名。\n'
        '必须配本次TYP2完整字库bit；旧TYP1及原1bit固件均不兼容。\n'
        'FONT.HZK固定3,856,960字节，含GB2312全部7445字符和95个可见ASCII。\n'
        '以后更换歌曲无需重新生成FONT.HZK；音频及歌词仍须转换为项目支持的WAV/LRC1格式。\n'
        '歌词仍受现有64行、488字记录等格式上限限制；GB2312之外的Unicode生僻字不在范围内。\n'
        '24px歌词/歌名、20px歌手、16级抗锯齿；OSD幼圆16px不变。\n'
        '随包音频仍为原45秒demo，全歌歌词表45行；不会凭字库延长音频。\n',encoding='utf-8')
    manifest['card_files']={f.name:digest(f) for f in sorted(CARD.iterdir()) if f.is_file()}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'card_typography_full.zip','w',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(CARD.iterdir()):
            if f.is_file(): z.write(f,'sd_card/'+f.name)


def main():
    OUT.mkdir(parents=True,exist_ok=True); CARD.mkdir(exist_ok=True)
    chars=repertoire()
    with p.TTFont(str(p.FONTS['hupo'])) as f:
        cmap=f.getBestCmap()
        assert all(ord(ALIASES.get(c,c)) in cmap for c in chars)
    words=[0]*FONT_WORDS; records={}; full_gold=[]; codes=[]; widths=[]
    for i,c in enumerate(chars):
        masks=[mask(c,size) for size in (24,20)]
        raw=b''.join(packed(m,size) for m,size in zip(masks,(24,20)))+bytes(8)
        assert len(raw)==496
        offset=8324+124*storage_index(c); w24,w20=[m.width for m in masks]
        words[4+base.code_index(c)]=0xA0000000|(w20<<23)|(w24<<18)|(offset//4)
        words[offset:offset+124]=struct.unpack('<124I',raw)
        records[c]={'index':base.code_index(c),'offset_words':offset,'width24':w24,'width20':w20}
        code=bytes((0,ord(c))) if ord(c)<128 else c.encode('gb2312')
        codes.append(int.from_bytes(code,'big')); widths.extend([w24,w20])
        for size,m in zip((24,20),masks):
            row=[m.getpixel((x,i%size))//17 for x in range(m.width)]+[0]*(32-m.width)
            full_gold.append(''.join(f'{v:x}' for v in row))
    assert len(words)==FONT_WORDS and len(words)<=FONT_CAPACITY
    words[:4]=[0x32505954,0x00141804,len(words),len(chars)]
    for f in (ROOT/'card').iterdir():
        if f.is_file(): shutil.copy2(f,CARD/f.name)
    (CARD/'FONT.HZK').write_bytes(struct.pack('<'+'I'*len(words),*words))
    (ROOT/'sim/typography_font.mem').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
    for name,values in [('full_font_codes',[f'{v:04x}' for v in codes]),
                        ('full_font_widths',[f'{v:02x}' for v in widths]),('full_font_rows',full_gold)]:
        (ROOT/f'sim/{name}.mem').write_text('\n'.join(values)+'\n',encoding='ascii')
    # Existing eight-character golden stays independent of binary packing.
    samples='追梦GALA%警'; fixture=bytearray((ROOT/'card/S01.LRC').read_bytes())
    for i,c in enumerate(samples):
        code=bytes((0,ord(c))) if ord(c)<128 else c.encode('gb2312')
        fixture[544+i*8:552+i*8]=code+b'\0\0'+struct.pack('<I',i*1000)
    (ROOT/'sim/typography_sample_lrc.mem').write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',fixture)),encoding='ascii')
    (ROOT/'sim/typography_sample_widths.mem').write_text(''.join(f'{mask(c,size).width:02x}\n' for size in (24,20) for c in samples),encoding='ascii')
    gold=[mask(c,size).getpixel((x,y))//17 for size in (24,20) for y in range(size) for c in samples for x in range(mask(c,size).width)]
    (ROOT/'sim/typography_row_golden.mem').write_text(''.join(f'{v:x}\n' for v in gold),encoding='ascii')
    manifest={'format':'TYP2','glyph_count':len(chars),'gb2312_count':7445,'ascii_count':95,
        'font_words':len(words),'font_bytes':len(words)*4,'glyph_bytes':496,
        'directory_words':8320,'chars':records,'aliases':ALIASES,'supersample_shifts':SHIFTS,
        'source_fonts':{k:{'path':str(v),'sha256':digest(v)} for k,v in p.FONTS.items()},
        'sample_text':samples,'sdram_font_base_word':FONT_BASE,'sdram_free_bytes':(FONT_CAPACITY-FONT_WORDS)*4,
        'source_font_pixels':{str(s):raster_font(s).size for s in (24,20)}}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Review examples include previously absent characters and both symbol aliases.
    im=p.Image.new('RGB',(640,360),'#070e13')
    examples=['华文琥珀 完整中文歌曲字库','作词作曲 编曲演唱 音乐与你同在',
              '我想要怒放的生命 世界如此美丽','龚龟龠 鳞麟麓 曦馨鑫 璀璨星河',
              '・ ― ，。！？《》“” （） ＡＢＣ', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
              'abcdefghijklmnopqrstuvwxyz 0123456789']
    for row,text in enumerate(examples):
        size=20 if row==6 else 24; x=16
        for c in text:
            m=mask(c,size); im.paste('#e8e4ff',(x,16+row*46),m); x+=m.width
    im.save(OUT/'font_coverage_preview.png')
    package()
    print(json.dumps({k:manifest[k] for k in ('glyph_count','font_bytes','sdram_free_bytes')},ensure_ascii=False))


if __name__=='__main__': main()
