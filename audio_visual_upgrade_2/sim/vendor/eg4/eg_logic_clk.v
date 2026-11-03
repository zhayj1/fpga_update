///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            bufg, bufio for clock, 
//            bufgmux as clock switch mux
//   Filename : eg_logic_clock.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale  1 ps / 1 ps

module  EG_LOGIC_BUFG(o,i);  // driver for global clk resource
output o;       //   [Template:BUFG output port.]
input i;        //   [Template:BUFG input port.]

	buf bufg (o, i);

endmodule

module  EG_LOGIC_BUFIO(clki,rst,coe,clko,clkdiv1,clkdivx);  // driver for IO clk resource
input clki;                                 //  [Template:Input clock signal.]
input rst;                                  //  [Template:Reset signal,high active.]
input coe;                                  //  [Template:Clock enable signal, high active.]
output clko;                                //    [Template:Clock output signal.]
output clkdiv1;                             //    [Template:Frequency divide coefficient 1 output.]
output clkdivx;                             //    [Template:Frequency divide coefficient x output.]

//EG_PHY_IOCLK  ioclk( .clki(clki), .stop(rst), .clko(clk_o));
//EG_PHY_CLKDIV clk_div(.clki(clk_o), .rst(rst), .rls(coe), .clkdiv1(clkdiv1), .clkdivx(clkdivx));

parameter GSR                = "DISABLE";     //  "ENABLE", "DISABLE".  [Template:Global reset.                  ]
parameter DIV                 = 2;            //  2, 4.                 [Template:Frequency division coefficient.]
parameter STOPCLK = "DISABLE";                //  "ENABLE", "DISABLE".  [Template:Clock stop.                    ]
tri1 rst,coe;
wire clko;
EG_PHY_IOCLK #(.STOPCLK(STOPCLK)) ioclk( .clki(clki), .stop(rst), .clko(clko));
EG_PHY_CLKDIV #(.DIV(DIV),.GSR(GSR)) clk_div  (.clki(clko), .rst(rst), .rls(coe), .clkdiv1(clkdiv1), .clkdivx(clkdivx));

endmodule

module  EG_LOGIC_BUFGMUX(o,i0,i1,s); // global clk switch mux
output o;            //   [Template:BUFG output port.]
input i0;            //   [Template:BUFG input port 0.]
input i1;            //   [Template:BUFG input port 1.]
input s;             //   [Template:Select signal.]
 
parameter INIT_OUT = "0";             //  "0", "1".         [Template:Initial output value.]
parameter PRESELECT_I0 = "TRUE";      //  "TRUE", "FALSE".  [Template:pre-select I0.       ]
parameter PRESELECT_I1 = "FALSE";     //  "TRUE", "FALSE".  [Template:pre-select I1.       ]

   localparam INITOUT = (INIT_OUT=="1")? "1" : "0" ;
   localparam PRESELECT = ((PRESELECT_I0 == "TRUE")&&(PRESELECT_I1 == "FALSE"))? "CLK0" :  ((PRESELECT_I0 == "FALSE")&&(PRESELECT_I1 == "TRUE"))? "CLK1" : "NONE" ;

    wire clko;
    wire [1:0] ce = 2'b11;
    wire [1:0] clki = {i1,i0};
    wire [1:0] drct = 2'b11;
    wire [1:0] sel = {s,~s};
EG_PHY_CSB #(.HOLD("YES"),.INITOUT(INITOUT),.PRESELECT(PRESELECT)) bufgmux(.clko(clko), .ce(ce), .clki(clki), .ignr(drct), .sel(sel));
buf (o,clko);

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
