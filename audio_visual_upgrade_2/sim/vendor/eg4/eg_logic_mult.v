///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            mult
//   Filename : eg_logic_mult.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 1 ps
module EG_LOGIC_MULT (p, a, b, cea, ceb, cepd, clk, rstan, rstbn, rstpdn); 
parameter   INPUT_WIDTH_A       = 18        ;
parameter   INPUT_WIDTH_B       = 18        ;
parameter   OUTPUT_WIDTH        = 36        ;
output      [OUTPUT_WIDTH-1:0]  p           ;                           //  [Template:Product output.                             ]
input       [INPUT_WIDTH_A-1:0] a           ;                           //  [Template:Multiplier a.                               ]
input       [INPUT_WIDTH_B-1:0] b           ;                           //  [Template:Multiplier b.                               ]
input                           cea         ; //DEFAULT := '0'              [Template:Port A selection, high active.              ]
input                           ceb         ; //DEFAULT := '0'              [Template:Port B selection, high active.              ]
input                           cepd        ; //DEFAULT := '0'              [Template:Product output chip selection, high active. ]
input                           clk         ; //DEFAULT := '0'              [Template:Synchronous clock.                          ]
input                           rstan       ; //DEFAULT := '0'              [Template:Port A reset, low active.                   ]
input                           rstbn       ; //DEFAULT := '0'              [Template:Port B reset, low active.                   ]
input                           rstpdn      ; //DEFAULT := '0'              [Template:Product output reset, low active.           ]

parameter   INPUTFORMAT     = "SIGNED"  ;      
parameter   INPUTREGA           = "ENABLE"  ;  // "ENABLE", "DISABLE". [Template: Input register enable of port A.]
parameter   INPUTREGB           = "ENABLE"  ;  // "ENABLE", "DISABLE". [Template: Input register enable of port A.]
parameter   OUTPUTREG           = "ENABLE"  ;  // "ENABLE", "DISABLE". [Template: Output register enable.         ]
parameter   IMPLEMENT           = "AUTO"    ;  
parameter   SRMODE              = "ASYNC"   ;  // "ASYNC", "SYNC".     [Template: Reset mode.                     ]

reg     [INPUT_WIDTH_A-1:0] a_async;
reg     [INPUT_WIDTH_B-1:0] b_async;
reg     [INPUT_WIDTH_A-1:0] a_sync;
reg     [INPUT_WIDTH_B-1:0] b_sync;
reg     [INPUT_WIDTH_A-1:0] a_use ;
reg     [INPUT_WIDTH_B-1:0] b_use ;
wire     [OUTPUT_WIDTH-1:0] sign_a ;
wire     [OUTPUT_WIDTH-1:0] sign_b ;

reg     [OUTPUT_WIDTH-1:0]  p_async ;
reg     [OUTPUT_WIDTH-1:0]  p_sync ;
reg     [OUTPUT_WIDTH-1:0]  p_result ;

assign p = p_result;

always @(posedge clk or negedge rstan) begin
  if(!rstan)                          begin a_async <= 0 ;            end
  else if(cea)                        begin a_async <= a ;            end
end
always @(posedge clk or negedge rstbn) begin
  if(!rstbn)                          begin b_async <= 0 ;            end
  else if(ceb)                        begin b_async <= b ;            end
end
always @(posedge clk) begin
  if(!rstan)                          begin a_sync <= 0;              end
  else if(cea)                        begin a_sync <= a ;             end
end
always @(posedge clk) begin
  if(!rstbn)                          begin b_sync <= 0;              end
  else if(ceb)                        begin b_sync <= b ;             end
end

always @(*)begin
  if(INPUTREGA == "ENABLE") begin
    if(SRMODE == "ASYNC")           begin a_use = a_async ;         end
    else                            begin a_use = a_sync ;          end
  end
  else                                begin a_use = a ;               end
end
always @(*)begin
  if(INPUTREGB == "ENABLE") begin
    if(SRMODE == "ASYNC")           begin b_use = b_async ;         end
    else                            begin b_use = b_sync ;          end
  end
  else                                begin b_use = b ;               end
end

assign sign_a = INPUTFORMAT == "SIGNED" ? {{(OUTPUT_WIDTH - INPUT_WIDTH_A){a_use[INPUT_WIDTH_A - 1]}}, a_use} :  a_use;
assign sign_b = INPUTFORMAT == "SIGNED" ? {{(OUTPUT_WIDTH - INPUT_WIDTH_B){b_use[INPUT_WIDTH_B - 1]}}, b_use} :  b_use;

always @(posedge clk or negedge rstpdn) begin
  if(!rstpdn)                         begin p_async <= 0 ;             end
  else if(cepd)                       begin p_async <= sign_a*sign_b ; end
end

always @(posedge clk) begin
  if(!rstpdn)                         begin p_sync <= 0;               end
  else if(cepd)                       begin p_sync <= sign_a*sign_b ;  end
end

always @(*) begin
  if(OUTPUTREG == "ENABLE") begin
    if(SRMODE == "ASYNC")           begin p_result = p_async ;      end
    else                            begin p_result = p_sync ;       end
  end
  else                                begin p_result = sign_a*sign_b ;  end
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
