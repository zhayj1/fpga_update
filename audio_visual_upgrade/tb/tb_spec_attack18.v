`timescale 1ns/1ps
`default_nettype none
module tb_spec_attack18;
    reg clk=0, rst_n=0, band_stb=0;
    reg [4:0] band_idx=0;
    reg [7:0] band_level=0;
    reg [5:0] sensitivity=16;
    wire analysis_stb, hit;
    wire [4:0] hit_band;
    wire [12:0] flux, threshold;
    wire [15:0] hit_count;
    always #20 clk=~clk;

    spec_attack18 dut(
        .clk(clk), .rst_n(rst_n), .band_stb(band_stb),
        .band_idx(band_idx), .band_level(band_level),
        .sensitivity(sensitivity), .analysis_stb(analysis_stb),
        .hit(hit), .hit_band(hit_band), .flux(flux),
        .threshold(threshold), .hit_count(hit_count));

    integer history [0:17][0:3];
    integer current [0:17];
    integer expected_flux, expected_best, best_delta;
    integer frames=0, hits=0;
    integer i,j,delta,mean;
    task clear_model;
        begin
            for(i=0;i<18;i=i+1) begin
                current[i]=0;
                for(j=0;j<4;j=j+1) history[i][j]=0;
            end
            frames=0; hits=0;
        end
    endtask

    task send_frame;
        input integer band_a, level_a, band_b, level_b;
        input integer expected_hit, expected_hit_band;
        integer n,k;
        begin
            expected_flux=0; expected_best=0; best_delta=0;
            for(n=0;n<18;n=n+1) begin
                current[n]=0;
                if(n==band_a) current[n]=level_a;
                if(n==band_b) current[n]=level_b;
                mean=(history[n][0]+history[n][1]+history[n][2]+history[n][3])/4;
                delta=(current[n]>mean)?current[n]-mean:0;
                expected_flux=expected_flux+delta;
                if(delta>best_delta) begin best_delta=delta;expected_best=n;end
                @(negedge clk);
                band_stb=1; band_idx=n; band_level=current[n];
                @(negedge clk); band_stb=0;
                if(n<17) repeat(2) @(negedge clk);
            end
            @(posedge analysis_stb);
            #1;
            if(flux!==expected_flux) begin
                $display("TEST_FAIL frame=%0d flux got=%0d expected=%0d",frames,flux,expected_flux);$finish;
            end
            if(hit!==expected_hit) begin
                $display("TEST_FAIL frame=%0d hit=%b expected=%0d flux=%0d threshold=%0d",frames,hit,expected_hit,flux,threshold);$finish;
            end
            if(hit && (hit_band!==expected_hit_band || hit_band!==expected_best)) begin
                $display("TEST_FAIL frame=%0d hit band=%0d expected=%0d model=%0d",frames,hit_band,expected_hit_band,expected_best);$finish;
            end
            if(hit) hits=hits+1;
            if(hit_count!==hits) begin
                $display("TEST_FAIL frame=%0d hits=%0d expected=%0d",frames,hit_count,hits);$finish;
            end
            for(n=0;n<18;n=n+1) begin
                for(k=3;k>0;k=k-1) history[n][k]=history[n][k-1];
                history[n][0]=current[n];
            end
            frames=frames+1;
            @(posedge clk); #1;
            if(analysis_stb!==0 || hit!==0) begin
                $display("TEST_FAIL analysis/hit pulse length frame=%0d",frames);$finish;
            end
        end
    endtask

    initial begin
        clear_model();
        repeat(4) @(negedge clk); rst_n=1;
        send_frame(-1,0,-1,0,0,0);
        send_frame(10,80,17,200,1,17);
        $display("SCENARIO_PASS positive_flux_best_band");
        send_frame(10,80,17,200,0,0);
        send_frame(-1,0,-1,0,0,0);
        $display("SCENARIO_PASS sustained_and_reverse_no_retrigger");
        send_frame(8,230,-1,0,0,0);
        repeat(8) send_frame(-1,0,-1,0,0,0);
        send_frame(8,230,-1,0,1,8);
        $display("SCENARIO_PASS cooldown_180ms");
        @(negedge clk); rst_n=0;
        clear_model();
        repeat(3) @(negedge clk); rst_n=1;
        send_frame(-1,0,-1,0,0,0);
        send_frame(5,190,-1,0,1,5);
        $display("SCENARIO_PASS reset_history_and_cooldown");
        $display("TEST_PASS");$finish;
    end
    initial begin #2000000;$display("TEST_FAIL attack18 timeout frame=%0d",frames);$finish;end
endmodule
`default_nettype wire
