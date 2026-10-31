`timescale 1ns/1ps
`default_nettype none
// Exercise the actual source publication schedule: all payload fields and the
// toggle change together on an SDR rising edge, at each of four pixel phases.
module tb_timing_descriptors;
    reg cp=0, cs=0;
    always #20 cp=~cp;
    always #5 cs=~cs;
    reg rn=0, dt=0, v=0;
    reg [15:0] fc=0, cnt=0;
    wire [7:0] captured;
    integer checks=0, publishes=0, phase, i, j, base_fc, b;
    reg [7:0] expected;
    layer_text_aa #(.FIVE_LINES(1),.CLK_HZ(100000000)) dut(
        .clk_pix(cp),.rst_pix_n(rn),.hs(1'b1),.vs(1'b1),.de(1'b0),
        .en(1'b1),.en_ttl(1'b1),.dout(),.dout_vld(),.alpha(),
        .gap_cnt(),.on_cnt(),.ttl_off(),.clk_sdr(cs),.rst_sdr_n(rn),
        .played(24'd0),.cur_fc(fc),.nxt_fc(fc),.n3_fc(fc),
        .cur_cnt(cnt),.nxt_cnt(cnt),.n3_cnt(cnt),
        .cur_vld(v),.nxt_vld(v),.n3_vld(v),
        .prev2_fc(fc),.prev2_cnt(cnt),.prev_fc(fc),.prev_cnt(cnt),
        .n4_fc(fc),.n4_cnt(cnt),.prev2_vld(v),.prev_vld(v),.n4_vld(v),
        .song_clear(1'b0),.off_px(6'd0),.desc_tgl(dt),.samp_stb(1'b0),
        .ttl_fc(fc),.ttl_cnt(cnt),.sgr_fc(fc),.sgr_cnt(cnt),
        .ttl_vld(v),.sgr_vld(v),.px_req(),.px_addr(),.px_len(),
        .px_ack(1'b0),.px_done(1'b0),.px_data(32'd0),.px_valid(1'b0));
    assign captured={dut.s_tv,dut.s_sv,dut.s_v0,dut.s_v1,dut.s_v2,
                     dut.s_p2v,dut.s_pv,dut.s_f4v};
    // Wide integer arithmetic is the independent reference. In particular,
    // no truncation of the input count or first-character index is permitted.
    function legal;
        input integer f,n,limit;
        begin legal=(n>0 && n<=limit && f+n<=488); end
    endfunction
    task publish;
        input integer f,n,valid_in,p;
        begin
            @(negedge cp);
            repeat(p+1) @(posedge cs);
            fc<=f;cnt<=n;v<=valid_in;dt<=~dt;
            expected={{2{valid_in && legal(f,n,24)}},
                      {6{valid_in && legal(f,n,19)}}};
            publishes=publishes+1;
            repeat(5) @(negedge cp);
            if(captured!==expected || dut.s_fc0!==fc[8:0] ||
               dut.s_tfc!==fc[8:0] || dut.s_cnt0!==cnt[4:0] ||
               dut.s_tcnt!==cnt[4:0]) begin
                $display("TEST_FAIL descriptor f=%0d n=%0d v=%0d phase=%0d got=%b expected=%b",f,n,valid_in,p,captured,expected);
                $finish;
            end
        end
    endtask
    // Also check at the exact commit, not only after eventual settling.
    always @(posedge cp) if(rn && (dut.ds[0]^dut.ds[1])) begin
        #1;
        if(captured!==expected) begin
            $display("TEST_FAIL descriptor commit got=%b expected=%b",captured,expected);
            $finish;
        end
        checks=checks+1;
    end
    initial begin
        repeat(5) @(negedge cp);rn=1;
        for(phase=0;phase<4;phase=phase+1) begin
            for(i=0;i<10;i=i+1) begin
                case(i)
                0:base_fc=0;1:base_fc=464;2:base_fc=469;3:base_fc=470;
                4:base_fc=487;5:base_fc=488;6:base_fc=489;
                7:base_fc=511;8:base_fc=512;default:base_fc=65535;
                endcase
                for(j=0;j<=32;j=j+1) publish(base_fc,j,1,phase);
            end
        end
        $display("SCENARIO_PASS TIMING-desc-boundary-phases");
        for(b=9;b<16;b=b+1) publish(1<<b,1,1,b%4);
        for(b=5;b<16;b=b+1) publish(0,(1<<b)+1,1,b%4);
        publish(0,19,0,0);publish(464,24,0,1);publish(0,19,1,2);
        $display("SCENARIO_PASS TIMING-desc-highbits-valid");
        @(negedge cp);rn=0;
        repeat(5) @(negedge cp);
        if(captured!==0) begin $display("TEST_FAIL reset descriptors");$finish;end
        v=0;dt=0;rn=1;
        publish(469,19,1,3);
        if(checks!=publishes) begin
            $display("TEST_FAIL commits=%0d publishes=%0d",checks,publishes);$finish;
        end
        $display("SCENARIO_PASS TIMING-desc-reset-recovery");
        $display("Descriptor commits checked: %0d",checks);
        $display("TEST_PASS");$finish;
    end
    initial begin #1000000;$display("TEST_FAIL watchdog");$finish;end
endmodule
`default_nettype wire
