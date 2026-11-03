"""Replace the congested precomputed index with one pipelined terminal flag."""
import json
from pathlib import Path
import shutil

root=Path(__file__).resolve().parents[1]
backup=root/'output/timing_cleanup_20261030/source_before_r3'
backup.mkdir()
for name in ['rtl/mem/sdram_arb.v','doc/workflow/state.json']:
    target=backup/name
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(root/name,target)
text=(root/'output/timing_cleanup_20261030/source_before_r2/rtl/mem/sdram_arb.v').read_text(encoding='utf-8')
text=text.replace('//   ⇒ **本文件的逻辑一行都没必要改**；',
    '//   2026-10-30: terminal condition pipelined one RUN iteration early; protocol unchanged.\n//   历史结论：')
text=text.replace('    reg [15:0] len;',
    '    reg [15:0] len;\n    reg terminal_q; // At RUN entry: n+1 >= accepted len, including len zero.')
text=text.replace("            n <= 16'd0; got <= 16'd0;\n            app_rd_en",
    "            n <= 16'd0; got <= 16'd0; terminal_q <= 1'b0;\n            app_rd_en")
text=text.replace("                    n <= 16'd0; got <= 16'd0;",
    "                    n <= 16'd0; got <= 16'd0;\n"
    "                    // Initial n is zero. Clamp can only shorten a request.\n"
    "                    terminal_q <= MAX_BURST[15:0]<=16'd1 ||\n"
    "                        (px_req ? px_len<=16'd1 : ctl_req ? ctl_len<=16'd1 : ld_len<=16'd1);")
text=text.replace("                    n <= n + 16'd1;",
    "                    n <= n + 16'd1;\n"
    "                    // Compute the condition for the NEXT RUN iteration.\n"
    "                    // 17 bits avoid overflow for the full 65535-word parameter.\n"
    "                    terminal_q <= ({1'b0,n}+17'd2 >= {1'b0,len});")
text=text.replace("if (n + 16'd1 >= len) begin", 'if (terminal_q) begin')
(root/'rtl/mem/sdram_arb.v').write_text(text,encoding='utf-8')
p=root/'doc/workflow/state.json';v=json.loads(p.read_text(encoding='utf-8-sig'))
v['timing_cleanup'].update(structural_attempts_started=3,automatic_retries_after_first_failure=2,
    attempt='timingclean_r3',stage='simulation_r3',
    r2_result=dict(setup_violations=123,non_shifted_setup_endpoints=59,
        setup_wns_ns=-5.565,hold_violations=0,slices=9773,
        physical='timingclean_r2_congestion_seed3_phy',selected=False,
        reason='Request-path terminal-index precomputation adds routing pressure and new critical paths.'))
p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('R2 preserved; R3 terminal flag applied.')
