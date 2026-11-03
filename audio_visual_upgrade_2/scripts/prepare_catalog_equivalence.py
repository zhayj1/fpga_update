"""Keep the existing independent catalog matrix and add a cycle comparator."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
original = (ROOT / 'output/transitions_round2/resource_catalog_r4.v').read_text(encoding='utf-8')
(ROOT / 'output/transitions_round2/resource_catalog_reference.v').write_text(
    original.replace('module resource_catalog #', 'module resource_catalog_reference #'), encoding='utf-8')
tb = (ROOT / 'tb/tb_catalog_matrix.v').read_text(encoding='utf-8').replace(
    'module tb_catalog_matrix #', 'module tb_catalog_equivalence #')
instance = re.search(r'    resource_catalog dut \(.*?\n    \);', tb, re.S)[0]
header = original.split(');', 1)[0]
names = []
for line in header.splitlines():
    if 'output ' in line:
        fields = re.sub(r'output (?:wire|reg)\s*(?:\[[^]]+\])?\s*', '', line.strip()).rstrip(',')
        names.extend(n.strip() for n in fields.split(','))
reference = instance.replace('resource_catalog dut', 'resource_catalog_reference reference')
reference = re.sub(r'\.(\w+)\([^)]*\)',
                   lambda m: '.' + m[1] + '()' if m[1] in names else m[0], reference)
checks = ['dut.' + n + ' !== reference.' + n for n in names]
checks += ['dut.' + n + ' !== reference.' + n for n in ('seen', 'valid', 'exists', 'too_large')]
checker = '''
    always @(negedge clk) if(rst_n) begin
        if(''' + ' ||\n           '.join(checks) + ''') begin
            $display("TEST_FAIL catalog cycle equivalence time=%0t",$time);$finish;
        end
    end
'''
tb = tb.replace(instance, instance + '\n' + reference + checker)
# Exhaustively exercise the byte validation ahead of decimal arithmetic.
# Invalid ASCII must remain ignored even when its low nibble is a digit.
extra = '''
        reset_catalog;
        for(number=0;number<256;number=number+1)
          for(mask=0;mask<256;mask=mask+1) begin
            @(negedge clk);
            wr_name={8'h53,number[7:0],mask[7:0],16'h4247,8'h31,16'h2020,24'h424d50};
            wr_type=0;wr_size=128;wr_cluster=number*256+mask;wr_en=1;
            @(negedge clk);wr_en=0;
          end
        for(number=0;number<256;number=number+1)
          for(mask=0;mask<4;mask=mask+1) begin
            @(negedge clk);
            wr_name={24'h533031,16'h4356,number[7:0],16'h2020,24'h424d50};
            wr_type=mask;wr_size=32'hffffffff;wr_cluster=number;wr_en=1;
            @(negedge clk);wr_en=0;
          end
        $display("SCENARIO_PASS CAT-cycle-all-name-bytes");
'''
tb = tb.replace('$display("TEST_PASS");', extra+'\n        $display("TEST_PASS");')
assert 'SCENARIO_PASS CAT-cycle-all-name-bytes' in tb
(ROOT / 'tb/tb_catalog_equivalence.v').write_text(tb, encoding='utf-8')
cfg = json.loads((ROOT / 'sim/modelsim_catalog_matrix.json').read_text())
cfg['dut_top'] = cfg['tb_top'] = 'work.tb_catalog_equivalence'
cfg['libraries'][0]['sources'] = [dict(path=p, language='verilog') for p in (
    'rtl/storage/resource_catalog.v', 'output/transitions_round2/resource_catalog_reference.v',
    'tb/tb_catalog_equivalence.v')]
(ROOT / 'sim/modelsim_catalog_equivalence.json').write_text(json.dumps(cfg, indent=2) + '\n')
expected = json.loads((ROOT / 'tb/expected_catalog_matrix.json').read_text())
expected.append('CAT-cycle-all-name-bytes')
(ROOT / 'tb/expected_catalog_equivalence.json').write_text(json.dumps(expected, indent=2)+'\n')
print('Comparing all', len(names), 'outputs and all catalog flag banks each cycle')
