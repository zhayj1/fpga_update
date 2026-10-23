localparam integer PIXEL_COUNT=16000;
initial begin
  bg_w[0]=640;
  bg_h[0]=16;
  bg_off[0]=0;
  cv_w[0]=320;
  cv_h[0]=16;
  cv_off[0]=10240;
  bg_w[1]=8;
  bg_h[1]=8;
  bg_off[1]=15360;
  cv_w[1]=8;
  cv_h[1]=8;
  cv_off[1]=15424;
  bg_w[2]=8;
  bg_h[2]=8;
  bg_off[2]=15488;
  cv_w[2]=8;
  cv_h[2]=8;
  cv_off[2]=15552;
  bg_w[3]=8;
  bg_h[3]=8;
  bg_off[3]=15616;
  cv_w[3]=8;
  cv_h[3]=8;
  cv_off[3]=15680;
  bg_w[4]=8;
  bg_h[4]=8;
  bg_off[4]=15744;
  cv_w[4]=8;
  cv_h[4]=8;
  cv_off[4]=15808;
  bg_w[5]=8;
  bg_h[5]=8;
  bg_off[5]=15872;
  cv_w[5]=8;
  cv_h[5]=8;
  cv_off[5]=15936;
end
function integer asset_of_file;
input integer ft;
begin
case(ft)
  11: asset_of_file=0; // S01CV1.BMP
  8: asset_of_file=0; // S01BG1.BMP
  12: asset_of_file=1; // S01CV2.BMP
  9: asset_of_file=1; // S01BG2.BMP
  13: asset_of_file=2; // S01CV3.BMP
  10: asset_of_file=2; // S01BG3.BMP
  19: asset_of_file=3; // S02CV1.BMP
  16: asset_of_file=3; // S02BG1.BMP
  20: asset_of_file=4; // S02CV2.BMP
  17: asset_of_file=4; // S02BG2.BMP
  21: asset_of_file=5; // S02CV3.BMP
  18: asset_of_file=5; // S02BG3.BMP
  default: asset_of_file=-1;
endcase
end
endfunction
