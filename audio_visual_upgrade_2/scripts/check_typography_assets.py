"""Check packed card fonts against approved raster pixels and all LRC characters."""
from pathlib import Path
import hashlib
import importlib.util
import json
import struct
import sys
import zipfile
import wave

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/typography_implementation_20261029'
spec=importlib.util.spec_from_file_location('typography_assets',ROOT/'scripts/prepare_typography.py')
assets=importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def decode_lrc(raw):
    """Independent byte-level LRC reader; do not reuse the generator's parser."""
    assert len(raw)==4448 and raw[:4]==b'LRC1'
    assert int.from_bytes(raw[8:10],'little')==8
    assert int.from_bytes(raw[10:12],'little')==136
    line_count=int.from_bytes(raw[18:20],'little')
    assert line_count<=64
    def record_text(offset):
        first=int.from_bytes(raw[offset:offset+2],'little')
        count=int.from_bytes(raw[offset+2:offset+4],'little')
        assert first+count<=488
        result=[]
        for i in range(first,first+count):
            code=raw[544+8*i:546+8*i]
            result.append(chr(code[1]) if code[0]==0 else code.decode('gb2312'))
        return ''.join(result)
    return {
        'title':record_text(20), 'singer':record_text(24),
        'lines':[{'index':i,'sample':int.from_bytes(raw[32+8*i:36+8*i],'little'),
                  'text':record_text(36+8*i)} for i in range(line_count)]}


def main():
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    card=OUT/'sd_card'
    raw=(card/'FONT.HZK').read_bytes()
    words=struct.unpack('<'+'I'*(len(raw)//4),raw)
    assert words[:4]==(0x31505954,0x00141804,len(words),len(manifest['chars']))
    assert len(raw)==manifest['font_bytes'] and len(words)<=261696
    expected_chars=set('追梦GALA%警 ')
    lrc_files=sorted(card.glob('*.LRC'))
    songs={}
    for path in lrc_files:
        raw_lrc=path.read_bytes()
        decoded=decode_lrc(raw_lrc)
        chars=set(decoded['title']+decoded['singer']+''.join(r['text'] for r in decoded['lines']))
        assert assets.song_chars(raw_lrc)==chars, (path.name,'generator skipped LRC records')
        expected_chars|=chars
        for line in decoded['lines']:
            missing=sorted(set(line['text'])-set(manifest['chars']))
            assert not missing,(path.name,line['index'],line['text'],missing)
        wav_path=path.with_suffix('.WAV')
        with wave.open(str(wav_path)) as wav:
            duration=wav.getnframes()/wav.getframerate()
        songs[path.name]={'line_count':len(decoded['lines']),'unique_characters':len(chars),
                         'last_line_seconds':decoded['lines'][-1]['sample']/48000 if decoded['lines'] else None,
                         'wav_duration_seconds':duration,'all_lines_have_glyphs':True}
    assert expected_chars==set(manifest['chars'])
    pixels=0
    levels=set()
    for char,entry in manifest['chars'].items():
        index=assets.code_index(char)
        desc=words[4+index]
        offset=desc&0x3ffff
        assert desc>>28==10 and offset==entry['offset'] and offset%4==0
        assert offset>=8324 and offset+176<=len(words)
        for size,row_offset,width in ((24,0,(desc>>18)&31),(20,24,(desc>>23)&31)):
            mask=assets.preview.text_mask(char,'hupo',size,16)
            assert width==mask.width==entry['width'+str(size)]
            for y in range(size):
                row=raw[(offset+(row_offset+y)*4)*4:(offset+(row_offset+y+1)*4)*4]
                for x in range(32):
                    value=(row[x//2]>>(4 if x%2==0 else 0))&15
                    expected=mask.getpixel((x,y))//17 if x<width else 0
                    assert value==expected,(char,size,x,y,value,expected)
                    levels.add(value)
                    pixels+=1
    assert levels==set(range(16))
    used={assets.code_index(c) for c in expected_chars}
    assert all(v==0 for i,v in enumerate(words[4:8324]) if i not in used)
    sim=[int(v,16) for v in (ROOT/'sim/typography_font.mem').read_text().split()]
    assert tuple(sim)==words
    for name,sha in manifest['card_files'].items(): assert digest(card/name)==sha,name
    meta=json.loads((card/'manifest.json').read_text(encoding='utf-8'))
    for entry in meta['files']:
        path=card/entry['name']
        assert entry['bytes']==path.stat().st_size and entry['sha256']==digest(path)
    with zipfile.ZipFile(OUT/'card_typography.zip') as archive:
        for name in manifest['card_files']:
            assert archive.read('sd_card/'+name)==(card/name).read_bytes()
        assert archive.testzip() is None
    inputs=[Path(__file__),ROOT/'scripts/prepare_typography.py',
            ROOT/'output/typography_preview_20261029/render.py',OUT/'manifest.json',
            card/'FONT.HZK',ROOT/'sim/typography_font.mem']+lrc_files+list(assets.preview.FONTS.values())
    result={'status':'PASS','scenarios':['TYP-01-card-font-pixels-and-coverage',
            'TYP-01-all-lrc-characters','TYP-01-card-metadata-and-package'],
            'songs':songs,'lrc_parser':'independent byte reader: line_count at bytes 18..19',
            'glyph_count':len(expected_chars),'compared_pixels':pixels,
            'coverage_levels':sorted(levels),'font_bytes':len(raw),
            'input_hashes':{p.as_posix():digest(p) for p in inputs},
            'package_sha256':digest(OUT/'card_typography.zip')}
    (OUT/'asset_check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('input_hashes','coverage_levels')},ensure_ascii=False))


if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    import check_full_typography as full
    full.main()
