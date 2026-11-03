from pathlib import Path
from PIL import Image,ImageDraw
import argparse
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',default='output/split_ui_20261101_r1');a=p.parse_args()
out=root/a.output
base=Image.open(root/'card/S01BG1.BMP').convert('RGB')
cover=Image.open(root/'card/S01CV1.BMP').convert('RGB')
coverage=[int(v,16) for v in (root/'sim/cover_coverage_golden.mem').read_text().split()][:57600]
def blend(frame,x,y,fg,a):
 bg=frame.getpixel((x,y))
 frame.putpixel((x,y),tuple((bg[c]*(15-a)+fg[c]*a+7)//15 for c in range(3)))
for y in range(240):
 for x in range(240):blend(base,x+40,y+134,cover.getpixel((x,y)),coverage[y*240+x])
text=[int(v,16) for v in (root/'sim/split_fast_frame.hex').read_text().split()]
assert len(text)==640*480
frames=[]
for mode in ['silence','music']:
 frame=base.copy()
 spectrum=[int(v,16) for v in (root/f'sim/split_{mode}_frame.hex').read_text().split()]
 assert len(spectrum)==640*480
 for pixels in [spectrum,text]:
  for i,v in enumerate(pixels):
   a=v>>24
   if a:blend(frame,i%640,i//640,((v>>16)&255,(v>>8)&255,v&255),a)
 frame.save(out/f'{mode}_rtl_preview_640x480.png')
 corrected=frame.resize((768,480),Image.Resampling.BICUBIC)
 corrected.save(out/f'{mode}_screen_aspect_preview.png');frames.append(corrected)
canvas=Image.new('RGB',(1536,520),(20,24,31));canvas.paste(frames[0],(0,40));canvas.paste(frames[1],(768,40))
draw=ImageDraw.Draw(canvas);draw.text((20,15),'SILENCE - RTL layout fixture',(240,240,240));draw.text((788,15),'MUSIC - RTL layout fixture',(240,240,240))
canvas.save(out/'split_ui_preview.png')
print('Rendered simulated text and spectrum over current cover/background. Test lyrics; not a board capture. OSD omitted.')
