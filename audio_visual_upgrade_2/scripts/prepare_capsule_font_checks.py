from pathlib import Path
import struct
root=Path(__file__).resolve().parents[1]
words=[int(x,16) for x in (root/'sim/typography_font.mem').read_text().split()]
raw=struct.pack('<'+'I'*len(words),*words)
assert raw==(root/'card/FONT.HZK').read_bytes()
chars=[]
for a in range(0xa1,0xf8):
 for b in range(0xa1,0xff):
  try:chars.append(bytes((a,b)).decode('gb2312'))
  except UnicodeDecodeError:pass
chars+=list(map(chr,range(32,127)));assert len(chars)==7540
def code(c):return ord(c) if ord(c)<128 else int.from_bytes(c.encode('gb2312'),'big')
def descriptor(c):
 v=code(c);i=8178+v-32 if v<128 else ((v>>8)-161)*94+(v&255)-161
 return words[4+i]
def width(c,size):return (descriptor(c)>>(18 if size==24 else 23))&31
def pixels(c,size,y):
 start=(descriptor(c)&0x3ffff)*16+(0 if size==24 else 288)+y*(size//2)
 return [(raw[start+x//2]>>(4 if x%2==0 else 0))&15 for x in range(width(c,size))]
def write_missing(name,values):
 p=root/'sim'/name;s='\n'.join(values)+'\n'
 if p.exists():assert p.read_text(encoding='ascii')==s,name
 else:p.write_text(s,encoding='ascii')
write_missing('full_font_codes.mem',[f'{code(c):04x}' for c in chars])
write_missing('full_font_widths.mem',[f'{width(c,size):02x}' for c in chars for size in (24,20)])
write_missing('full_font_rows.mem',[''.join(f'{v:x}' for v in pixels(c,size,i%size)+[0]*(32-width(c,size))) for i,c in enumerate(chars) for size in (24,20)])
samples='追梦GALA%警';fixture=bytearray((root/'card/S01.LRC').read_bytes())
for i,c in enumerate(samples):fixture[544+i*8:552+i*8]=code(c).to_bytes(2,'big')+b'\0\0'+struct.pack('<I',i*1000)
write_missing('typography_sample_lrc.mem',[f'{v[0]:08x}' for v in struct.iter_unpack('<I',fixture)])
write_missing('typography_sample_widths.mem',[f'{width(c,size):02x}' for size in (24,20) for c in samples])
gold=[f'{v:x}' for size in (24,20) for y in range(size) for c in samples for v in pixels(c,size,y)]
assert len(gold)==6056,len(gold)
write_missing('typography_row_golden.mem',gold)
print('Recovered missing test vectors from unchanged, byte-verified card FONT.HZK; no font or RTL rewritten.')
