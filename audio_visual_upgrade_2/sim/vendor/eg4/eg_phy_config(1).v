///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//   Vendor : Anlogic
//   Version : 1.1
//   Description : Anlogic Hard IP Library Component
//            CONFIG block
//   Filename : eg_phy_config.v
//   Timestamp : Fri July  8 09:30:30 CST 2016
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    8/2/16 - Initial version.      
//    11/3/16 - v1.0      
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 10 ps

module EG_PHY_CONFIG(
  jrstn, jrti, jshift, jtck, jtdi, jupdate, jscanen, jtms, jtdo, jtag8_ipa, jtag8_ipb,
  done, highz,
  cclk, cclk_en,
  gsrn_sync_clk, usr_gsrn,
  dna_dout, dna_clk, dna_din, dna_shift_en,
  mboot_rebootn, mboot_dynamic_addr
);
  //chip watcher(customer should not see chip watcher interface)
  output       jrstn;
  output [1:0] jrti;
  output       jshift;
  output       jtck;
  output       jtdi;
  output       jupdate;
  output [1:0] jscanen;
  output       jtms;

  input [1:0]  jtdo;
  input [7:0]  jtag8_ipa;
  input [7:0]  jtag8_ipb;

  //global control
  output       	done;
  output       	highz;

  //cclk 
  output       	cclk;
  input	      	cclk_en;	

  //user gsrn
  input        	gsrn_sync_clk;
  input        	usr_gsrn;

  //DNA IP
  output		dna_dout;
  input		dna_clk;
  input		dna_din;
  input		dna_shift_en;

  //Multi boot
  input		mboot_rebootn;
  input [7:0] 	mboot_dynamic_addr;

  tri0 cclk_en;

  //Parameter
  //multiboot
  parameter MBOOT_AUTO_SEL = "DISABLE";	     //  "ENABLE", "DISABLE".  [Template:Set in device setting.]
  parameter ADDR_SOURCE_SEL = "STATIC";	     //  "STATIC", "DYNAMIC".  [Template:Start mode.           ]
  parameter STATIC_ADDR = 8'b0;		         //  DEFAULT 8'b0.         [Template:Static start address. ]
  //io                                                                                               
  parameter DONE_PERSISTN = "ENABLE";	     //  "ENABLE", "DISABLE".  [Template:Set in device setting.]	
  parameter INIT_PERSISTN = "ENABLE";	     //  "ENABLE", "DISABLE".  [Template:Set in device setting.]
  parameter PROGRAMN_PERSISTN = "DISABLE";   //  "ENABLE", "DISABLE".  [Template:Set in device setting.]
  parameter JTAG_PERSISTN = "DISABLE";	     //  "ENABLE", "DISABLE".  [Template:Set in device setting.]
  //parameter(register)
  parameter GSRN_SYNC_SEL = "DISABLE";	     //  "ENABLE", "DISABLE".  [Template:set by wakeup register.]
  parameter FREQ = "2.5";			         //  "2.5", "5.0", "10.0", "30.0". [Template:set by wakeup register.]
  parameter USR_GSRN_EN = "DISABLE";	     //  "ENABLE", "DISABLE".  [Template:set by wakeup register.]

  // GSR implementation
  reg [1:0] usr_gsrn_sync;

  initial
  begin
    usr_gsrn_sync = 2'b00;
  end

  always @(posedge gsrn_sync_clk)
    usr_gsrn_sync <= {usr_gsrn_sync[1], usr_gsrn};

  always @(*)
  begin
    glbl.usr_gsrn_en <= (USR_GSRN_EN == "ENABLE") ? 1'b1 : 1'b0;
    glbl.gsrn <= (USR_GSRN_EN == "ENABLE") ? ((GSRN_SYNC_SEL == "ENABLE") ? usr_gsrn_sync[1] : usr_gsrn) : 1'b1;
    glbl.gsr <= ~glbl.gsrn;
  end

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
