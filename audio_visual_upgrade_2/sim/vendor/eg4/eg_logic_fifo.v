///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            fifo
//   Filename : eg_logic_fifo.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//    05/30/16 - correct the EP1 parameter value
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 1 ps
module EG_LOGIC_FIFO (
    rst,
    di, clkw, we, csw, 
    do, clkr, re, csr, ore,
    empty_flag, aempty_flag,
    full_flag, afull_flag
);
// 1kx9 by default
parameter DATA_WIDTH_W = 9;                                          //  1~9*48.                       [Template:FIFO write data width.]
parameter DATA_WIDTH_R = DATA_WIDTH_W;                               //  1~9*48.                       [Template:FIFO read data width. ]
parameter DATA_DEPTH_W = 1024;                                       //  512, 1024, 2048, 4096, 8192.  [Template:FIFO write data depth.]
parameter DATA_DEPTH_R = DATA_WIDTH_W * DATA_DEPTH_W / DATA_WIDTH_R; //  512, 1024, 2048, 4096, 8192.  [Template:FIFO read data depth. ]
input   rst;                                  //   [Template:Reset, high active.]
input   [DATA_WIDTH_W-1:0] di;                //   [Template:FIFO write data.]
output  [DATA_WIDTH_R-1:0] do;                //   [Template:FIFO read data.]
input   clkw;    //   [Template:FIFO write clock.]
input   we;      //   [Template:FIFO write enable,high active.]
input   clkr; //DEFAULT := '0'  [Template:FIFO read clock.]
input   re;   //DEFAULT := '0'  [Template:FIFO read enable,high active.]
input   ore; //DEFAULT := '0'   [Template:FIFO read output enable,high active.]
input [2:0] csw;  //  [Template:FIFO write chip select signal,high active.]
input [2:0] csr;  //  [Template:FIFO write chip select signal,high active.]
output  empty_flag;  //DEFAULT := '0'    [Template:FIFO empty flag.]
output  aempty_flag; //DEFAULT := '0'   [Template:FIFO almost empty flag.]
output  full_flag;  //DEFAULT := '0'    [Template:FIFO full flag.]
output  afull_flag; //DEFAULT := '0'     [Template:FIFO almost full flag.]
parameter  MODE = "FIFO8K";                  //  "FIFO8K".             [Template:FIFO mode.                           ]
parameter  REGMODE_W   = "NOREG";            //  "NOREG", "OUTREG".    [Template:FIFO write register.                 ]
parameter  REGMODE_R   = "NOREG";            //  "NOREG", "OUTREG".    [Template:FIFO read register.                  ]
parameter  E  = 0;                           //  DEFAULT 0.            [Template:FIFO empty flag depth setting.       ]
parameter  AE = 6;                           //  1~DATA_DEPTH_W-1.     [Template:FIFO almost empty flag depth setting.]
parameter  AF = DATA_DEPTH_W-6;              //  1~DATA_DEPTH_W-1.     [Template:FIFO almost full flag depth setting. ]
parameter  F  = DATA_DEPTH_W;                //  DATA_DEPTH_W.         [Template:FIFO full flag depth setting.        ]
                                             
parameter  GSR = "DISABLE";                  //  "ENABLE", "DISABLE".  [Template:Global reset.                  ]
parameter  RESETMODE = "ASYNC";              //  "SYNC", "ASYNC".      [Template:FIFO reset mode.               ]
parameter  ASYNC_RESET_RELEASE = "SYNC";     //  "SYNC", "ASYNC".      [Template:FIFO asynchronous reset mode.  ]
parameter ENDIAN = "LITTLE";                 //  "LITTLE", "BIG".      [Template:FIFO Alignment mode.           ]

// TO BE FILLED

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
