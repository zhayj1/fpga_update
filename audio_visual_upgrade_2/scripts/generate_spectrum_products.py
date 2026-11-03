from pathlib import Path
root=Path(__file__).resolve().parents[1]
coefficients={'sx':[15,45,75,103,131,158,183,206,228,247,263,278,289,298,304,307],
              'cy':[256,253,248,241,231,220,206,190,172,152,132,109,86,62,38,13]}
for name,values in coefficients.items():
    words=[digit*values[sector] for sector in range(16) for digit in range(16)]+[0]*256
    (root/f'rtl/gfx/spectrum_{name}_products.dath').write_text(''.join(f'{v:04x}\n' for v in words),encoding='ascii')
