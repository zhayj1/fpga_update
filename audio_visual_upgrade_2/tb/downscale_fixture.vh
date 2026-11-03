localparam integer PIXEL_COUNT=438;
initial begin
  bg_w[0]=8;
  bg_h[0]=6;
  bg_off[0]=25;
  cv_w[0]=5;
  cv_h[0]=5;
  cv_off[0]=0;
  bg_w[1]=8;
  bg_h[1]=6;
  bg_off[1]=98;
  cv_w[1]=5;
  cv_h[1]=5;
  cv_off[1]=73;
  bg_w[2]=8;
  bg_h[2]=6;
  bg_off[2]=171;
  cv_w[2]=5;
  cv_h[2]=5;
  cv_off[2]=146;
  bg_w[3]=8;
  bg_h[3]=6;
  bg_off[3]=244;
  cv_w[3]=5;
  cv_h[3]=5;
  cv_off[3]=219;
  bg_w[4]=8;
  bg_h[4]=6;
  bg_off[4]=317;
  cv_w[4]=5;
  cv_h[4]=5;
  cv_off[4]=292;
  bg_w[5]=8;
  bg_h[5]=6;
  bg_off[5]=390;
  cv_w[5]=5;
  cv_h[5]=5;
  cv_off[5]=365;
end
function integer asset_of_file;
input integer ft;
begin case(ft)
  11: asset_of_file=0;
  8: asset_of_file=0;
  12: asset_of_file=1;
  9: asset_of_file=1;
  13: asset_of_file=2;
  10: asset_of_file=2;
  19: asset_of_file=3;
  16: asset_of_file=3;
  20: asset_of_file=4;
  17: asset_of_file=4;
  21: asset_of_file=5;
  18: asset_of_file=5;
  default: asset_of_file=-1;
endcase end
endfunction
