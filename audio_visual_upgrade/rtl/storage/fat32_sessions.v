`default_nettype none
// One file execution datapath, two persistent sessions. Each session owns a
// complete 512B mailbox in one shared 1Kx8 BRAM. Ownership survives scheduling;
// downstream backpressure cannot retain the SD bus inside a material sector.
module fat32_sessions #(
    parameter integer CLK_HZ=50000000, WATCHDOG_MS=2000, LO_STALL_MS=500
)(
    input wire clk, rst_n,
    input wire lo_start, input wire [31:0] lo_cluster, lo_size,
    input wire hi_start, input wire [31:0] hi_cluster, hi_size,
    input wire lo_want, hi_want, hi_refill,
    output reg lo_busy, hi_busy, lo_done, hi_done,
    output reg [3:0] lo_err, hi_err,
    output wire lo_valid, hi_valid, output wire [7:0] lo_data, hi_data,
    input wire lo_ready, hi_ready,
    input wire [31:0] data_lba, total_clusters, input wire [3:0] spc_shift,
    output reg sec_req, output reg [31:0] sec_lba,
    input wire sec_busy, sec_valid, sec_done, input wire [7:0] sec_data,
    input wire [3:0] sec_err, output wire sec_ready,
    output reg chain_req, output wire [31:0] chain_cluster,
    input wire chain_busy, chain_done, input wire [3:0] chain_err,
    input wire [31:0] chain_next,
    output wire [1:0] owner, output wire safe_idle, output wire lo_stall
);
    localparam [3:0] IDLE=0, LAUNCH=1, SECTOR=2, CHAIN=3, DRAIN=4,
        SHIFT=5, BASE=6, OFFSET=7, SEND=8;
    localparam integer WD_LIMIT=(CLK_HZ/1000)*WATCHDOG_MS;
    localparam integer STALL_LIMIT=(CLK_HZ/1000)*LO_STALL_MS;
    reg [3:0] state;
    reg active, last;
    reg [31:0] cluster [0:1];
    reg [31:0] remain [0:1];
    reg [6:0] index [0:1];
    reg [1:0] need_chain, filled;
    reg [8:0] end_pos [0:1];
    reg [8:0] read_pos [0:1];
    reg [8:0] write_pos;
    reg [3:0] shift_left;
    reg [31:0] watchdog, stall_count;
    reg [1:0] out_valid;
    reg [7:0] out_lo, out_hi;
    reg read_pending, read_owner;
    wire [1:0] busy_vec={hi_busy,lo_busy};
    wire lo_eligible=lo_busy && remain[0]!=0 && !filled[0] && !out_valid[0] &&
        !(read_pending && !read_owner) && lo_want;
    wire hi_eligible=hi_busy && remain[1]!=0 && !filled[1] && !out_valid[1] &&
        !(read_pending && read_owner) && hi_want;
    wire choose_hi=hi_eligible && (hi_refill || !lo_eligible || !last);
    wire can_choose=(lo_eligible || hi_eligible) && !sec_busy && !chain_busy;
    wire [31:0] active_remain=active ? remain[1] : remain[0];
    wire [31:0] active_cluster=active ? cluster[1] : cluster[0];
    wire [6:0] active_index=active ? index[1] : index[0];
    wire full_sector=(active_remain[31:9]!=0);
    // Update a file's 32-bit length once per sector, using one 23-bit decrement.
    // A partial last sector ends at size[8:0]-1; trailing SD bytes stay private.
    wire [31:0] next_remain=full_sector ?
        {active_remain[31:9]-23'd1,active_remain[8:0]} : 32'd0;
    wire [8:0] sector_end=full_sector ? 9'd511 : active_remain[8:0]-9'd1;
    // One address adder and a one-bit shifter, reused over several clocks.
    // sec_lba is private scratch until SEND asserts sec_req.
    wire [31:0] address_a=(state==LAUNCH) ? active_cluster : sec_lba;
    wire [31:0] address_b=(state==LAUNCH) ? 32'hfffffffe :
        (state==BASE) ? data_lba : {25'd0,active_index};
    wire [31:0] address_sum=address_a+address_b;
    assign chain_cluster=cluster[active];
    assign sec_ready=1'b1; // a whole empty sector mailbox was reserved at launch
    assign owner=(state==IDLE) ? 2'd0 : (active ? 2'd1 : 2'd2);
    assign safe_idle=(state==IDLE) && !sec_req && !chain_req;
    assign lo_stall=(stall_count>=STALL_LIMIT);
    assign lo_valid=out_valid[0]; assign hi_valid=out_valid[1];
    assign lo_data=out_lo; assign hi_data=out_hi;

    // A single synchronous read port feeds two small consumer-owned skids.
    // Only completed sectors are published; CRC/error responses stay with active.
    wire read_hi=filled[1] && !out_valid[1];
    wire read_lo=filled[0] && !out_valid[0];
    wire read_fire=!read_pending && (read_hi || read_lo);
    wire read_sel=read_hi;
    wire [9:0] ram_raddr={read_sel,read_pos[read_sel]};
    wire [7:0] ram_data;
    wire ram_we=(state==SECTOR) && sec_valid;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) u_sectors (
        .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(ram_we),.rsta(1'b0),.bea(1'b0),
        .addra({active,write_pos}),.dia(sec_data),.doa(),
        .clkb(clk),.ceb(read_fire),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .addrb(ram_raddr),.dib(8'd0),.dob(ram_data)
    );
    integer s;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; active<=0; last<=0; need_chain<=0; filled<=0;
            lo_busy<=0; hi_busy<=0; lo_done<=0; hi_done<=0; lo_err<=0; hi_err<=0;
            sec_req<=0; sec_lba<=0; chain_req<=0;
            write_pos<=0; shift_left<=0; watchdog<=0; stall_count<=0;
            out_valid<=0; out_lo<=0; out_hi<=0;
            read_pending<=0; read_owner<=0;
            for(s=0;s<2;s=s+1) begin
                cluster[s]<=0; remain[s]<=0; index[s]<=0; end_pos[s]<=0; read_pos[s]<=0;
            end
        end else begin
            lo_done<=0; hi_done<=0; sec_req<=0; chain_req<=0;
            if(!lo_busy || !lo_want || (state!=IDLE && !active)) stall_count<=0;
            else if(stall_count<STALL_LIMIT) stall_count<=stall_count+1'b1;
            if(state==IDLE) watchdog<=0;
            else if(watchdog<WD_LIMIT) watchdog<=watchdog+1'b1;

            if(out_valid[0] && lo_ready) out_valid[0]<=0;
            if(out_valid[1] && hi_ready) out_valid[1]<=0;
            read_pending<=read_fire;
            if(read_fire) begin
                read_owner<=read_sel;
                read_pos[read_sel]<=read_pos[read_sel]+1'b1;
                if(read_pos[read_sel]==end_pos[read_sel]) filled[read_sel]<=0;
            end
            if(read_pending) begin
                out_valid[read_owner]<=1;
                if(read_owner) out_hi<=ram_data; else out_lo<=ram_data;
            end
            for(s=0;s<2;s=s+1) begin
                if(busy_vec[s] && remain[s]==0 && !filled[s] && !out_valid[s] &&
                   !(read_pending && read_owner==s) && !(state!=IDLE && active==s)) begin
                    if(s==0) begin lo_busy<=0; lo_done<=1; end
                    else begin hi_busy<=0; hi_done<=1; end
                end
            end
            if(lo_start && !lo_busy) begin
                cluster[0]<=lo_cluster; remain[0]<=lo_size; index[0]<=0;
                need_chain[0]<=0; lo_busy<=1; lo_err<=0;
            end
            if(hi_start && !hi_busy) begin
                cluster[1]<=hi_cluster; remain[1]<=hi_size; index[1]<=0;
                need_chain[1]<=0; hi_busy<=1; hi_err<=0;
            end

            case(state)
            IDLE: if(can_choose) begin active<=choose_hi; state<=LAUNCH; end
            LAUNCH: begin
                watchdog<=0;
                if(need_chain[active]) begin chain_req<=1; state<=CHAIN; end
                else begin
                    sec_lba<=address_sum; shift_left<=spc_shift; state<=SHIFT;
                end
            end
            SHIFT: if(shift_left!=0) begin
                sec_lba<={sec_lba[30:0],1'b0}; shift_left<=shift_left-1'b1;
            end else state<=BASE;
            BASE: begin sec_lba<=address_sum; state<=OFFSET; end
            OFFSET: begin sec_lba<=address_sum; state<=SEND; end
            SEND: begin sec_req<=1; write_pos<=0; state<=SECTOR; end
            SECTOR: begin
                if(ram_we) write_pos<=write_pos+1'b1;
                if(sec_done) begin
                    if(sec_err!=0) begin
                        remain[active]<=0;
                        if(active) hi_err<=sec_err==3 ? 4'd5 : sec_err==4 ? 4'd4 : 4'd1;
                        else lo_err<=sec_err==3 ? 4'd5 : sec_err==4 ? 4'd4 : 4'd1;
                    end else begin
                        remain[active]<=next_remain;
                        end_pos[active]<=sector_end; read_pos[active]<=0;
                        filled[active]<=1;
                        if(index[active]==((7'd1<<spc_shift)-1'b1)) need_chain[active]<=1;
                        else index[active]<=index[active]+1'b1;
                    end
                    last<=active; state<=IDLE;
                end
            end
            CHAIN: if(chain_done) begin
                if(chain_err!=0 || chain_next<2 || chain_next>=32'h0ffffff7 ||
                   chain_next>=total_clusters+32'd2) begin
                    remain[active]<=0;
                    if(active) hi_err<=chain_err!=0 ? 4'd2 : 4'd3;
                    else lo_err<=chain_err!=0 ? 4'd2 : 4'd3;
                end else begin cluster[active]<=chain_next; index[active]<=0; need_chain[active]<=0; end
                last<=active; state<=IDLE;
            end
            // A watchdog never transfers a still-pending response to the other session.
            DRAIN: if(!sec_busy && !chain_busy) begin last<=active; state<=IDLE; end
            default: state<=IDLE;
            endcase
            if(state!=IDLE && state!=DRAIN && watchdog>=WD_LIMIT) begin
                remain[active]<=0; state<=DRAIN;
                if(active) hi_err<=4'd4; else lo_err<=4'd4;
            end
        end
    end
endmodule
`default_nettype wire
