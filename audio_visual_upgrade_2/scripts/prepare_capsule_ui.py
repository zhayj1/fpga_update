from pathlib import Path
import math
root=Path(__file__).resolve().parents[1]
b=[min(255,math.ceil(y*5/6*math.tan((k+1)*math.pi/32))) if k<15 else 255 for y in range(256) for k in range(16)]
(root/'rtl/gfx/spectrum_angles.dath').write_text('\n'.join(f'{v:02x}' for v in b)+'\n',encoding='ascii')
print('Capsule nearest-sector ROM: 4096 bytes')
