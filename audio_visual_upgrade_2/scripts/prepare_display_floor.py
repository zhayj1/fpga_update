from pathlib import Path
import hashlib, json, shutil, wave, struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/display_floor_20261102_r1'
OUT.mkdir()  # Preserve existing evidence.
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p, v): p.write_text(json.dumps(v, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
paths = [p for folder in ('rtl','ip','constraints') for p in (ROOT/folder).rglob('*') if p.is_file()]
save(OUT/'baseline_sha256.json', {p.relative_to(ROOT).as_posix():sha(p) for p in paths})
p = ROOT/'rtl/audio/spec_bands64.v'
original = p.read_text(encoding='utf-8')
(OUT/'baseline').mkdir()
shutil.copy2(p, OUT/'baseline/spec_bands64.v')
(OUT/'spec_bands64_original.v').write_text(original.replace('module spec_bands64 (', 'module spec_bands64_original ('), encoding='utf-8')
old = "    wire [14:0] sum_next=sum+{7'd0,rd_data};"
new = '''    // Display-only floor: LOG_MAG maps raw FFT magnitudes 1..4 to 78..122.
    // Keep the shared RAM and the 18 attack bands on the original bin values.
    localparam [7:0] DISPLAY_FLOOR_LOG = 8'd122;
    wire [7:0] display_mag = (rd_data <= DISPLAY_FLOOR_LOG) ? 8'd0 : rd_data;
    wire [7:0] add_mag = attack_mode ? rd_data : display_mag;
    wire [14:0] sum_next=sum+{7'd0,add_mag};'''
assert original.count(old)==1
p.write_text(original.replace(old,new), encoding='utf-8')
wav = ROOT.parents[1]/'tone_187p5Hz_10s_48kHz_16bit_stereo.wav'
with wave.open(str(wav), 'rb') as f:
    assert (f.getframerate(), f.getnchannels(), f.getsampwidth()) == (48000,2,2)
    metadata = dict(rate=f.getframerate(), channels=f.getnchannels(), frames=f.getnframes(), sha256=sha(wav))
    raw = f.readframes(32768)
samples = [x[0] >> 4 for x in struct.iter_unpack('<hh', raw)]
assert len(samples)==32768
(OUT/'tone_left_12bit.hex').write_text(''.join(f'{x&4095:03x}\n' for x in samples), encoding='ascii')
save(OUT/'wav_input.json', metadata)
print(OUT)
