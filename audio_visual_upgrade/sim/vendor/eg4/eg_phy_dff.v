///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            dff_slice
//   Filename : eg_phy_dff.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module dff_slice_half ( q , clk, f, di, fx, ffc_asrn , mc1_sr, mc1_di, mc1_fx, mc1_testsh, s_d0, s_ce, ffc_sr, sr_n, latchmode);  
output q;
input clk, f, di, fx, ffc_asrn , mc1_sr, mc1_di, mc1_fx, mc1_testsh, s_d0, s_ce, ffc_sr, sr_n;
input latchmode;
reg qtmp;
reg d_n;
wire q;
wire q_n;
wire net21 = mc1_testsh ? sr_n : ~mc1_di ;
wire sfx = mc1_fx ;
wire sfxn = ~mc1_fx ; 
wire sf = sfxn & (!net21);
wire sdi= sfxn & net21 ;

wire sset = ~mc1_sr;
wire sset_n = mc1_sr ;  
wire setn = sset ? ffc_asrn : 1'b1;
wire resetn = sset ? 1'b1 : ffc_asrn ;
wire [2:0]dmux_sel = {sf,sdi,sfx};
reg net0102;
always @(dmux_sel or f or di or fx)
  begin
  	case(dmux_sel[2:0])
  	3'b100 : net0102 = ~f;
  	3'b010 : net0102 = ~di;
  	3'b001 : net0102 = ~fx;
  	default : begin
  			  net0102 = 1'bx;
	                  //$display("Circuit maybe Error : The DFF dmux select signal is not ONE-HOT, the value is %b", dmux_sel);
	                  //$finish;
	          end
  	endcase
  end // dmux

 	
wire [2:0]sel = {s_d0,s_ce,ffc_sr} ;
 always @(sel or net0102 or q_n or sset_n)
  begin
  	case(sel[2:0])
  	3'b100 : d_n = net0102;
  	3'b010 : d_n = q_n;
  	3'b001 : d_n = sset_n;
  	default : begin
	                  d_n = 1'bx;
	                  //$display("Circuit maybe Error : The DFF input select signal is not ONE-HOT, the value is %b", sel);
	                  //$finish;
	          end
  	endcase
  end


  
 always @(posedge clk or negedge setn or negedge resetn)
 	begin if(!setn) qtmp <= 1'b1;
 	else  if(!resetn) qtmp <= 1'b0;
 	else qtmp <= ~ d_n ;
 	end
reg latch_q;
 always @( clk or negedge setn or negedge resetn or d_n)
  	begin if(!setn) latch_q <= 1'b1;
 	else  if(!resetn) latch_q <= 1'b0;
 	else  if(!clk) latch_q <= ~ d_n ;
 	end

 assign q = latchmode ? latch_q : qtmp ;  	  
assign q_n = ~q ;   
endmodule

module pfb_dffctrl ( s_d0, s_ce, ffc_asrn,ffc_sr,sr_n, sr, mc1_testsh, ce , latchmode, gsrn, gsrforce_n, mc1_disgsr, mc1_syncmode);
output s_d0,s_ce,ffc_asrn,ffc_sr,sr_n;
input sr,ce,gsrn,gsrforce_n;
input mc1_testsh,latchmode,mc1_disgsr,mc1_syncmode;

wire ffc_sr = sr & (!mc1_testsh);
wire ffc_srn = ~ffc_sr;
wire gsr = !(gsrforce_n & mc1_disgsr | gsrn);
wire asyncgsr_n = !(ffc_sr & (!mc1_syncmode) | gsr);
wire ffc_asrn = asyncgsr_n;
wire sr_n = ~sr;
wire s_d0 = ce & ffc_srn;
wire s_ce = !ce & ffc_srn;
endmodule


module dff_slice( q0, q1, ce, sr, clk, gsrn, gsrforce_n, mc1_syncmode, mc1_disgsr, mc1_testsh, di,f,fx,mc1_sr,mc1_di,mc1_fx,latchmode);
output q0,q1;
input ce,sr,clk,gsrn,gsrforce_n,mc1_syncmode,mc1_disgsr,mc1_testsh,latchmode;
input [1:0]di,f,fx,mc1_sr,mc1_di,mc1_fx;
//wire s_d0,s_ce,ffc_asrn,ffc_sr,sr_n;

pfb_dffctrl dffctrl( .s_d0(s_d0), .s_ce(s_ce), .ffc_asrn(ffc_asrn),  .ffc_sr(ffc_sr), .sr_n(sr_n), .sr(sr), .mc1_testsh(mc1_testsh), .ce(ce) , .latchmode(latchmode),
 .gsrn(gsrn), .gsrforce_n(gsrforce_n), .mc1_disgsr(mc1_disgsr), .mc1_syncmode(mc1_syncmode));
