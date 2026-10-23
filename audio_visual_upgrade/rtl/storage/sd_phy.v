`default_nettype none
// Group 2: shared SD command transport, serial CRC7, single SPI engine.
module sd_phy #(
    parameter integer CLK_HZ            = 50000000,
    parameter integer INIT_SCK_HZ       = 400000,
    // 数据阶段 SCK 目标频率。
    //   ★ 2026-09-26 板上实测：25MHz 采样裕量不足（详见 storage_top.v 同名参数的说明），
    //     默认改用 12.5MHz（半周期 40ns）。本模块单独使用/被其它顶层集成时也吃这个默认值。
    parameter integer DATA_SCK_HZ       = 12500000,
    parameter integer POLL_TIMEOUT_MS   = 1000,
    parameter integer WATCHDOG_MS       = 2000,
    parameter integer SECTOR_TIMEOUT_MS = 250,
    parameter integer RESP_MAX_BYTES    = 16,
    // CMD0 之前的 0xFF 字节数（冲块，见 sd_init_spi.v 里的说明）；板上默认 520
    parameter integer PWR_BYTES         = 520,
    parameter         REQUIRE_SDHC      = 1'b1,
    parameter         CRC_ON            = 1'b0
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 初始化 ----
    input  wire        init_start,   // 单周期脉冲
    output wire        init_busy,
    output reg        init_done,    // 保持
    output reg        init_fail,    // 保持
    output reg [3:0]  init_err,     // sd_init_spi 原始细码
    output reg [31:0] card_ocr,
    output reg        card_sdhc,

    // ---- 扇区读服务 ----
    input  wire        sec_req,      // 单周期脉冲；仅 sec_busy=0 时给出
    input  wire [31:0] sec_lba,
    output reg        sec_busy,
    output wire        sec_valid,
    output wire [7:0]  sec_data,
    input  wire        sec_ready,
    output reg        sec_done,     // 1 拍脉冲
    output reg [3:0]  sec_err,      // 0=OK 1=R1 2=令牌超时 3=CRC16 4=超时
    output reg [15:0] sec_crc_rx,
    output reg [15:0] sec_crc_calc,

    // ---- SD 卡引脚 ----
    output wire        sd_sck,
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input  wire        sd_miso
);
    // Shared command transport and one SPI byte engine. Init steps and read
    // phases retain distinct protocol decisions, but never duplicate execution.
    localparam [3:0] IDLE=0, POWER=1, COMMAND=2, RESPONSE=3, EXTRA=4,
        EVALUATE=5, READY=6, TOKEN=7, DATA=8, CRC=9, TAIL=10, FINISH=11, FAILED=12;
    localparam integer INIT_HALF=(CLK_HZ+2*INIT_SCK_HZ-1)/(2*INIT_SCK_HZ);
    localparam integer DATA_HALF=(CLK_HZ+2*DATA_SCK_HZ-1)/(2*DATA_SCK_HZ);
    localparam integer INIT_LIMIT=(CLK_HZ/1000)*WATCHDOG_MS;
    localparam integer POLL_LIMIT=(CLK_HZ/1000)*POLL_TIMEOUT_MS;
    localparam integer READ_LIMIT=(CLK_HZ/1000)*SECTOR_TIMEOUT_MS;
    reg [3:0] state;
    reg [2:0] step;
    reg reading, command_read;
    reg [39:0] tx_shift;
    reg [2:0] cmd_index, extra_left;
    reg [15:0] response_count, power_count;
    reg [7:0] r1;
    reg [31:0] extra, timer;
    reg [8:0] data_index;
    reg crc_index;
    reg [3:0] read_error;
    reg out_valid;
    reg [7:0] out_data;
    reg cs_n;
    reg request_pending;
    reg [31:0] pending_lba;

    function [39:0] init_head;
        input [2:0] s;
        begin
            case(s)
            0:init_head=40'h4000000000;
            1:init_head=40'h48000001aa;
            2:init_head=40'h7b00000001;
            3:init_head=40'h7700000000;
            4:init_head=40'h6940000000;
            default:init_head=40'h7a00000000;
            endcase
        end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] c0; input [7:0] d;
        reg [15:0] c; integer k;
        begin
            c=c0;
            for(k=7;k>=0;k=k-1) c=(c<<1)^((c[15]^d[k]) ? 16'h1021 : 16'd0);
            crc16_byte=c;
        end
    endfunction

    // CRC7 advances one bit per clk while each of the first five command
    // bytes is on the wire. Even HALF=1 leaves >=16 clocks per byte.
    reg [6:0] crc7;
    reg [7:0] crc_byte;
    reg [3:0] crc_bits;
    wire byte_busy, byte_done;
    wire [7:0] byte_rx;
    reg byte_active, byte_abort;
    wire byte_want=(state==POWER || state==COMMAND || state==RESPONSE ||
        state==EXTRA || state==TOKEN || state==CRC || state==TAIL ||
        (state==DATA && !out_valid));
    wire byte_start=byte_want && !byte_busy && !byte_done && !byte_active && !byte_abort;
    wire [7:0] byte_tx=state==COMMAND ? (cmd_index==5 ? {crc7,1'b1} : tx_shift[39:32]) : 8'hff;
    wire [15:0] half_period=reading ? DATA_HALF : INIT_HALF;
    sd_spi_byte u_byte(
        .clk(clk),.rst_n(rst_n && !byte_abort),.start(byte_start),
        .tx_data(byte_tx),.half_period(half_period),.busy(byte_busy),.done(byte_done),
        .rx_data(byte_rx),.sck(sd_sck),.mosi(sd_mosi),.miso(sd_miso)
    );
    assign sd_cs_n=cs_n;
    assign sec_valid=out_valid;
    assign sec_data=out_data;
    assign init_busy=!reading && state!=IDLE && state!=READY && state!=FAILED;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; step<=0; reading<=0; command_read<=0;
            tx_shift<=0; cmd_index<=0; extra_left<=0; response_count<=0; power_count<=0;
            r1<=0; extra<=0; timer<=0; data_index<=0; crc_index<=0; read_error<=0;
            out_valid<=0; out_data<=0; cs_n<=1;
            request_pending<=0; pending_lba<=0;
            crc7<=0; crc_byte<=0; crc_bits<=0; byte_active<=0; byte_abort<=0;
            init_done<=0; init_fail<=0; init_err<=0; card_ocr<=0; card_sdhc<=0;
            sec_busy<=0; sec_done<=0; sec_err<=0; sec_crc_rx<=0; sec_crc_calc<=0;
        end else begin
            sec_done<=0; byte_abort<=0;
            if(byte_start) byte_active<=1;
            if(byte_done || byte_abort) byte_active<=0;
            if(out_valid && sec_ready) out_valid<=0;
            if(sec_req) begin request_pending<=1; pending_lba<=sec_lba; end
            if(state==IDLE || state==READY || state==FAILED || state==FINISH) timer<=0;
            else timer<=timer+1'b1;
            if(byte_start && state==COMMAND && cmd_index<5) begin
                crc_byte<=tx_shift[39:32]; crc_bits<=8;
            end else if(crc_bits!=0) begin
                crc7<={crc7[5:0],1'b0} ^ ((crc7[6]^crc_byte[7]) ? 7'h09 : 7'd0);
                crc_byte<={crc_byte[6:0],1'b0}; crc_bits<=crc_bits-1'b1;
            end

            case(state)
            IDLE: if(init_start) begin
                state<=POWER; power_count<=0; step<=0; timer<=0; reading<=0;
                init_done<=0; init_fail<=0; init_err<=0; request_pending<=0;
            end
            POWER: if(byte_done) begin
                if(power_count==PWR_BYTES-1) begin
                    tx_shift<=init_head(0); cmd_index<=0; crc7<=0;
                    command_read<=0; cs_n<=0; state<=COMMAND;
                end else power_count<=power_count+1'b1;
            end
            COMMAND: if(byte_done) begin
                if(cmd_index==5) begin response_count<=0; state<=RESPONSE; end
                else begin tx_shift<={tx_shift[31:0],8'hff}; cmd_index<=cmd_index+1'b1; end
            end
            RESPONSE: if(byte_done) begin
                if(!byte_rx[7]) begin
                    r1<=byte_rx;
                    if(command_read) begin
                        if(byte_rx==0) state<=TOKEN;
                        else begin read_error<=1; cs_n<=1; state<=FINISH; end
                    end else if(step==1 || step==5) begin
                        extra_left<=4; extra<=0; state<=EXTRA;
                    end else state<=EVALUATE;
                end else if(response_count+1>=RESP_MAX_BYTES) begin
                    cs_n<=1;
                    if(reading) begin read_error<=1; state<=FINISH; end
                    else begin init_err<=4; init_fail<=1; state<=FAILED; end
                end else response_count<=response_count+1'b1;
            end
            EXTRA: if(byte_done) begin
                extra<={extra[23:0],byte_rx}; extra_left<=extra_left-1'b1;
                if(extra_left==1) state<=EVALUATE;
            end
            EVALUATE: begin
                // Default schedules the next init command on the following
                // cycle; the previous step's R1/R7 remains stable for decisions.
                state<=COMMAND; cmd_index<=0; crc7<=0;
                case(step)
                0: if(r1==1) begin step<=1; tx_shift<=init_head(1); end
                   else begin init_err<=1; state<=FAILED; end
                1: if(r1[2]) begin init_err<=2; state<=FAILED; end
                   else if(r1!=1) begin init_err<=3; state<=FAILED; end
                   else if(extra[11:8]==0) begin init_err<=10; state<=FAILED; end
                   else if(extra[7:0]!=8'haa) begin init_err<=11; state<=FAILED; end
                   else begin step<=CRC_ON ? 2 : 3; tx_shift<=init_head(CRC_ON ? 2 : 3); end
                2: if(r1[2]) begin init_err<=4; state<=FAILED; end
                   else begin step<=3; tx_shift<=init_head(3); end
                3: if(r1[2]) begin init_err<=4; state<=FAILED; end
                   else begin step<=4; tx_shift<=init_head(4); end
                4: if(r1[2]) begin init_err<=4; state<=FAILED; end
                   else if(r1[0]) begin
                       if(timer>=POLL_LIMIT) begin init_err<=5; state<=FAILED; end
                       else begin step<=3; tx_shift<=init_head(3); end
                   end else begin step<=5; tx_shift<=init_head(5); end
                5: begin
                    card_ocr<=extra; card_sdhc<=extra[30];
                    if(!extra[31] || extra[23:15]==0) begin init_err<=6; state<=FAILED; end
                    else if(REQUIRE_SDHC && !extra[30]) begin init_err<=7; state<=FAILED; end
                    else begin init_done<=1; cs_n<=1; state<=READY; end
                end
                default: begin init_err<=8; state<=FAILED; end
                endcase
            end
            READY: if((sec_req || request_pending) && init_done) begin
                reading<=1; command_read<=1; sec_busy<=1; sec_err<=0; read_error<=0;
                timer<=0; tx_shift<={8'h51,sec_req ? sec_lba : pending_lba};
                request_pending<=0; cmd_index<=0; crc7<=0; cs_n<=0;
                out_valid<=0; sec_crc_rx<=0; sec_crc_calc<=0; state<=COMMAND;
            end
            TOKEN: if(byte_done && byte_rx==8'hfe) begin data_index<=0; state<=DATA; end
            DATA: if(byte_done) begin
                out_data<=byte_rx; out_valid<=1;
                sec_crc_calc<=crc16_byte(sec_crc_calc,byte_rx);
                if(data_index==511) begin crc_index<=0; state<=CRC; end
                else data_index<=data_index+1'b1;
            end
            CRC: if(byte_done) begin
                if(!crc_index) begin sec_crc_rx[15:8]<=byte_rx; crc_index<=1; end
                else begin sec_crc_rx[7:0]<=byte_rx; state<=TAIL; end
            end
            TAIL: if(byte_done) begin
                cs_n<=1;
                if(CRC_ON && sec_crc_rx!=sec_crc_calc) read_error<=3;
                state<=FINISH;
            end
            FINISH: if(!out_valid && !byte_busy && !byte_active && !byte_abort) begin
                sec_busy<=0; sec_done<=1; sec_err<=read_error; reading<=0; state<=READY;
            end
            FAILED: begin cs_n<=1; init_fail<=1; end
            default: begin init_err<=8; init_fail<=1; cs_n<=1; state<=FAILED; end
            endcase
            if(init_busy && timer>=INIT_LIMIT) begin
                init_err<=8; init_fail<=1; cs_n<=1; byte_abort<=1; state<=FAILED;
            end
            if(sec_busy && state!=FINISH && timer>=READ_LIMIT) begin
                read_error<=4; cs_n<=1; byte_abort<=1; state<=FINISH;
            end
        end
    end
endmodule
`default_nettype wire
