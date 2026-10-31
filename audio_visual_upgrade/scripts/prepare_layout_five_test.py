"""Create deterministic layout fixtures; read packed glyphs via font manifest."""
from pathlib import Path
import json,struct
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/layout_five_20261030'

def main():
    manifest=json.loads((ROOT/'output/typography_full_20261030/manifest.json').read_text(encoding='utf-8'))
    raw=(ROOT/'output/typography_full_20261030/sd_card/FONT.HZK').read_bytes()
    lines=['追梦GALA%警','我想要怒放的生命世界如此美丽','不在乎它是不是悬崖峭壁追梦人啊','就算风雨再大也要勇敢追逐梦想直到天明啊','世界如此美丽','让生命像一首歌永远唱出心中的希望','追梦赤子心','GALA']
    records=[0]*1112;gold=[];small=[];info=[];first=0
    for line_no,text in enumerate(lines):
        assert len(text)<=19
        width=sum(manifest['chars'][c]['width24'] for c in text)
        info.append({'text':text,'first':first,'count':len(text),'width':width})
        for i,c in enumerate(text):
            code=bytes((0,ord(c))) if ord(c)<128 else c.encode('gb2312')
            records[136+2*(first+i)]=int.from_bytes(code+b'\0\0','little')
            records[137+2*(first+i)]=i*1000
        for y in range(24):
            row=[]
            for i,c in enumerate(text):
                char=manifest['chars'][c];offset=char['offset_words']*4+y*12
                packed=raw[offset:offset+12]
                row += [((packed[x//2]>>(4 if x%2==0 else 0))&15)|(16 if i*1000<=2500 else 0) for x in range(char['width24'])]
            gold+=row+[0]*(576-width)
        for y in range(20):
            row=[]
            for c in text:
                char=manifest['chars'][c];offset=char['offset_words']*4+288+y*10
                packed=raw[offset:offset+10]
                row += [(packed[x//2]>>(4 if x%2==0 else 0))&15 for x in range(char['width20'])]
            small+=row+[0]*(480-len(row))
        first+=len(text)
    (ROOT/'sim/layout_five_lrc.mem').write_text(''.join(f'{v:08x}\n' for v in records),encoding='ascii')
    (ROOT/'sim/layout_five_gold.mem').write_text(''.join(f'{v:02x}\n' for v in gold),encoding='ascii')
    (ROOT/'sim/layout_five_small.mem').write_text(''.join(f'{v:x}\n' for v in small),encoding='ascii')
    (ROOT/'sim/layout_five_info.mem').write_text(''.join(f'{v:04x}\n' for line in info for v in (line['first'],line['count'],line['width'])),encoding='ascii')
    (OUT/'fixtures.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
