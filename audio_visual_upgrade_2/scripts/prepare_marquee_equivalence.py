"""Prepare an immutable r7 reference and the AA-marquee cycle comparator."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/transitions_timing'
source = (OUT / 'layer_text_aa_r7.v').read_text()
(OUT / 'layer_text_aa_reference.v').write_text(source.replace(
    'module layer_text_aa #', 'module layer_text_aa_reference #'))
cfg = json.loads((ROOT / 'sim/modelsim_typography_layer.json').read_text())
cfg['dut_top'] = cfg['tb_top'] = 'work.tb_marquee_equivalence'
cfg['libraries'][0]['sources'] = [s for s in cfg['libraries'][0]['sources']
    if not s['path'].startswith('tb/')]
cfg['libraries'][0]['sources'] += [dict(path=p, language='verilog') for p in (
    'output/transitions_timing/layer_text_aa_reference.v', 'tb/tb_marquee_equivalence.v')]
(ROOT / 'sim/modelsim_marquee_equivalence.json').write_text(json.dumps(cfg, indent=2)+'\n')
(ROOT / 'tb/expected_marquee_equivalence.json').write_text(json.dumps([
    'MARQUEE-all-widths-and-offset-boundaries', 'MARQUEE-cadence-hold-and-overflow',
    'MARQUEE-random-completion-reset-priority'], indent=2)+'\n')

connections = '''
        .clk_pix(cp),.rst_pix_n(rn),.hs(1'b1),.vs(1'b1),.de(1'b0),
        .en(1'b1),.en_ttl(1'b1),.color_title(24'h123456),.color_singer(24'h567890),
        .color_sung(24'hABCDEF),.color_other(24'hFEDCBA),
        .dout(RESULT[23:0]),.dout_vld(RESULT[24]),.alpha(RESULT[28:25]),
        .gap_cnt(RESULT[60:29]),.on_cnt(RESULT[92:61]),.ttl_off(RESULT[104:93]),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd0),
        .cur_fc(16'd0),.nxt_fc(16'd0),.n3_fc(16'd0),
        .cur_cnt(16'd0),.nxt_cnt(16'd0),.n3_cnt(16'd0),
        .cur_vld(1'b0),.nxt_vld(1'b0),.n3_vld(1'b0),
        .prev2_fc(16'd0),.prev2_cnt(16'd0),.prev_fc(16'd0),.prev_cnt(16'd0),
        .n4_fc(16'd0),.n4_cnt(16'd0),.prev2_vld(1'b0),.prev_vld(1'b0),.n4_vld(1'b0),
        .prev3_fc(16'd0),.prev3_cnt(16'd0),.n5_fc(16'd0),.n5_cnt(16'd0),
        .prev3_vld(1'b0),.n5_vld(1'b0),.song_clear(1'b0),
        .off_px(6'd0),.desc_tgl(1'b0),.samp_stb(stb),
        .ttl_fc(tf),.ttl_cnt(tc),.sgr_fc(sf),.sgr_cnt(sc),.ttl_vld(1'b1),.sgr_vld(1'b1),
        .px_req(RESULT[105]),.px_addr(RESULT[126:106]),.px_len(RESULT[142:127]),
        .px_ack(1'b0),.px_done(1'b0),.px_data(32'd0),.px_valid(1'b0)'''
instances = '\n'.join(f'    {module} #(.BOX_W(BOX_W),.SPP(SPP),.HOLD_N(HOLD_N)) {name}('
    + connections.replace('RESULT', result) + ');'
    for module, name, result in [('layer_text_aa', 'dut', 'actual'),
                                ('layer_text_aa_reference', 'reference', 'expected')])
force_lines = '\n'.join(f'        force {name}.{signal}={value};'
    for name in ('dut', 'reference')
    for signal, value in [('working', 'inject_work'), ('c_kind', 'inject_kind'),
                          ('row_done', 'inject_done'), ('row_width', 'inject_width'),
                          ('row_error', 'inject_error'), ('cancel_job', 'inject_cancel')])
template = r'''`timescale 1ns/1ps
`default_nettype none
module marquee_case #(parameter integer BOX_W=448,SPP=2,HOLD_N=3,ID=0)(output reg [2:0] done=0);
    reg cp=0,cs=0; always #20 cp=~cp; always #5 cs=~cs;
    reg rn=0,stb=0,inject_work=0,inject_done=0,inject_cancel=0;
    reg [1:0] inject_kind=0; reg [9:0] inject_width=0;reg [7:0] inject_error=0;
    reg [15:0] tf=0,tc=0,sf=0,sc=0;
    wire [142:0] actual,expected;
INSTANCES
    integer i,j,pos,seed;
    reg [31:0] limit;
    task tick;begin @(negedge cs);#1;end endtask
    task deposit_step;
        input integer offset;
        begin
            dut.off_t=offset;reference.off_t=offset;
            dut.off_s=offset;reference.off_s=offset;
            dut.hold_count=0;reference.hold_count=0;
            dut.hold_empty=1;reference.hold_empty=1;
            dut.div_count=SPP-1;reference.div_count=SPP-1;
            dut.divider_last=1;reference.divider_last=1;
            stb=1;tick;
        end
    endtask
    // Compare the untouched r7 sequential logic and all public outputs after
    // every SDR edge, including simultaneous row completion/sample/descriptor
    // updates. Inject only the row-renderer completion interface in both.
    always @(posedge cs) begin
        #1;
        if(actual!==expected ||
           {dut.off_t,dut.off_s,dut.div_count,dut.hold_count,dut.hold_empty,dut.divider_last,
            dut.title_changed_q,dut.singer_changed_q,dut.done_toggle,dut.completed_width,
            dut.completed_kind,dut.completed_scroll} !==
           {reference.off_t,reference.off_s,reference.div_count,reference.hold_count,
            reference.hold_empty,reference.divider_last,reference.title_changed_q,
            reference.singer_changed_q,reference.done_toggle,reference.completed_width,
            reference.completed_kind,reference.completed_scroll} ||
           dut.title_limit!==({22'd0,reference.wt}+BOX_W-1) ||
           dut.singer_limit!==({22'd0,reference.ws}+BOX_W-1) ||
           dut.title_wide!==(reference.wt>BOX_W) || dut.singer_wide!==(reference.ws>BOX_W)) begin
            $display("TEST_FAIL marquee id=%0d width=%0d step=%0d time=%0t off=%0d/%0d singer=%0d/%0d",
                ID,i,j,$time,dut.off_t,reference.off_t,dut.off_s,reference.off_s);$finish;
        end
    end
    initial begin
FORCES
        seed=7113+ID;repeat(5) tick;rn=1;repeat(5) tick;
        for(i=0;i<1024;i=i+1) begin
            inject_work=1;inject_done=1;inject_kind=1;inject_width=i;tick;
            inject_kind=2;inject_width=1023-i;tick;
            inject_done=0;inject_work=0;
            // Width boundaries, 10-bit overflow, and both wrap limits.
            for(j=0;j<10;j=j+1) begin
                limit=j<5 ? i+BOX_W-1 : 1023-i+BOX_W-1;
                case(j%5)
                0:pos=0;1:pos=1023;2:pos=limit-1;3:pos=limit;4:pos=limit+1;
                endcase
                deposit_step(pos);
            end
        end
        done[0]=1;
        // Natural progression exercises simultaneous title/singer wraps,
        // sample gaps, exact hold lengths, and unreachable (>1023) limits.
        for(i=0;i<8;i=i+1) begin
            inject_work=1;inject_done=1;inject_kind=1;
            inject_width=(i==7) ? 1023 : BOX_W+i+1;tick;
            inject_kind=2;inject_width=BOX_W+i+3;tick;
            inject_done=0;inject_work=0;
            for(j=0;j<32000;j=j+1) begin stb=(j%7!=0);tick;end
        end
        done[1]=1;
        for(i=0;i<100000;i=i+1) begin
            stb=$random(seed);inject_width=$random(seed);inject_kind=$random(seed);
            inject_work=($random(seed)&3)!=0;inject_done=$random(seed);
            inject_error=($random(seed)&7)==0;inject_cancel=($random(seed)&7)==0;
            if(i%17==0) tf=$random(seed);
            if(i%19==0) sc=$random(seed);
            if(i%31==0) begin tc=$random(seed);sf=$random(seed);end
            rn=i%997!=0;tick;
        end
        done[2]=1;
    end
endmodule
module tb_marquee_equivalence;
    wire [26:0] done;
CASES
    initial begin
        wait(done[0]&&done[3]&&done[6]&&done[9]&&done[12]&&done[15]&&done[18]&&done[21]&&done[24]);
        $display("SCENARIO_PASS MARQUEE-all-widths-and-offset-boundaries");
        wait(done[1]&&done[4]&&done[7]&&done[10]&&done[13]&&done[16]&&done[19]&&done[22]&&done[25]);
        $display("SCENARIO_PASS MARQUEE-cadence-hold-and-overflow");
        wait(&done);$display("SCENARIO_PASS MARQUEE-random-completion-reset-priority");
        $display("TEST_PASS");$finish;
    end
    initial begin #6000000;$display("TEST_FAIL marquee timeout");$finish;end
endmodule
`default_nettype wire
'''
variants = [(0,2,3),(1,2,3),(160,2,3),(288,2,3),(448,2,3),(1024,2,3),(-1,2,3),(448,1,0),(448,1200,24000)]
cases = '\n'.join(f'    marquee_case #(.BOX_W({w}),.SPP({s}),.HOLD_N({h}),.ID({n})) c{n}(.done(done[{3*n+2}:{3*n}]));'
                  for n,(w,s,h) in enumerate(variants))
(ROOT / 'tb/tb_marquee_equivalence.v').write_text(template.replace('INSTANCES', instances)
    .replace('FORCES', force_lines).replace('CASES', cases))
