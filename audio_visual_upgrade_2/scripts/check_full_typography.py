"""Independent TYP2 byte decoder, complete encoding and LRC coverage checks."""
import hashlib
import importlib.util
import json
import struct
import wave
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    s=importlib.util.spec_from_file_location(name,ROOT/path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
gen=module('full_assets','scripts/prepare_full_typography.py')
oldcheck=module('old_check','scripts/check_typography_assets.py')
OUT=gen.OUT
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    card=OUT/'sd_card'; raw=(card/'FONT.HZK').read_bytes()
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    assert len(raw)==3856960
    assert struct.unpack_from('<4I',raw)==(0x32505954,0x00141804,964240,7540)
    # Enumerate all encoding slots independently, including undefined slots.
    expected={}
    for index in range(8178):
        code=bytes((161+index//94,161+index%94))
        try: expected[index]=code.decode('gb2312')
        except UnicodeDecodeError: pass
    expected.update({8178+i:chr(32+i) for i in range(95)})
    assert len(expected)==7540 and set(expected.values())==set(manifest['chars'])
    masks={};levels=set();pixels=0;offsets=set()
    for i in range(8320):
        desc=int.from_bytes(raw[16+i*4:20+i*4],'little')
        if i not in expected:
            assert desc==0,('undefined code',i);continue
        char=expected[i];start=(desc&0x3ffff)*16
        assert desc>>28==10 and start>=33296 and start+496<=len(raw)
        assert (start-33296)%496==0 and start not in offsets
        assert start==33296+(i if i<846 else i-564)*496,('direct slot mismatch',i)
        offsets.add(start)
        assert raw[start+488:start+496]==bytes(8)
        for size,offset,pitch,width in ((24,0,12,(desc>>18)&31),(20,288,10,(desc>>23)&31)):
            m=gen.mask(char,size);masks[char,size]=m
            assert 0<width==m.width<=size
            for y in range(size):
                for x in range(size):
                    b=raw[start+offset+y*pitch+x//2]
                    actual=(b>>(4*(1-x%2)))&15
                    want=m.getpixel((x,y))//17 if x<width else 0
                    assert actual==want,(char,size,x,y,actual,want)
                    levels.add(actual);pixels+=1
    assert levels==set(range(16)) and len(offsets)==7540
    for slot in range(7709):
        start=33296+496*slot
        if start not in offsets: assert raw[start:start+496]==bytes(496),('reserved slot',slot)
    # Preserve every approved old glyph pixel, rather than just a screenshot.
    old=ROOT/'output/typography_implementation_20261029'
    old_manifest=json.loads((old/'manifest.json').read_text(encoding='utf-8'))
    old_raw=(old/'sd_card/FONT.HZK').read_bytes();old_pixels=0
    for char,rec in old_manifest['chars'].items():
        for size,row_offset in ((24,0),(20,24)):
            m=masks[char,size];assert m.width==rec['width'+str(size)]
            for y in range(size):
                for x in range(m.width):
                    b=old_raw[(rec['offset']+(row_offset+y)*4)*4+x//2]
                    assert ((b>>(4*(1-x%2)))&15)==m.getpixel((x,y))//17,(char,size,x,y)
                    old_pixels+=1
    songs={}
    for path in sorted(card.glob('*.LRC')):
        decoded=oldcheck.decode_lrc(path.read_bytes())
        text=decoded['title']+decoded['singer']+''.join(x['text'] for x in decoded['lines'])
        assert set(text)<=set(manifest['chars'])
        with wave.open(str(path.with_suffix('.WAV'))) as wav:
            duration=wav.getnframes()/wav.getframerate()
        songs[path.name]={'line_count':len(decoded['lines']),'all_lines_covered':True,
                         'unique_characters':len(set(text)),'wav_seconds':duration,
                         'last_line_seconds':decoded['lines'][-1]['sample']/48000}
    # Independent memory map guard: four image pairs, two lyrics, full font.
    slots=[(f'BG{i}',i*230400,230400) for i in range(4)]
    slots += [(f'CV{i}',921600+i*43200,43200) for i in range(4)]
    slots += [('LRC0',1094400,1112),('LRC1',1095512,1112),('FONT',1096624,len(raw)//4)]
    for a,b in zip(slots,slots[1:]):assert a[1]+a[2]==b[1],(a,b)
    assert all(start%4==0 and length%4==0 for _,start,length in slots)
    assert slots[-1][1]+slots[-1][2]<=2**21
    sim_words=[int(v,16) for v in (ROOT/'sim/typography_font.mem').read_text().split()]
    assert struct.pack('<'+'I'*len(sim_words),*sim_words)==raw
    with zipfile.ZipFile(OUT/'card_typography_full.zip') as z:
        assert z.testzip() is None
        for name,digest in manifest['card_files'].items():
            assert sha(card/name)==digest and z.read('sd_card/'+name)==(card/name).read_bytes()
    meta=json.loads((card/'manifest.json').read_text(encoding='utf-8'))
    for entry in meta['files']:
        f=card/entry['name'];assert entry['bytes']==f.stat().st_size and entry['sha256']==sha(f)
    report={'status':'PASS','scenarios':['FULL-01-complete-encoding-and-pixels','FULL-01-original-pixels-preserved',
        'FULL-01-independent-lrc-coverage','FULL-01-memory-map-and-package'],
        'glyph_count':7540,'compared_pixels':pixels,'preserved_old_pixels':old_pixels,
        'font_bytes':len(raw),'free_sdram_bytes':145152,'songs':songs,
        'slot_map':[{'name':n,'base_word':a,'words':w} for n,a,w in slots],
        'package_sha256':sha(OUT/'card_typography_full.zip'),
        'input_hashes':{str(f):sha(f) for f in [Path(__file__),ROOT/'scripts/prepare_full_typography.py',
            ROOT/'scripts/check_typography_assets.py',card/'FONT.HZK',OUT/'manifest.json']}}
    (OUT/'asset_check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('input_hashes','slot_map')},ensure_ascii=False))


if __name__=='__main__':main()
