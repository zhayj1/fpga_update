///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            config multiboot 
//            config dna 
//            config gctrl 
//            config gsrn
//            config cclk 
//   Filename : al_logic_config.v
//   Timestamp : Wed Nov  2 17:27:07 CST 2016
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/02/16 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale  1 ns / 1 ps

module EG_LOGIC_MBOOT(rebootn, dynamic_addr);   // config multiboot
input       rebootn;         //                      [Template:Restart control signal, low active.]
input [7:0] dynamic_addr;    // [Template:Dynamic restart address,high-8bit address, SPI Flash address[23:16].]

  //parameter 
  parameter ADDR_SOURCE_SEL = "STATIC";   //  "STATIC", "DYNAMIC".  [Template:Start mode.       ]
  parameter STATIC_ADDR = 8'b00000000;    //  DEFAULT 8'b00000000.  [Template:High-8bit address.]

endmodule

module EG_LOGIC_DNA(dout, clk, din, shift_en);    // config dna 
output dout;   // LSB out firstly         //     [Template:DNA data output, LSB is preferred.]
input  clk;                               //     [Template:Clock input.]
input  din;                               //     [Template:User data input.]
input  shift_en;                          //     [Template:Shifter enable signal,high active.]

endmodule


module  EG_LOGIC_GSRN(gsrn, sync_clk);     // config gsrn
input gsrn;
input sync_clk; 

  //parameter 
  parameter GSRN_SYNC_SEL = "DISABLE";  //  "ENABLE", "DISABLE".  [Template:set by wakeup register.]
  parameter USR_GSRN_EN   = "DISABLE";  //  "ENABLE", "DISABLE".  [Template:set by wakeup register.]
  
  reg [1:0] usr_gsrn_sync;

  initial
  begin
    usr_gsrn_sync = 2'b00;
  end

  always @(posedge sync_clk)
    usr_gsrn_sync <= {usr_gsrn_sync[1], gsrn};

  //assign glbl.gsrn = (USR_GSRN_EN == "ENABLE") ? ((GSRN_SYNC_SEL == "ENABLE") ? usr_gsrn_sync[1] : gsrn) : 1'b1;
  always @(*)
  begin
    glbl.usr_gsrn_en <= (USR_GSRN_EN == "ENABLE") ? 1'b1 : 1'b0;
    glbl.gsrn <= (USR_GSRN_EN == "ENABLE") ? ((GSRN_SYNC_SEL == "ENABLE") ? usr_gsrn_sync[1] : gsrn) : 1'b1;
    glbl.gsr <= ~glbl.gsrn;
  end

endmodule

module EG_LOGIC_CCLK(cclk, en);        // config cclk
output cclk;
input  en;

parameter FREQ = "4.5";      //  "4.5", "6.5", "10.0", "20.0", "30.0", "40.0", "60.0", "130.0".  [Template:frequency set by wakeup register.] 

realtime half_period;
reg int_clk;

initial
begin
  int_clk = 1'b0;
end

initial
begin
  case (FREQ)
    "4.5"   : half_period = 111.1; //111.1ns (4.5MHz)
    "6.5"   : half_period = 76.9; 
    "10.0"  : half_period = 50; 
    "20.0"  : half_period = 25; 
    "30.0"  : half_period = 16.67; 
    "40.0"  : half_period = 12.5; 
    "60.0"  : half_period = 8.3; 
    "130.0" : half_period = 3.8; 
    default : half_period = 111.1;   //default frequency is 4.5MHz
  endcase
end

always
  #half_period int_clk = ~int_clk;

assign cclk = en ? int_clk : 1'b0;

endmodule // EG_LOGIC_CCLK


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
