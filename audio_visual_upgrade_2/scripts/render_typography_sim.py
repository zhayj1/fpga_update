"""Convert self-checked ModelSim pixel dumps to images; no reference rendering."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'music_screen/.pylibs'))
from PIL import Image

OUT=ROOT/'output/typography_implementation_20261029'


def frames(name,count):
    values=[int(v,16) for v in (ROOT/'sim'/name).read_text().split()]
    if len(values)!=640*256*count: raise ValueError(f'Incomplete {name}: {len(values)} pixels')
    result=[]
    for i in range(count):
        raw=bytearray()
        for v in values[i*640*256:(i+1)*640*256]: raw.extend(v.to_bytes(3,'big'))
        result.append(Image.frombytes('RGB',(640,256),bytes(raw)))
    return result


def main():
    osd=frames('typography_osd_actual.mem',6)
    for i,im in enumerate(osd): im.save(OUT/f'osd_sim_{i//3}_{i%3}.png')
    sheet=Image.new('RGB',(600,448))
    for i,im in enumerate(osd): sheet.paste(im.crop((424,16,624,240)),((i%3)*200,(i//3)*224))
    sheet.save(OUT/'osd_sim_three_pages.png')
    frames('typography_core_actual.mem',1)[0].save(OUT/'core_sim_alignment.png')
    print('Rendered six OSD frames and one core alignment frame from actual simulator output')


if __name__=='__main__': main()
