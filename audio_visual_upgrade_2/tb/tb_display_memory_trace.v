`timescale 1ns/1ps
`default_nettype none
// Passive diagnostic wrapper. Reuse the original independent pixel checker;
// do not change the controller, device model, stimulus or pass criteria.
module tb_display_memory_trace;
    parameter integer LINES=16,COVER_LINES=8;
    parameter real SDR_HALF=5.0,SDR_SHIFT=5.0;
    tb_display_memory #(.LINES(LINES),.COVER_LINES(COVER_LINES),.PHYSICAL(1),
        .SDR_HALF(SDR_HALF),.SDR_SHIFT(SDR_SHIFT)) test();

    integer cycles=0,issued=0,returned=0;
    reg started=0;
    reg [20:0] read_addresses[0:63];
    initial $display("PHY_TRACE_SCOPE half_ns=%0.3f shift_ns=%0.3f diagnostic_only=1",SDR_HALF,SDR_SHIFT);
    always @(posedge test.cs) begin
        if(test.app_rd) started=1;
        if(started && cycles<80) begin
            cycles=cycles+1;
            $display("PHY_CLOCK t=%0.3f rd_req=%b addr=%h rdv=%b rd=%h dq=%h",$realtime,test.app_rd,test.ra,test.rdv,test.rd,test.physical.phy.SDR_DQ);
            if(test.app_rd && issued<64) begin
                read_addresses[issued]=test.ra; issued=issued+1;
            end
            if(test.rdv && returned<issued) begin
                $display("PHY_RETURN t=%0.3f index=%0d addr=%h got=%h exp=%h",$realtime,returned,read_addresses[returned],test.rd,test.word_at(read_addresses[returned]));
                returned=returned+1;
            end
        end
    end
    always @(posedge test.physical.phy.SDRAM_CLK) if(started && cycles<80)
        $display("PHY_COMMAND t=%0.3f cmd=%b%b%b bank=%h addr=%h dm=%h dq=%h",$realtime,test.physical.phy.SDR_RAS,test.physical.phy.SDR_CAS,test.physical.phy.SDR_WE,test.physical.phy.SDR_BA,test.physical.phy.SDR_ADDR,test.physical.phy.SDR_DM,test.physical.phy.SDR_DQ);
    always @(test.physical.phy.SDR_DQ) if(started && cycles<80)
        $display("PHY_DQ t=%0.3f dq=%h",$realtime,test.physical.phy.SDR_DQ);
endmodule
`default_nettype wire
