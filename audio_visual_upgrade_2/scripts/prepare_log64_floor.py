"""Save the authorized baseline and apply the reviewed discrete log map."""
from pathlib import Path
import hashlib, json, shutil, re, bisect, csv

ROOT = Path(__file__).resolve().parents[1]
TAG = 'log64_floor_20261102_r1'
OUT = ROOT/'output'/TAG
assert not OUT.exists(), 'Preserve existing evidence'
OUT.mkdir()
def read(p): return p.read_text(encoding='utf-8-sig')
def write(p,t): p.write_text(t,encoding='utf-8')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
inputs=json.loads(read(ROOT/'prj/td_build/display_floor_20261102_r3_syn/inputs.json'))
baseline={}
for entry in inputs['sources']:
    src=Path(entry['path']); rel=src.relative_to(ROOT)
    assert sha(src)==entry['sha256'].lower(), str(src)
    dst=OUT/'baseline'/rel; dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(src,dst); baseline[rel.as_posix()]=sha(src)
for p in ['tb/tb_spectrum_stage1.v','tb/tb_layer_fft64.v','tb/tb_split_spectrum.v',
          'tb/expected_split_spectrum.json','tb/expected_spectrum_stage1.json']:
    dst=OUT/'baseline'/p; dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/p,dst)
write(OUT/'baseline_sha256.json',json.dumps(baseline,indent=2))
write(OUT/'authorization.txt','按照这般方案修改吧可以适合多数歌曲，保留刚加入的残值门限\n64段离散对数划分，同步尖峰位置，不增加频段增益；保留 <=122 残值门限。\n')
linear=read(ROOT/'rtl/audio/spec_bands64.v')
log=read(ROOT/'output/linear64_20261102_r1/baseline/rtl/audio/spec_bands64.v')
write(OUT/'spec_bands64_linear_reference.v',linear.replace('module spec_bands64 (','module spec_bands64_linear_reference (',1))
write(OUT/'spec_bands64_log_reference.v',log.replace('module spec_bands64 (','module spec_bands64_log_reference (',1))
map_start=log.index('    // The approved 48 kHz map')
map_end=log.index("    // HTML's")
start=linear.index('    // 48 kHz / 1024:')
end=linear.index("    // HTML's")
new=linear[:start]+log[map_start:map_end]+linear[end:]
new=new.replace('wire [15:0] recip=attack_recip(attack_band_idx);',
    'wire [15:0] recip=attack_mode ? attack_recip(attack_band_idx)\n                                    : band_recip(bar_idx);')
