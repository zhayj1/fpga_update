///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            global clk,  io clock, clk div
//   Filename : eg_phy_clk.v
//   Timestamp : Thu Apr  24 09:30:30 CST 2014
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    4/24/14 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module EG_PHY_GCLK (clki, clko);
    input clki;     //  [Template:BUFG input port.]
    output clko;    //  [Template:Clock switching output port.]

    buf (clko,clki);
 specify                                      
      //(clki  => clko) = (0.5:0.5:0.5, 0.5:0.5:0.5);
        (clki  => clko) = (0.0:0.0:0.0, 0.0:0.0:0.0);
 endspecify 
endmodule

module EG_PHY_IOCLK (clki, stop, clko);
    input clki;       //  [Template:IOCLK clock input.]
    input stop;       //  [Template:IOCLK stop enable port.] 
    output clko;      //  [Template:IOCLK clock output.]

    wire clko_tmp;
    buf (clko,clko_tmp);
    parameter  STOPCLK = "DISABLE"; //  "ENABLE", "DISABLE".  [Template:Clock stop enable.]

    reg ck_en1,ck_en2;
    reg stop_en;

    initial begin
        ck_en1 = 1'b0;
        ck_en2 = 1'b0;
    end

    initial begin
        case (STOPCLK)
            "DISABLE" : stop_en = 1'b0;
            "ENABLE"  : stop_en = 1'b1;
            default   : begin
                            $display("Parameter Warning : The attribute STOPCLK on ECLK instance %m is set to %s.  Legal values for this attribute are ENABLE or DISABLE.", STOPCLK);
                            //$finish;
                        end
        endcase
    end

    assign clksel = ~(stop & stop_en);

    always @(negedge clki)
        if(clksel==1'b0) begin
            ck_en1 <= 1'b0;
            ck_en2 <= ck_en1;
        end
        else begin
            ck_en1 <= 1'b1;
            ck_en2 <= ck_en1;
        end

    assign clko_tmp = stop_en ? (clki & ck_en2) : clki;
 specify                                      
        (clki  => clko) = (0.5:0.5:0.5, 0.5:0.5:0.5);
 	$setuphold (posedge clki, stop 	, 0:0:0, 0:0:0);
 	$setuphold (negedge clki, stop 	, 0:0:0, 0:0:0); 	
 endspecify
endmodule
 
module EG_PHY_CLKDIV (clki, rst, rls, clkdiv1, clkdivx);

    output clkdiv1, clkdivx;
    input clki;
    input rst;
    input rls;

    tri1 gsrn = glbl.gsrn;
    //tri1 gsrn;

    parameter GSR = "DISABLE";    //  "ENABLE", "DISABLE".  [Template:Global reset.]
    parameter DIV = 2;            //  2, 4.                 [Template:Clock divide.]

//check parameter
    initial begin
        if (DIV != 2 && DIV != 4) begin
        $display("attribute syntax error : the attribute DIV on clkdiv instance %m is set to %d. legal values for this attribute are 2 or 4.", DIV);
        $finish;
        end
    end

    reg sr_reg1, sr_reg2, SRN, rst_d1, set;
    wire clkdiv1_val, clkdiv1_buf, sr,rstn;
    reg [2:0] count_dn;
    wire clki_buf;

    buf inst_buf0 (clkdiv1, clkdiv1_buf);
    wire clk_divx_tmp;
    buf (clk_divx,clk_divx_tmp);
    wire clkdivx_tmp;
    assign clkdivx_tmp = (DIV == 2) ? count_dn[0] : count_dn[1];
    buf (clkdivx, clkdivx_tmp);

    initial 
    begin
        count_dn = 2'b00;
    end
    assign   rstn = ~(rst | ~(gsrn | (GSR=="DISABLE")));

/*
    always @ (gsrn) begin
        if (GSR == "ENABLE") begin
            SRN = gsrn;
        end
        else if (GSR == "DISABLE")
            SRN = 1'b1;
    end

    not (SR1, SRN);
    or (sr, rst, SR1);
*/

    always @ (posedge clki or negedge rstn) begin
        if (!rstn) sr_reg1<=0;
        else sr_reg1 <= 1'b1;
    end

    always @ (posedge clki or negedge sr_reg1)  begin
        if(!sr_reg1) sr_reg2<=0;
        else sr_reg2 <= 1'b1;
    end

    assign clki_buf = clki;

    and (clkdiv1_val, clki_buf, sr_reg1);
    and (clkdiv1_buf, clkdiv1_val, sr_reg2);

    always @ (posedge clki or posedge sr)
    begin
        if (sr == 1'b1)
            rst_d1 <= 1'b0;
        else
            rst_d1 <= 1'b1;
    end

    and (setn, rst_d1, rls);
    always @ (posedge clki or negedge setn)
    begin
        if (setn == 1'b0)
            count_dn <= 2'b00;
        else
            count_dn <= count_dn - 1;
    end
wire done_gwe = glbl.done_gwe;
 specify                                      
        (clki  => clkdiv1) = (0.5:0.5:0.5, 0.5:0.5:0.5);
        (clki  => clkdivx) = (0.5:0.5:0.5, 0.5:0.5:0.5);        
 	$setuphold (posedge clki, posedge rls &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (negedge clki, posedge rls &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (posedge clki, posedge rst &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (negedge clki, posedge rst &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0); 
 	
 	$setuphold (posedge clki, negedge rls &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (negedge clki, negedge rls &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (posedge clki, negedge rst &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);
 	$setuphold (negedge clki, negedge rst &&& (done_gwe!=1'b0)	, 0:0:0, 0:0:0);  		 	
 endspecify  

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
