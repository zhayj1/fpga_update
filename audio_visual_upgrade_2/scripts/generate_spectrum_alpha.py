"""Regenerate/check the exact combinational capsule edge-alpha constant."""
from pathlib import Path
import argparse,re

parser=argparse.ArgumentParser()
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
thresholds=(102,108,113,119,125,131,137,144,150,157,163,170,177,184,192)
entries=[next((15-i for i,t in enumerate(thresholds) if a*a+b*b<=t),0)
         for a in range(16) for b in range(16)]
constant=''.join(format(v,'x') for v in reversed(entries))
if args.check:
    source=(root/'rtl/gfx/layer_spectrum_ring.v').read_text()
    actual=re.search(r"CAPSULE_ALPHA=1024'h([0-9a-f]+)",source).group(1)
    assert actual==constant, 'Capsule alpha table differs from original thresholds'
    print('PASS: all 256 capsule edge-alpha entries match the original thresholds')
else:
    print("localparam [1023:0] CAPSULE_ALPHA=1024'h"+constant+';')
