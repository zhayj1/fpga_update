"""Generate fixed raster boundaries and independent full-frame test geometry."""
from pathlib import Path
import math, json, copy
ROOT=Path(__file__).resolve().parents[1]

def write_json(path,value):
    (ROOT/path).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')

def main():
    if "output wire [3:0] coverage" in (ROOT/"rtl/gfx/layer_spectrum_ring.v").read_text(encoding="utf-8"):
        raise SystemExit("Capsule renderer active: use scripts/prepare_capsule_ui.py; legacy ROM would be incompatible.")
    boundaries=[]
    for dy in range(256):
        for k in range(32):
            theta=(k//2+(.15 if k%2==0 else .85))*math.pi/32
            boundaries.append(min(255,math.ceil(dy*5/6*math.tan(theta))))
    (ROOT/'rtl/gfx/spectrum_angles.dath').write_text('\n'.join(f'{x:02x}' for x in boundaries)+'\n')
    golden=[]; counts=[0]*64; mismatches=[]
    for y in range(480):
        dy=abs(y-254);phase=32
        for x in range(640):
            dx=abs(x-320)
            if x==320: phase=0
            elif x<320 and phase and dx<boundaries[(dy&255)*32+phase-1]: phase-=1
            elif x>320 and phase<32 and dx>=boundaries[(dy&255)*32+phase]: phase+=1
            radius2=(1.2*(x-320))**2+(y-254)**2
            theta=math.atan2(1.2*(x-320),254-y)%(2*math.pi)
            position=theta*32/math.pi;band=int(position)%64
            within=136**2<=radius2<=182**2 and .15<=position%1<.85
            ref=(64|band) if within else 0
            golden.append(ref)
            if within:counts[band]+=1
            if 136**2<=radius2<=182**2:
                sector=(phase>>1)&15
                actual=(63-sector if x<320 else sector) if y<254 else (32+sector if x<320 else 31-sector)
                if bool(phase&1)!=within or (within and actual!=band):mismatches.append((x,y,phase,band))
    assert not mismatches,mismatches[:8]
    assert all(counts),counts
    (ROOT/'sim/circular_geometry_golden.mem').write_text('\n'.join(f'{x:02x}' for x in golden)+'\n')
    print(json.dumps({'angle_bytes':len(boundaries),'checked_pixels':len(golden),'band_pixel_range':[min(counts),max(counts)]}))
    # Extend only new test configurations. Historical evidence/configs remain.
    for name,old in [('core','visual_core'),('board','board_compile'),('text','layout_five'),
                     ('text_sdram','layout_sdram'),('legacy_core','visual_core'),('system','downscale_integration')]:
        cfg=json.loads((ROOT/f'sim/modelsim_{old}.json').read_text(encoding='utf-8-sig'))
        if name in ('core','text','text_sdram'):
            oldtb='tb_visual_core' if name=='core' else 'tb_layout_five'
            newtb='tb_circular_core' if name=='core' else 'tb_circular_text'
            cfg['tb_top']='work.'+newtb
            if cfg.get('dut_top')=='work.'+oldtb:cfg['dut_top']='work.'+newtb
            for lib in cfg['libraries']:
                for src in lib['sources']:
                    if src['path']==f'tb/{oldtb}.v':src['path']=f'tb/{newtb}.v'
        if name in ('core','board','legacy_core','system'):
            cfg['libraries'][0]['sources'].append({'path':'rtl/gfx/layer_spectrum_ring.v','language':'verilog'})
            cfg.setdefault('data_files',[]).append('rtl/gfx/spectrum_angles.dath')
        write_json(f'sim/modelsim_circular_{name}.json',cfg)
    sources=['sim/vendor/eg4/eg_phy_bram.v','sim/vendor/eg4/eg_phy_bram32k.v',
             'sim/vendor/eg4/eg_logic_bram.v','rtl/gfx/attack_rings.v',
             'rtl/gfx/layer_spectrum_ring.v','tb/tb_circular_spectrum.v']
    write_json('sim/modelsim_circular_spectrum.json',{'dut_top':'work.layer_spectrum_ring','tb_top':'work.tb_circular_spectrum',
        'data_files':['rtl/gfx/spectrum_angles.dath','sim/circular_geometry_golden.mem'],
        'libraries':[{'name':'work','defines':['OSD_SIM'],'sources':[{'path':p,'language':'verilog'} for p in sources]}]})

if __name__=='__main__':main()
