"""Preserve R1 and apply the second, bounded timing cleanup attempt once."""
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
backup = root / 'output/timing_cleanup_20261030/source_before_r2'
backup.mkdir()
files = ['rtl/gfx/lyric_pick.v', 'rtl/mem/sdram_arb.v',
         'rtl/gfx/text_row_aa.v', 'doc/workflow/state.json']
for name in files:
    dest = backup / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / name, dest)

def replace(name, old, new):
    path = root / name
    text = path.read_text(encoding='utf-8')
    assert text.count(old) == 1, (name, old)
    path.write_text(text.replace(old, new), encoding='utf-8')

pick = root / files[0]
text = pick.read_text(encoding='utf-8')
start = text.index('    wire slot_valid=')
end = text.index(';', start) + 1
text = text[:start] + '''    // Full-width rejection first; only the bounded legal fields need addition.
    wire slot_valid=px_data[15:9]==0 && px_data[31:21]==0 &&
        px_data[20:16]!=0 && px_data[20:16]<=5'd19 &&
        ({1'b0,px_data[8:0]}+{5'd0,px_data[20:16]}<=10'd488);''' + text[end:]
pick.write_text(text, encoding='utf-8')

name = files[1]
replace(name, '//   ⇒ **本文件的逻辑一行都没必要改**；',
              '//   2026-10-30: burst terminal index is precomputed at acceptance; protocol unchanged.\n//   历史结论：')
replace(name, '    reg [15:0] len;',
              '    reg [15:0] len;\n    reg [15:0] last_n; // Accepted length minus one, saturated for length zero.')
replace(name, "            n <= 16'd0; got <= 16'd0;\n            app_rd_en",
              "            n <= 16'd0; got <= 16'd0; last_n <= 16'd0;\n            app_rd_en")
for client in ['px', 'ctl', 'ld']:
    # Keep the original clamp expression and client-priority mux.
    path = root / name
    text = path.read_text(encoding='utf-8')
    line = next(line for line in text.splitlines() if 'base <= '+client+'_addr;' in line)
    expression = f'({client}_len > MAX_BURST[15:0]) ? MAX_BURST[15:0] : {client}_len'
    addition = f"\n                                             last_n <= ({client}_len==0 || MAX_BURST[15:0]==0) ? 16'd0 : (({expression})-16'd1); end"
    text = text.replace(line, line.rsplit('end', 1)[0] + addition)
    path.write_text(text, encoding='utf-8')
replace(name, "if (n + 16'd1 >= len) begin", 'if (n >= last_n) begin')

name = files[2]
replace(name, '            if(state==RECORD || state==4\'d12) begin\n',
              '            // Results are consumed only in DIRECTORY; unconditional updates\n'
              '            // remove a long state-enable path without changing that sample.\n'
              '            begin\n')

path = root / 'doc/workflow/state.json'
state = json.loads(path.read_text(encoding='utf-8-sig'))
state['timing_cleanup'].update(structural_attempts_started=2,
    automatic_retries_after_first_failure=1, attempt='timingclean_r2',
    r1_result=dict(setup_violations=69, non_shifted_setup_endpoints=5,
                   setup_wns_ns=-5.565, hold_violations=0,
                   physical='timingclean_r1_congestion_seed3_phy'))
path.write_text(json.dumps(state, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('R1 preserved; R2 applied.')
