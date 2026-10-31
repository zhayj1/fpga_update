`timescale 1ns/1ps
`default_nettype none
module tb_geometry_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,hsf=0,vsf=0,seen=0,en=0;
reg [16:0] lc=0;reg [15:0] vl=0,xc=0;
reg [14:0] fid=0;
reg [15:0] wx=0,wy=0,ww=0,wh=0,iw=0,ih=0,stride=0;
wire [66:0] scan={hsf,vsf,seen,lc,vl,xc,fid};
reg [20:0] base=21'h10000;
wire [3:0] valid;
integer n,j,k,l,seed=32'h1ab47,checks=0;
layer_bg_reference #(.MAX_W(640),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(0)) m00 (.clk_pix(clk),.rst_pix_n(rst_n),.hs(1'b1),.vs(1'b1),.de(1'b1),.en(en),
.win_x(wx),.win_y(wy),.win_w(ww),.win_h(wh),.img_w(iw),.img_h(ih),.words_per_row(stride),
.slot_base(base),.dout(),.dout_vld(valid[0]),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),.idle(),
.clk_sdr(clk),.rst_sdr_n(rst_n),.px_req(),.px_addr(),.px_len(),.px_ack(1'b0),.px_done(1'b0),
.px_data(32'd0),.px_valid(1'b0),.scan_state(scan),.cmd_valid(),.slot_free(),.next_bank(),
.cmd_addr(),.cmd_words(),.cmd_ack(1'b0),.wr_take(1'b0),.wr_active(1'b0),.wr_done(1'b0),
.wr_error(1'b0),.wr_en(1'b0),.wr_good(1'b0),.wr_addr(10'd0));
layer_bg #(.MAX_W(640),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(0),.GEOMETRY_BITS(10)) m01 (.clk_pix(clk),.rst_pix_n(rst_n),.hs(1'b1),.vs(1'b1),.de(1'b1),.en(en),
.win_x(wx),.win_y(wy),.win_w(ww),.win_h(wh),.img_w(iw),.img_h(ih),.words_per_row(stride),
.slot_base(base),.dout(),.dout_vld(valid[1]),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),.idle(),
.clk_sdr(clk),.rst_sdr_n(rst_n),.px_req(),.px_addr(),.px_len(),.px_ack(1'b0),.px_done(1'b0),
.px_data(32'd0),.px_valid(1'b0),.scan_state(scan),.cmd_valid(),.slot_free(),.next_bank(),
.cmd_addr(),.cmd_words(),.cmd_ack(1'b0),.wr_take(1'b0),.wr_active(1'b0),.wr_done(1'b0),
.wr_error(1'b0),.wr_en(1'b0),.wr_good(1'b0),.wr_addr(10'd0));
layer_bg_reference #(.MAX_W(640),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(1)) m10 (.clk_pix(clk),.rst_pix_n(rst_n),.hs(1'b1),.vs(1'b1),.de(1'b1),.en(en),
.win_x(wx),.win_y(wy),.win_w(ww),.win_h(wh),.img_w(iw),.img_h(ih),.words_per_row(stride),
.slot_base(base),.dout(),.dout_vld(valid[2]),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),.idle(),
.clk_sdr(clk),.rst_sdr_n(rst_n),.px_req(),.px_addr(),.px_len(),.px_ack(1'b0),.px_done(1'b0),
.px_data(32'd0),.px_valid(1'b0),.scan_state(scan),.cmd_valid(),.slot_free(),.next_bank(),
.cmd_addr(),.cmd_words(),.cmd_ack(1'b0),.wr_take(1'b0),.wr_active(1'b0),.wr_done(1'b0),
.wr_error(1'b0),.wr_en(1'b0),.wr_good(1'b0),.wr_addr(10'd0));
layer_bg #(.MAX_W(640),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(1),.GEOMETRY_BITS(10)) m11 (.clk_pix(clk),.rst_pix_n(rst_n),.hs(1'b1),.vs(1'b1),.de(1'b1),.en(en),
.win_x(wx),.win_y(wy),.win_w(ww),.win_h(wh),.img_w(iw),.img_h(ih),.words_per_row(stride),
.slot_base(base),.dout(),.dout_vld(valid[3]),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),.idle(),
.clk_sdr(clk),.rst_sdr_n(rst_n),.px_req(),.px_addr(),.px_len(),.px_ack(1'b0),.px_done(1'b0),
.px_data(32'd0),.px_valid(1'b0),.scan_state(scan),.cmd_valid(),.slot_free(),.next_bank(),
.cmd_addr(),.cmd_words(),.cmd_ack(1'b0),.wr_take(1'b0),.wr_active(1'b0),.wr_done(1'b0),
.wr_error(1'b0),.wr_en(1'b0),.wr_good(1'b0),.wr_addr(10'd0));
task compare;
begin
 #1;
 if(m00.geometry_ok!==m01.geometry_ok) begin $display("TEST_FAIL geometry scale=0 signal=geometry_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.line_ok!==m01.line_ok) begin $display("TEST_FAIL geometry scale=0 signal=line_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.go_now!==m01.go_now) begin $display("TEST_FAIL geometry scale=0 signal=go_now n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.before_first!==m01.before_first) begin $display("TEST_FAIL geometry scale=0 signal=before_first n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.next_ok!==m01.next_ok) begin $display("TEST_FAIL geometry scale=0 signal=next_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.want_first!==m01.want_first) begin $display("TEST_FAIL geometry scale=0 signal=want_first n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.want_next!==m01.want_next) begin $display("TEST_FAIL geometry scale=0 signal=want_next n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.target_row!==m01.target_row) begin $display("TEST_FAIL geometry scale=0 signal=target_row n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.row_addr!==m01.row_addr) begin $display("TEST_FAIL geometry scale=0 signal=row_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.row_phase!==m01.row_phase) begin $display("TEST_FAIL geometry scale=0 signal=row_phase n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.next_addr!==m01.next_addr) begin $display("TEST_FAIL geometry scale=0 signal=next_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.min_row!==m01.min_row) begin $display("TEST_FAIL geometry scale=0 signal=min_row n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.expect_tag!==m01.expect_tag) begin $display("TEST_FAIL geometry scale=0 signal=expect_tag n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.issue!==m01.issue) begin $display("TEST_FAIL geometry scale=0 signal=issue n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.req_addr!==m01.req_addr) begin $display("TEST_FAIL geometry scale=0 signal=req_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.req_words!==m01.req_words) begin $display("TEST_FAIL geometry scale=0 signal=req_words n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.req_tag!==m01.req_tag) begin $display("TEST_FAIL geometry scale=0 signal=req_tag n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.req_toggle!==m01.req_toggle) begin $display("TEST_FAIL geometry scale=0 signal=req_toggle n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m00.dout_vld!==m01.dout_vld) begin $display("TEST_FAIL geometry scale=0 signal=dout_vld n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.geometry_ok!==m11.geometry_ok) begin $display("TEST_FAIL geometry scale=1 signal=geometry_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.line_ok!==m11.line_ok) begin $display("TEST_FAIL geometry scale=1 signal=line_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.go_now!==m11.go_now) begin $display("TEST_FAIL geometry scale=1 signal=go_now n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.before_first!==m11.before_first) begin $display("TEST_FAIL geometry scale=1 signal=before_first n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.next_ok!==m11.next_ok) begin $display("TEST_FAIL geometry scale=1 signal=next_ok n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.want_first!==m11.want_first) begin $display("TEST_FAIL geometry scale=1 signal=want_first n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.want_next!==m11.want_next) begin $display("TEST_FAIL geometry scale=1 signal=want_next n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.target_row!==m11.target_row) begin $display("TEST_FAIL geometry scale=1 signal=target_row n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.row_addr!==m11.row_addr) begin $display("TEST_FAIL geometry scale=1 signal=row_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.row_phase!==m11.row_phase) begin $display("TEST_FAIL geometry scale=1 signal=row_phase n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.next_addr!==m11.next_addr) begin $display("TEST_FAIL geometry scale=1 signal=next_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.min_row!==m11.min_row) begin $display("TEST_FAIL geometry scale=1 signal=min_row n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.expect_tag!==m11.expect_tag) begin $display("TEST_FAIL geometry scale=1 signal=expect_tag n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.issue!==m11.issue) begin $display("TEST_FAIL geometry scale=1 signal=issue n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.req_addr!==m11.req_addr) begin $display("TEST_FAIL geometry scale=1 signal=req_addr n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.req_words!==m11.req_words) begin $display("TEST_FAIL geometry scale=1 signal=req_words n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.req_tag!==m11.req_tag) begin $display("TEST_FAIL geometry scale=1 signal=req_tag n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.req_toggle!==m11.req_toggle) begin $display("TEST_FAIL geometry scale=1 signal=req_toggle n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 if(m10.dout_vld!==m11.dout_vld) begin $display("TEST_FAIL geometry scale=1 signal=dout_vld n=%0d vln=%0d lcnt=%0d wx/y/w/h=%0d,%0d,%0d,%0d",n,vl,lc,wx,wy,ww,wh);$finish;end
 @(posedge clk);#1;@(negedge clk);checks=checks+1;
end
endtask
initial begin
 repeat(4) @(negedge clk);rst_n=1;seen=1;en=1;
 force m00.ready_sync=3; force m00.ack_sync={2{m00.req_toggle}};
 force m01.ready_sync=3; force m01.ack_sync={2{m01.req_toggle}};
 force m10.ready_sync=3; force m10.ack_sync={2{m10.req_toggle}};
 force m11.ready_sync=3; force m11.ack_sync={2{m11.req_toggle}};
 for(n=0;n<640;n=n+1) begin
  ww=n+1;wh=(n*37)%480+1;iw=ww;ih=wh;
  wx=(640-ww)/2;wy=(480-wh)/2;
  if(n%3==1 && ww>=20 && wh>=20) begin iw=ww-19;ih=wh-19;end
  stride=((iw*3+15)/16)*4;fid=n;base=21'h10000+n*1024;
  vl=0;lc=16;xc=0;hsf=0;compare;
  for(j=0;j<525;j=j+1) begin
   vl=j;
   for(k=0;k<6;k=k+1) begin
    case(k) 0:lc=0;1:lc=24;2:lc=144+wx-7;3:lc=144+wx+2;4:lc=799;5:lc=800;endcase
    xc=(k==4)?639:wx;hsf=(k==5);compare;
   end
  end
 end
 $display("SCENARIO_PASS geometry-all-widths-frames");
 for(n=0;n<20000;n=n+1) begin
  vl=$random(seed)&65535;lc=$random(seed)&131071;xc=$random(seed)&65535;
  en=n[0];seen=n[1];hsf=n[2];vsf=n[3];compare;
 end
 $display("SCENARIO_PASS geometry-blanking-and-disabled");
 $display("TEST_PASS");$finish;
end
initial begin #100000000;$display("TEST_FAIL geometry timeout");$finish;end
endmodule
`default_nettype wire
