`timescale 1ns/1ps
`default_nettype none
module tb_cover_scale_rows;
    reg cp=0,cs=0,rn=0;
    always #20 cp=~cp;
    initial begin #3; forever #5 cs=~cs; end
    reg [16:0] line_cycle=0;
    reg [15:0] video_line=0;
    wire line_end=(line_cycle==17'd79);
    wire video_de=(line_cycle>=17'd16 && line_cycle<17'd20);
    wire [15:0] pixel_x=video_de ? line_cycle[15:0]-16'd16 : 16'd0;
    wire [66:0] scan_state={line_end,1'b0,1'b1,line_cycle,video_line,pixel_x,15'd1};
    always @(posedge cp) if(rn) begin
        if(line_end) begin line_cycle<=0; video_line<=video_line+1'b1; end
        else line_cycle<=line_cycle+1'b1;
    end

    wire req;
    wire [20:0] addr;
    wire [15:0] len;
    wire [23:0] pixel;
    wire pixel_valid;
    reg ack=0,done=0,valid=0;
    reg [31:0] data=0;
    wire cmd_valid,slot_free,next_bank;
    wire [20:0] cmd_addr;
    wire [15:0] cmd_words;
    layer_bg #(.MAX_W(8),.LAT(7),.H_ACT_DLY(17),.V_ACT_DLY(2),
               .V_ACT_LIN(8),.SHARED_RASTER(1),.SCALE(1)) dut (
        .clk_pix(cp),.rst_pix_n(rn),.hs(1'b0),.vs(1'b0),.de(video_de),.en(1'b1),
        .win_x(16'd0),.win_y(16'd1),.win_w(16'd4),.win_h(16'd5),
        .img_w(16'd4),.img_h(16'd4),.words_per_row(16'd3),.slot_base(21'd100),
        .dout(pixel),.dout_vld(pixel_valid),.underrun_cnt(),.stall_cnt(),
        .ferr_cnt(),.gap_cnt(),.idle(),.clk_sdr(cs),.rst_sdr_n(rn),
        .px_req(req),.px_addr(addr),.px_len(len),.px_ack(ack),.px_done(done),
        .px_data(data),.px_valid(valid),.scan_state(scan_state),
        .cmd_valid(cmd_valid),.slot_free(slot_free),.next_bank(next_bank),
        .cmd_addr(cmd_addr),.cmd_words(cmd_words),.cmd_ack(1'b0),
        .wr_take(1'b0),.wr_active(1'b0),.wr_done(1'b0),.wr_error(1'b0),
        .wr_en(1'b0),.wr_good(1'b0),.wr_addr(10'd0)
    );
    integer requests=0,word_index=0,source_row=0;
    reg sending=0;
    reg [7:0] row_byte=0;
    integer pixels [0:4];
    integer expected_row [0:4];
    integer display_row;
    integer i;
    reg [7:0] expected_byte;
    initial begin
        expected_row[0]=0; expected_row[1]=0; expected_row[2]=1;
        expected_row[3]=2; expected_row[4]=3;
        for(i=0;i<5;i=i+1) pixels[i]=0;
    end
    always @(negedge cs) if(rn) begin
        ack=0; done=0; valid=0;
        if(!sending && req) begin
            if(requests>=5) begin $display("TEST_FAIL extra row request"); $finish; end
            source_row=expected_row[requests];
            if(addr!==21'd100+source_row*3 || len!==16'd3) begin
                $display("TEST_FAIL row request %0d address=%0d expected=%0d",requests,addr,100+source_row*3);
                $finish;
            end
            row_byte=source_row+8'd1;
            requests=requests+1; word_index=0; sending=1; ack=1;
        end else if(sending) begin
            if(word_index<3) begin
                data={4{row_byte}}; valid=1; word_index=word_index+1;
            end else begin done=1; sending=0; end
        end
    end
    always @(posedge cp) if(rn && video_de && video_line>=16'd3 && video_line<16'd8) begin
        display_row=video_line-3;
        expected_byte=expected_row[display_row]+1;
        if(!pixel_valid || pixel!=={3{expected_byte}}) begin
            $display("TEST_FAIL display row=%0d x=%0d valid=%b pixel=%h expected=%0d",
                display_row,pixel_x,pixel_valid,pixel,expected_row[display_row]+1);
            $finish;
        end
        pixels[display_row]=pixels[display_row]+1;
    end
    initial begin
        repeat(5) @(negedge cp); rn=1;
        wait(video_line==16'd9);
        if(requests!=5) begin $display("TEST_FAIL row request count %0d",requests); $finish; end
        for(i=0;i<5;i=i+1) if(pixels[i]!=4) begin
            $display("TEST_FAIL row %0d pixel count %0d",i,pixels[i]); $finish;
        end
        $display("SCENARIO_PASS scale_vertical_address_and_pixels");
        $display("TEST_PASS"); $finish;
    end
    initial begin #1000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