dff_slice_half dff0( .q(q0) , .clk(clk), .f(f[0]), .di(di[0]), .fx(fx[0]), .ffc_asrn(ffc_asrn) , .mc1_sr(mc1_sr[0]), .mc1_di(mc1_di[0]), .mc1_fx(mc1_fx[0]), 
.mc1_testsh(mc1_testsh), .s_d0(s_d0), .s_ce(s_ce), .ffc_sr(ffc_sr), .sr_n(sr_n), .latchmode(latchmode));
dff_slice_half dff1( .q(q1) , .clk(clk), .f(f[1]), .di(di[1]), .fx(fx[1]), .ffc_asrn(ffc_asrn) , .mc1_sr(mc1_sr[1]), .mc1_di(mc1_di[1]), .mc1_fx(mc1_fx[1]), 
.mc1_testsh(mc1_testsh), .s_d0(s_d0), .s_ce(s_ce), .ffc_sr(ffc_sr), .sr_n(sr_n), .latchmode(latchmode));
endmodule  

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
su4MlKU8+402CR6LDS9cxwTZKAbsI23atz+mD9jtwCUG7eacE+xXQkUYzN0yJjpg
FFAj5jbDdCzvJvxmkkIGXG8s1C/fENg6HHyaaITD11bUqngugvF+okTDH7FAqFB5
YcKHb8Vlz1iGqKMJ3RZGyeFvWPNf6wusp0y+o8Zh3j4=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
f52n19Q4urMvPA1qKx/AvVPCfJ0yZuzrsm98WHnkcOQlG/glV16QDR7S37iyPxbK
qJ6Mq4qZS8TFMon9XwQ5mamrKQ2wYYqeX1G9oi3C8D/wETXUNLVWLbJGs57SByCP
eMsvjeZ4BAgumHa+5qZA/ByP+5ynklqMFAOXYRoArX4=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
pTJ+eXstmGdQcwTO/QGESBpnJ7eRVHKjZvnAOtjDi/AC7c0RzAGnWaRBPSm/UqND
2TpgsuvccOorAUHyIhor3qkv8jtWIr3y9W36nRj4JEO9ijXdvhJXpOQ0+vgo/Tbg
rr3+x9jIzDf4T7CUSpuIqsQW1Fdg7vweZ12PaKHSTU/JTvbSca8jO7tOPwV5KUg3
cutVLwqPAK7sCeAf72D1+eBArtDqZgGSht+D7UxxYrv8RmXUsCGbpO/j8F48U++U
rXTNWYNTJMq0w1/VpcESphLsb8b2TqhkoomVtTmG7YcunwKJpsKaKTl6l48EQvHD
J4DLqYP+wYbFrcnEyEewZg==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
ZvfzAf7PRkuRm6nsiXQV6BdDpJobl4DYrcQzc86UOyrt/gUme+6RKKiIUiggiGnx
YRvC9KUC4xQI12YYNCPT1rMkcbc3QFfoSbLaVElJDxrf9FahbvTuy/efU/5aIEsa
RBKnW012FMo3+OlUcoKdNOD5K11yix0Y1iIuP0s+xF8=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Mq9t6Xrtikv4COKcSVZ3ZshBLHqoVAYuf0jbOug5+ExESnVQkpWhHqHpk9+wI2rg
3/9ZTT8FD4KJVL0+RRUB1UxCVUsCOqDa2+zg1V4Hk0m2ZEBH8Kw4rIT+Y3kBaDWz
wQ5YekxLURcV34ut6OmK7AT5k7UHM2gwt0NSqphPsF0gkGGM1AY8BdLS0T7r/L8j
vnB4ld5WCHGFeLa98WfUte5AiT0TK7XYVf6Dm3HRBziFq9H3oasVOyXvPXvw9BN5
MO37YZq2r2EzGnULbpbUJV9jmpFdgFxNajhKOs5fXSn/Ku/6KbpR6Ty+UKH4ZSUV
9w+dZZBBSQABuSqj0RoDcw==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
d2lnGYQDieLPRG+78shxbu3QjfNQDUwoe8TYcHXlDthRQgqRCTTGtfNi0HPFs/zh
iaCLIbHbkdc5jWR2W0IXvxJ/OqLBK765y+MvasdyxnAAjn9u4e6SvBpRvjnbUwZT
byEhK5VtRAygzKFgg10UP9kWEmgf3gY3uB3LsilDqkg1xW1LpMCZBW80SNkwpDGy
hTHkLC9pt1MR/BNZiEKy6X0p0nuDQXdBZW8GBg5Mx8SH7nQia/n/2czlE31680lJ
opneOj5gWawQHxg4GEd6YMiqYoPKwWTXH79KFfVFuge8OSevh1nylBWqUMnP89Hs
uDqv1GxFTlUVmR5hQ0ddKw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 48)
`pragma protect data_block
x8CRoYDY1tGjhtOIgQ9QdhJG7AyClCYRNVYsYgZuuXzlxwgg9X7WDtYnFu8Fp13u
`pragma protect end_protected
