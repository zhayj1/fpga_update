"""Typography helpers and entry point for the complete TYP2 font generator."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import struct
import sys
import zipfile
import argparse

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/typography_implementation_20261029'
CARD=OUT/'sd_card'
spec=importlib.util.spec_from_file_location('approved_preview', ROOT/'output/typography_preview_20261029/render.py')
preview=importlib.util.module_from_spec(spec); spec.loader.exec_module(preview)


def code_index(char):
    if 32 <= ord(char) <= 127: return 8178+ord(char)-32
    q,w=char.encode('gb2312')
    if not (161<=q<=247 and 161<=w<=254): raise ValueError('Unsupported code: '+char)
    return (q-161)*94+w-161


def song_chars(raw):
    if len(raw)!=4448 or raw[:4]!=b'LRC1': raise ValueError('LRC1 expected')
    # Every referenced record, including title and singer, is checked.
    u=lambda p:struct.unpack_from('<I',raw,p)[0]
    # Word 2 describes the table layout (8 header words, records at word 136).
    # Word 4 contains {line_count, lyric_character_count}, as in lyric_pick.
    if u(8)!=((136<<16)|8): raise ValueError('Unsupported LRC table layout')
    line_count=u(16)>>16
    if line_count>64: raise ValueError('LRC line count exceeds 64 slots')
    desc=[u(20),u(24)]+[u(36+8*i) for i in range(line_count)]
    chars=set()
    for v in desc:
        first,count=v&65535,v>>16
        if first+count>488: raise ValueError('LRC record range')
        for i in range(first,first+count):
            b=raw[544+8*i:546+8*i]
            chars.add(chr(b[1]) if b[0]==0 else b.decode('gb2312'))
    return chars


def row_bytes(mask):
    result=bytearray()
    for y in range(mask.height):
        pixels=[mask.getpixel((x,y))//17 for x in range(mask.width)]
        pixels += [0]*(32-len(pixels))
        result.extend((pixels[i]<<4)|pixels[i+1] for i in range(0,32,2))
    return result


def refresh_card_package():
    """Refresh metadata/package without rerasterizing verified font pixels."""
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    meta=json.loads((ROOT/'card/manifest.json').read_text(encoding='utf-8'))
    meta['format']='audio_visual_upgrade_typography_card_v1'
    meta['purpose']='华文琥珀/幼圆16级抗锯齿配套卡；仅用于TYPOGRAPHY=1的新固件'
    meta.pop('preview',None)
    meta['typography']={
        'format':'TYP1', 'font_bytes':manifest['font_bytes'],
        'glyph_count':manifest['glyph_count'], 'coverage_bits':4,
        'title_lyrics_px':24, 'singer_px':20, 'osd_px':16,
        'osd_rect':[424,16,200,224],
        'character_policy':'包含当前全部LRC使用字符及验证字符；更换歌曲后重新运行scripts/prepare_typography.py',
        'asc_loaded':False,
        'compatibility':'仅配TYPOGRAPHY=1/TYP1固件；更新用字只需换FONT.HZK，不需重新综合'
    }
    for entry in meta['files']:
        path=CARD/entry['name']
        entry['bytes']=path.stat().st_size
        entry['sha256']=preview.digest(path)
    (CARD/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (CARD/'README_typography.txt').write_text(
        '本目录为新TYPOGRAPHY固件配套素材，不可配合旧bit使用。\n'
        '复制本目录内文件到FAT32卡根目录，保持8.3文件名。\n'
        'FONT.HZK为TYP1四位覆盖率字库；ASC.HZK仅保留兼容文件，新固件不装载。\n'
        '新增或修改LRC内容后，先更新工程card目录，再运行python scripts/prepare_typography.py重新生成字库与卡包。\n'
        '缺字、边界溢出或容量不足会报错，不会裁切笔画或降低抗锯齿等级。\n'
        '字库已覆盖LRC全部行（含歌名/歌手）；不可配原1bit字库固件。\n'
        '可配typography_dspall1_seed3_phy/skeleton.bit；该bit未通过全部setup时序。\n',encoding='utf-8')
    manifest['card_files']={p.name:preview.digest(p) for p in sorted(CARD.iterdir()) if p.is_file()}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'card_typography.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(CARD.iterdir()):
            if p.is_file(): z.write(p,'sd_card/'+p.name)


def main():
    OUT.mkdir(exist_ok=True); CARD.mkdir(exist_ok=True)
    # Only used characters are stored. New songs must rerun this tool; every
    # glyph is checked against the approved baseline, never cropped to fit.
    chars=set('追梦GALA%警 ')
    for p in sorted((ROOT/'card').glob('*.LRC')): chars |= song_chars(p.read_bytes())
    with preview.TTFont(str(preview.FONTS['hupo'])) as f:
        cmap=f.getBestCmap()
        missing=sorted(c for c in chars if ord(c) not in cmap)
        if missing: raise ValueError('Font missing: '+''.join(missing))
    # Same scale/baseline as the preview. Additional card text must fit, never crop.
    words=[0]*8324
    records={}
    for char in sorted(chars,key=code_index):
        masks=[preview.text_mask(char,'hupo',size,16) for size in (24,20)]
        if any(m.width>=32 for m in masks): raise ValueError('Glyph too wide for 5-bit descriptor: '+char)
        data=b''.join(row_bytes(m) for m in masks)
        assert len(data)==704
        offset=len(words)
        if offset+176>261696 or offset>=262144: raise ValueError('Typography capacity exceeded; no quality reduction')
        w24,w20=(m.width for m in masks)
        words[4+code_index(char)]=0xA0000000 | w20<<23 | w24<<18 | offset
        words.extend(struct.unpack('<176I',data))
        records[char]={'index':code_index(char),'offset':offset,'width24':w24,'width20':w20}
    words[:4]=[0x31505954,0x00141804,len(words),len(chars)]
    data=struct.pack('<'+'I'*len(words),*words)
    for p in (ROOT/'card').iterdir():
        if p.is_file(): shutil.copy2(p,CARD/p.name)
    (CARD/'FONT.HZK').write_bytes(data)
    # Unused compatibility file retained in the package, never loaded in TYPOGRAPHY mode.
    (ROOT/'sim/typography_font.mem').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
    lrc=(ROOT/'card/S01.LRC').read_bytes()
    (ROOT/'sim/typography_lrc.mem').write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',lrc)),encoding='ascii')
    # Recover exact existing OSD glyph mapping, not a manually reordered label table.
    old=(ROOT/'card/FONT.HZK').read_bytes()
    reverse={old[i*128:(i+1)*128]:i for i in range(8178)}
    source=[int(v,16) for v in (ROOT/'rtl/gfx/osd_font_ch.dath').read_text().split()]
    ch=[0]*1024; asc=[0]*256; mapping={}
    for g in range(1,30):
        raw=b''.join(v.to_bytes(4,'big') for v in source[g*32:g*32+32])
        i=reverse[raw]; char=bytes([161+i//94,161+i%94]).decode('gb2312')
        mapping[g]=char
        m=preview.text_mask(char,'youyuan',16,16)
        raw=row_bytes(m)
        for y in range(16):
            ch[g*32+y*2]=int.from_bytes(raw[y*16:y*16+4],'big')
            ch[g*32+y*2+1]=int.from_bytes(raw[y*16+4:y*16+8],'big')
    for i,char in enumerate('0123456789%/<>'):
        m=preview.text_mask(char,'youyuan',16,16); raw=row_bytes(m)
        for y in range(16): asc[i*16+y]=int.from_bytes(raw[y*16:y*16+4],'big')
    for name,values in [('osd_youyuan_ch.dath',ch),('osd_youyuan_ascii.dath',asc)]:
        (ROOT/'rtl/gfx'/name).write_text(''.join(f'{v:08x}\n' for v in values),encoding='ascii')
    # Independent pixel reference for new row TB. Explicit CJK/ASCII and both sizes.
    samples='追梦GALA%警'
    fixture=bytearray(lrc)
    sample_widths=[]
    for i,char in enumerate(samples):
        code=bytes((0,ord(char))) if ord(char)<128 else char.encode('gb2312')
        fixture[544+i*8:552+i*8]=code+b'\0\0'+struct.pack('<I',i*1000)
    for size in (24,20):
        sample_widths += [preview.glyph('hupo',size,c).width for c in samples]
    (ROOT/'sim/typography_sample_lrc.mem').write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',fixture)),encoding='ascii')
    (ROOT/'sim/typography_sample_widths.mem').write_text(''.join(f'{v:02x}\n' for v in sample_widths),encoding='ascii')
    gold=[]
    for size in (24,20):
        for row in range(size):
            for char in samples:
                m=preview.text_mask(char,'hupo',size,16)
                gold.extend(m.getpixel((x,row))//17 for x in range(m.width))
    (ROOT/'sim/typography_row_golden.mem').write_text(''.join(f'{v:x}\n' for v in gold),encoding='ascii')
    manifest={'format':'TYP1','font_words':len(words),'font_bytes':len(data),'glyph_count':len(chars),
              'directory_words':8320,'glyph_bytes':704,'chars':records,'osd_mapping':mapping,
              'sample_text':samples,'sample_widths':{str(size):sum(preview.glyph('hupo',size,c).width for c in samples) for size in (24,20)},
              'source_fonts':{k:{'path':str(v),'sha256':preview.digest(v)} for k,v in preview.FONTS.items()},
              'card_files':{p.name:preview.digest(p) for p in CARD.iterdir() if p.is_file()},
              'note':'Pair this card package only with the new TYPOGRAPHY bitstream; original card untouched.'}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    refresh_card_package()
    print(json.dumps({k:manifest[k] for k in ('font_words','font_bytes','glyph_count','sample_widths')},ensure_ascii=False))


if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-only',action='store_true',help='Refresh card metadata/zip without changing verified font pixels')
    args=parser.parse_args()
    import prepare_full_typography as full
    if args.package_only: full.package()
    else: full.main()
