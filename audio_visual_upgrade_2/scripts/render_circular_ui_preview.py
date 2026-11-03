"""Composite real RTL test masks with existing artwork; not a board capture."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/circular_ui_20261101_r1'

def main():
    frame=Image.open(ROOT/'card/S01BG1.BMP').convert('RGB')
    cover=Image.open(ROOT/'card/S01CV1.BMP').convert('RGB');pix=frame.load()
    coverage=[int(x,16) for x in (ROOT/'sim/cover_coverage_golden.mem').read_text().split()][:57600]
    for y in range(240):
        for x in range(240):
            a=coverage[y*240+x];b=pix[x+200,y+134];f=cover.getpixel((x,y))
            pix[x+200,y+134]=tuple((b[c]*(15-a)+f[c]*a+7)//15 for c in range(3))
    bars=[int(x,16) for x in (ROOT/'sim/circular_spectrum_frame.hex').read_text().split()]
    text=[int(x,16) for x in (ROOT/'sim/circular_text_frame.hex').read_text().split()]
    assert len(bars)==len(text)==640*480
    for i,(sp,t) in enumerate(zip(bars,text)):
        x=i%640;y=i//640
        if sp:pix[x,y]=((sp>>16)&255,(sp>>8)&255,sp&255)
        a=t>>24
        if a:
            b=pix[x,y];f=((t>>16)&255,(t>>8)&255,t&255)
            pix[x,y]=tuple((b[c]*(15-a)+f[c]*a+7)//15 for c in range(3))
    frame.save(OUT/'layout_simulation_preview_640x480.png')
    frame.resize((768,480),Image.Resampling.NEAREST).save(OUT/'layout_screen_aspect_preview.png')
    print('Preview uses RTL fixture pixels; no board capture or actual-song claim.')

if __name__=='__main__':main()