start=new.index('    // Exactly four display bins:')
end=new.index('    wire [8:0] smooth=',start)
new=new[:start]+'''    // Single-bin bands must pass through the same display floor.
    wire single_bin=!attack_mode &&
                    ((bar_idx<=6'd21)||(bar_idx==6'd23)||(bar_idx==6'd25));
    wire [7:0] average=single_bin ? add_mag
                      : ((scaled[30:16]>255)?8'd255:scaled[23:16]);
'''+new[end:]
write(ROOT/'rtl/audio/spec_bands64.v',new)
hi=list(range(1,23))+[24,25,27,28,30,32,34,36,38,40,43,45,48,51,54,57,61,64,68,72,76,81,86,91,96,102,108,114,121,128,136,144,153,162,171,181,192,203,215,228,242,256]
lo_attack=[1,1,1,2,3,4,5,8,11,15,20,28,39,54,75,104,144,200]
hi_attack=[2,2,2,3,4,5,8,11,15,20,28,39,54,75,104,144,200,277]
centers=[bisect.bisect_left(hi,(a+b)//2) for a,b in zip(lo_attack,hi_attack)]
assert len(hi)==64 and centers[16]==57
for p in ['rtl/gfx/layer_fft64.v','rtl/gfx/layer_spectrum_ring.v']:
    text=read(ROOT/p)
    start=text.index('    // Place each unchanged attack band')
    end=text.index('    function [5:0] attack_center;',start)
    text=text[:start]+"    // Map each attack band's integer bin midpoint into the log display bands.\n"+text[end:]
    for i,c in enumerate(centers):
        text,count=re.subn(r"(5'd"+str(i)+r": attack_center=6'd)\d+;",r'\g<1>'+str(c)+';',text)
        assert count==1,(p,i)
    write(ROOT/p,text)
with (OUT/'frequency_map.csv').open('w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f);w.writerow(['bar_1_based','bin_lo','bin_hi','bin_center_lo_hz','bin_center_hi_hz','bin_count'])
    prev=0
    for b,h in enumerate(hi):
        w.writerow([b+1,prev+1,h,(prev+1)*46.875,h*46.875,h-prev]);prev=h
write(OUT/'attack_centers.json',json.dumps(centers))

# New reference tests keep all previous release tests and frozen inputs intact.
t=read(ROOT/'tb/tb_display_floor.v')
t=t.replace('display_floor_check','log64_floor_check').replace('tb_display_floor','tb_log64_floor')
t=t.replace('spec_bands64_original','spec_bands64_log_reference')
t=t.replace('wire [7:0] old_attack_level, filtered_level;', '''wire [7:0] old_attack_level, filtered_level;
    wire linear_attack_stb;
    wire [4:0] linear_attack_idx;
    wire [7:0] linear_attack_level;''')
t=t.replace('    spec_attack18 attack_new', '''    spec_bands64_linear_reference linear_reference(clk,rst_n,bin_stb,bin_idx,bin_mag,frame_stb,
        ,,,,linear_attack_stb,linear_attack_idx,linear_attack_level);
    spec_attack18 attack_new''')
t=t.replace('spec_attack18 attack_old(clk,rst_n,old_attack_stb,old_attack_idx,old_attack_level,sensitivity,',
            'spec_attack18 attack_old(clk,rst_n,linear_attack_stb,linear_attack_idx,linear_attack_level,sensitivity,')
t=t.replace('attack_result !== old_attack_result)',
            '{attack_stb,attack_idx,attack_level} !== {linear_attack_stb,linear_attack_idx,linear_attack_level} ||\n                attack_result !== old_attack_result)')
write(ROOT/'tb/tb_log64_floor.v',t)
t=read(ROOT/'tb/tb_display_floor_wav.v').replace('display_floor_check','log64_floor_check').replace('tb_display_floor_wav','tb_log64_floor_wav')
t=t.replace('idx>=2','(idx<2 || idx>4)').replace('idx==1','idx==4').replace('idx==0','idx==3')
t=t.replace('first bar','fourth bar').replace('first_min','fourth_min').replace('first_max','fourth_max').replace('second_max','fifth_max')
t=t.replace('actual_wav_187p5_first_bar_stable_within_2_levels','actual_wav_187p5_fourth_bar_stable_within_2_levels')
t=t.replace('actual_wav_other_62_bars_zero','actual_wav_outside_three_tone_bins_zero')
write(ROOT/'tb/tb_log64_floor_wav.v',t)

# Independent boundary / coverage / averaging test.
t=read(ROOT/'tb/tb_spec_bands64_distinct.v').replace('tb_spec_bands64_distinct','tb_log64_mapping')
t=t.replace('    integer reads [0:511];','    integer band_high[0:63];\n    integer j, lower, width, value, total_mag, q16;\n    integer reads [0:511];')
t=t.replace('    initial begin\n', '    initial begin\n'+''.join(f'        band_high[{i}]={h};\n' for i,h in enumerate(hi)),1)
t=t.replace('if(dut.cursor<4*bar_idx+1 || dut.cursor>4*bar_idx+4)',
    'if(dut.cursor<(bar_idx==0?1:band_high[bar_idx-1]+1) || dut.cursor>band_high[bar_idx])')
start=t.index('            expected_mag=')
end=t.index('            expected_level=',start)
t=t[:start]+'''            lower=bar_idx==0?1:band_high[bar_idx-1]+1;
            width=band_high[bar_idx]-lower+1;
            total_mag=0;
            for(j=lower;j<=band_high[bar_idx];j=j+1) begin
                value=(j*37+11)%256;
                if(value>122) total_mag=total_mag+value;
            end
            q16=(65536+width/2)/width;
            expected_mag=width==1?total_mag:(total_mag*q16)>>16;
'''+t[end:]
t=t.replace('if(band_reads[i]!=4)', 'if(band_reads[i]!=band_high[i]-(i==0?0:band_high[i-1]))')
t=t.replace('linear bar','log bar').replace('equal_width_four_bins','log_widths_and_filtered_averages')
write(ROOT/'tb/tb_log64_mapping.v',t)

p=ROOT/'tb/tb_spectrum_stage1.v';write(p,read(p).replace('band15','band39').replace("bar_idx==6'd15","bar_idx==6'd39"))
p=ROOT/'tb/expected_spectrum_stage1.json';write(p,read(p).replace('band15','band39'))
p=ROOT/'tb/tb_layer_fft64.v';write(p,read(p).replace('bar_idx=42','bar_idx=57').replace(',421',',571'))
p=ROOT/'tb/tb_split_spectrum.v';t=read(p)
t=t.replace('check_linear_spikes','check_log_spikes').replace('linear-frequency','log-frequency').replace('linear spike','log spike')
t=t.replace('integer attack_lo_ref[0:17]', 'integer log_high[0:63], search_band, midpoint;\n    integer attack_lo_ref[0:17]')
t=t.replace('            attack_lo_ref[0]=1;', ''.join(f'            log_high[{i}]={h};\n' for i,h in enumerate(hi))+'            attack_lo_ref[0]=1;',1)
t=t.replace('expected_center=((attack_lo_ref[j]+attack_hi_ref[j])/2-1)/4;',
    '''midpoint=(attack_lo_ref[j]+attack_hi_ref[j])/2;
                expected_center=0;
                for(search_band=0;search_band<64;search_band=search_band+1)
                    if(midpoint>log_high[search_band]) expected_center=search_band+1;''')
write(p,t)
p=ROOT/'tb/expected_split_spectrum.json';write(p,read(p).replace('linear-frequency','log-frequency'))
print(json.dumps({'tag':TAG,'baseline_sources':len(baseline),'spike_centers':centers}))
