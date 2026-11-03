from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]
out=root/'output/capsule_ui_20261101_r1'
base=Image.open(root/'card/S01BG1.BMP').convert('RGB')
cover=Image.open(root/'card/S01CV1.BMP').convert('RGB')
coverage=[int(x,16) for x in (root/'sim/cover_coverage_golden.mem').read_text().split()][:57600]
for y in range(240):
 for x in range(240):
  a=coverage[y*240+x];b=base.getpixel((x+200,y+134));f=cover.getpixel((x,y))
  base.putpixel((x+200,y+134),tuple((b[c]*(15-a)+f[c]*a+7)//15 for c in range(3)))
frames=[]
for mode in ['silence','music']:
 frame=base.copy()
 pixels=[int(x,16) for x in (root/f'sim/capsule_{mode}_frame.hex').read_text().split()]
 assert len(pixels)==640*480,len(pixels)
 for i,v in enumerate(pixels):
  a=v>>24;x=i%640;y=i//640
  if a:
   b=frame.getpixel((x,y));f=((v>>16)&255,(v>>8)&255,v&255)
   frame.putpixel((x,y),tuple((b[c]*(15-a)+f[c]*a+7)//15 for c in range(3)))
 frame.save(out/f'{mode}_rtl_preview_640x480.png')
 corrected=frame.resize((768,480),Image.Resampling.BICUBIC)
 corrected.save(out/f'{mode}_screen_aspect_preview.png');frames.append(corrected)
# A close-up uses nearest-neighbor so edge coverage remains inspectable.
frames[1].crop((220,60,550,220)).resize((990,480),Image.Resampling.NEAREST).save(out/'capsule_edge_detail.png')
canvas=Image.new('RGB',(1536,520),(20,24,31));canvas.paste(frames[0],(0,40));canvas.paste(frames[1],(768,40))
draw=ImageDraw.Draw(canvas);draw.text((20,15),'SILENCE - 64 dots',(240,240,240));draw.text((788,15),'MUSIC - capsule bars (RTL fixture)',(240,240,240))
canvas.save(out/'silence_and_music_preview.png')
print('Generated RTL mask previews; not a board screenshot; title and lyric omitted in this shape preview.')
