///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            idelay, iddr, oddr 
//   Filename : eg_logic_io.v
//   Timestamp : Mon Jul 29 14:20:41 CST 2016
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    29/07/16 - Initial version.
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 1 ps
module  EG_LOGIC_IDELAY(o,i);
output o;          // [Template:delayed singal,output to user.]
input i;           // [Template: input IO PAD.]

parameter INDEL = 1;  // 1~32. [Template:The initialization delay is 0.52ns and each Tap is 0.12ns.]

localparam SIM_TAPDELAY_VALUE = 0.12;
reg [4:0] delay_count;
reg o_out;

initial begin
  delay_count = 0;
  #1;
  delay_count = INDEL;
end

    wire delay_chain_0,  delay_chain_1,  delay_chain_2,  delay_chain_3,
         delay_chain_4,  delay_chain_5,  delay_chain_6,  delay_chain_7,
         delay_chain_8,  delay_chain_9,  delay_chain_10, delay_chain_11,
         delay_chain_12, delay_chain_13, delay_chain_14, delay_chain_15,
         delay_chain_16, delay_chain_17, delay_chain_18, delay_chain_19,
         delay_chain_20, delay_chain_21, delay_chain_22, delay_chain_23,
         delay_chain_24, delay_chain_25, delay_chain_26, delay_chain_27,
         delay_chain_28, delay_chain_29, delay_chain_30, delay_chain_31;


// delay chain

    assign #0.52               delay_chain_0  = i;
    assign #SIM_TAPDELAY_VALUE delay_chain_1  = delay_chain_0;
    assign #SIM_TAPDELAY_VALUE delay_chain_2  = delay_chain_1;
    assign #SIM_TAPDELAY_VALUE delay_chain_3  = delay_chain_2;
    assign #SIM_TAPDELAY_VALUE delay_chain_4  = delay_chain_3;
    assign #SIM_TAPDELAY_VALUE delay_chain_5  = delay_chain_4;
    assign #SIM_TAPDELAY_VALUE delay_chain_6  = delay_chain_5;
    assign #SIM_TAPDELAY_VALUE delay_chain_7  = delay_chain_6;
    assign #SIM_TAPDELAY_VALUE delay_chain_8  = delay_chain_7;
    assign #SIM_TAPDELAY_VALUE delay_chain_9  = delay_chain_8;
    assign #SIM_TAPDELAY_VALUE delay_chain_10 = delay_chain_9;
    assign #SIM_TAPDELAY_VALUE delay_chain_11 = delay_chain_10;
    assign #SIM_TAPDELAY_VALUE delay_chain_12 = delay_chain_11;
    assign #SIM_TAPDELAY_VALUE delay_chain_13 = delay_chain_12;
    assign #SIM_TAPDELAY_VALUE delay_chain_14 = delay_chain_13;
    assign #SIM_TAPDELAY_VALUE delay_chain_15 = delay_chain_14;
    assign #SIM_TAPDELAY_VALUE delay_chain_16 = delay_chain_15;
    assign #SIM_TAPDELAY_VALUE delay_chain_17 = delay_chain_16;
    assign #SIM_TAPDELAY_VALUE delay_chain_18 = delay_chain_17;
    assign #SIM_TAPDELAY_VALUE delay_chain_19 = delay_chain_18;
    assign #SIM_TAPDELAY_VALUE delay_chain_20 = delay_chain_19;
    assign #SIM_TAPDELAY_VALUE delay_chain_21 = delay_chain_20;
    assign #SIM_TAPDELAY_VALUE delay_chain_22 = delay_chain_21;
    assign #SIM_TAPDELAY_VALUE delay_chain_23 = delay_chain_22;
    assign #SIM_TAPDELAY_VALUE delay_chain_24 = delay_chain_23;
    assign #SIM_TAPDELAY_VALUE delay_chain_25 = delay_chain_24;
    assign #SIM_TAPDELAY_VALUE delay_chain_26 = delay_chain_25;
    assign #SIM_TAPDELAY_VALUE delay_chain_27 = delay_chain_26;
    assign #SIM_TAPDELAY_VALUE delay_chain_28 = delay_chain_27;
    assign #SIM_TAPDELAY_VALUE delay_chain_29 = delay_chain_28;
    assign #SIM_TAPDELAY_VALUE delay_chain_30 = delay_chain_29;
    assign #SIM_TAPDELAY_VALUE delay_chain_31 = delay_chain_30;
    assign #SIM_TAPDELAY_VALUE delay_chain_32 = delay_chain_31;
    assign #SIM_TAPDELAY_VALUE delay_chain_33 = delay_chain_32;


    always @(*) begin

	case (delay_count)
            1:  o_out = delay_chain_0;
            2:  o_out = delay_chain_1;
            3:  o_out = delay_chain_2;
            4:  o_out = delay_chain_3;
            5:  o_out = delay_chain_4;
            6:  o_out = delay_chain_5;
            7:  o_out = delay_chain_6;
            8:  o_out = delay_chain_7;
            9:  o_out = delay_chain_8;
            10:  o_out = delay_chain_9;
            11: o_out = delay_chain_10;
            12: o_out = delay_chain_11;
            13: o_out = delay_chain_12;
            14: o_out = delay_chain_13;
            15: o_out = delay_chain_14;
            16: o_out = delay_chain_15;
            17: o_out = delay_chain_16;
            18: o_out = delay_chain_17;
            19: o_out = delay_chain_18;
            20: o_out = delay_chain_19;
            21: o_out = delay_chain_20;
            22: o_out = delay_chain_21;
            23: o_out = delay_chain_22;
            24: o_out = delay_chain_23;
            25: o_out = delay_chain_24;
            26: o_out = delay_chain_25;
            27: o_out = delay_chain_26;
            28: o_out = delay_chain_27;
            29: o_out = delay_chain_28;
            30: o_out = delay_chain_29;
            31: o_out = delay_chain_30;
            32: o_out = delay_chain_31;
            default:
		        o_out = delay_chain_0;

	endcase
    end 

  buf(o,o_out);

endmodule


//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_IDDR", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module EG_LOGIC_IDDR (q1, q0, clk, d, rst);
    output q1;        //  [Template:1 bit negedge data output.]
    output q0;        //  [Template:1 bit posedge data output.]
    input clk;        //  [Template:Sampling clock.]
    input d;          //  [Template:DDR data entered on I/O.]
    input rst;        //  [Template:Reset signal,high active.]

    parameter ASYNCRST = "ENABLE";    //  "ENABLE", "DISABLE". [Template:Asynchronous reset.]
    parameter PIPEMODE = "PIPED";     //  "PIPED", "NONE". [Template:q0,q1 data alignment mode.]

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;
    wire clk_node = clk; 
    reg [1:0] comp_reg,true_reg;

    
    always @(negedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     comp_reg[0] <= 1'b0 ;
     else
     comp_reg[0] <= d ;
    end
    always @(posedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     comp_reg[1] = 1'b0 ;
     else
     comp_reg[1] <= comp_reg[0] ;
    end
    
    always @(posedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     true_reg[0] <= 1'b0 ;
     else
     true_reg[0] <= d ;
    end
    always @(posedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     true_reg[1] = 1'b0 ;
     else
     true_reg[1] <= true_reg[0] ;
    end    
    
    wire true_dff = (PIPEMODE == "PIPED")? true_reg[1]:true_reg[0];
    buf (q1, comp_reg[1]);
    buf (q0, true_dff);          	

endmodule

//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_ODDR", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module EG_LOGIC_ODDR (q, clk, d1, d0, rst);
    output q;         //  [Template:1 bit DDR edge output data.]
    input clk;        //  [Template:Synchronous clock.]
    input d1;         //  [Template:1 bit negedge input data.]
    input d0;         //  [Template:1 bit posedge input data.]
    input rst;        //  [Template:Reset,high active.]
    
    parameter ASYNCRST = "ENABLE";    //  "ENABLE", "DISABLE". [Template:Asynchronous reset.]

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node ;   
    wire clk_node = clk;
    reg [1:0] comp_reg;
    reg true_reg;   
    wire ddr;
    buf (d_comp,d1);
    buf (d_true,d0);
    buf (q,ddr);
    always @(posedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     comp_reg[0] = 1'b0 ;
     else
     comp_reg[0] = d_comp ;
    end
    always @(negedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     comp_reg[1] = 1'b0 ;
     else
     comp_reg[1] = comp_reg[0] ;
    end

    always @(posedge clk_node or posedge async_rst)
    begin
     if(async_rst)
     true_reg = 1'b0 ;
     else
     true_reg = d_true ;
    end

    reg clk_mux;
    always @(clk_node)  clk_mux <= #0.1 clk_node; 
    assign   ddr = clk_mux ? true_reg : comp_reg[1] ;    

endmodule


//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_IDDRx2", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module EG_LOGIC_IDDRx2 (q3, q2, q1, q0, pclk, sclk, d, rst);
    output q3;          //  [Template:The 3th bit of parallel output.]
    output q2;          //  [Template:The 2th bit of parallel output.]
    output q1;          //  [Template:The 1th bit of parallel output.]
    output q0;          //  [Template:The 0th bit of parallel output.]
    input pclk;         //  [Template:Clock input of 1/2 sclk.] 
    input sclk;         //  [Template:Clock input of 1/2 data rate.]
    input d;            //  [Template:Serial data input.]
    input rst;          //  [Template:Reset, high active.]

    parameter ASYNCRST = "ENABLE";     //  "ENABLE", "DISABLE". [Template:Asynchronous reset.]

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;
    reg cap_reg;
    reg [1:0] cap_reg_1, cap_reg_2;
    reg [1:0] des_reg;
    reg [3:0] des_reg_1;

// Capture to sclk domain    
    always @(posedge sclk or posedge async_rst)
    begin  
     if(async_rst)
       cap_reg <= 1'b0;
     else
       cap_reg <= d;
    end
    
// Sync to sclk domain    
    always @(negedge sclk or posedge async_rst)
    begin
     if(async_rst)
       cap_reg_1[1:0] <= 2'b00 ;
     else
       cap_reg_1[1:0] <= {d,cap_reg};
    end

    always @(posedge sclk or posedge async_rst)
    begin
     if(async_rst)
       cap_reg_2 <= 2'b00 ;
     else
       cap_reg_2 <= cap_reg_1;
    end


// Capture to pclk domain    
    always @(negedge pclk or posedge async_rst)
    begin
     if(async_rst)
       des_reg[1:0] <= 2'b00 ;
     else
       des_reg[1:0] <= cap_reg_2 ;
    end    
    
// Deserialize in pclk domain
    always @(posedge pclk or posedge async_rst)
    begin
     if(async_rst)
       des_reg_1[3:0] <= 4'b0000 ;
     else
       des_reg_1[3:0] <= {cap_reg_2[1:0], des_reg[1:0]} ;
    end    

    buf (q3, des_reg_1[3]);
    buf (q2, des_reg_1[2]);          	
    buf (q1, des_reg_1[1]);
    buf (q0, des_reg_1[0]);          	

endmodule

//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_ODELAY", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module  EG_LOGIC_ODELAY(o,i);
output o;         // [Template:output io PAD.]
input i;          // [Template:usr singal, output to delay Macro.]

parameter OUTDEL = 1;    //  1~4. [Template:The initialization delay is 0.175ns and each Tap is 0.11ns.]

localparam SIM_TAPDELAY_VALUE = 0.11;
reg [1:0] delay_count ;
reg o_out;

initial begin
  delay_count = OUTDEL;
end

    wire delay_chain_0,  delay_chain_1,  delay_chain_2,  delay_chain_3;

// delay chain

    assign #0.175              delay_chain_0  = i;
    assign #SIM_TAPDELAY_VALUE delay_chain_1  = delay_chain_0;
    assign #SIM_TAPDELAY_VALUE delay_chain_2  = delay_chain_1;
    assign #SIM_TAPDELAY_VALUE delay_chain_3  = delay_chain_2;


    always @(*) begin
	case (delay_count)
            1:  o_out = delay_chain_0;
            2:  o_out = delay_chain_1;
            3:  o_out = delay_chain_2;
            4:  o_out = delay_chain_3;
            default:
		o_out = delay_chain_0;
	endcase
    end 

    wire o_outm = o_out;

  buf(o,o_outm);

endmodule

//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_ODDRx2", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module EG_LOGIC_ODDRx2 (q, pclk, sclk, d3, d2, d1, d0, rst);
    output q;              //  [Template:Serial data output from IO.]
    input pclk;            //  [Template:Clock input of 1/2 sclk.] 
    input sclk;            //  [Template:Clock input of 1/2 data rate.]
    input d3;              //  [Template:3th bit parallel data.]
    input d2;              //  [Template:2th bit parallel data.]
    input d1;              //  [Template:1th bit parallel data.]
    input d0;              //  [Template:0th bit parallel data.]
    input rst;             //  [Template:Reset,high active.]
    
    parameter ASYNCRST = "ENABLE";   //  "ENABLE", "DISABLE". [Template:Asynchronous reset.]

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;

    EG_LOGIC_ODDR x2to1_20 (.q(q20), .clk(pclk), .d1(d2), .d0(d0), .rst(async_rst));
    EG_LOGIC_ODDR x2to1_31 (.q(q31), .clk(pclk), .d1(d3), .d0(d1), .rst(async_rst));

    EG_LOGIC_ODDR x2to1_4to1 (.q(q), .clk(sclk), .d1(q31), .d0(q20), .rst(async_rst));

endmodule

//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_ODDRx2l", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
module EG_LOGIC_ODDRx2l (q, sclk, d3, d2, d1, d0, rst);
    output q;        //  [Template:Serial data output.]
    input sclk;      //  [Template:Clock input of 1/2 data rate.]
    input d3;        //  [Template:3th bit parallel data.]
    input d2;        //  [Template:2th bit parallel data.]
    input d1;        //  [Template:1th bit parallel data.]
    input d0;        //  [Template:0th bit parallel data.]
    input rst;       //  [Template:Reset,high active.]
    
    parameter ASYNCRST = "ENABLE";     //  "ENABLE", "DISABLE".  [Template:Asynchronous reset.]

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;

    reg ckd2;

    initial begin
      ckd2 = 1'b0;
    end

    always @(posedge sclk or posedge async_rst)
      begin
        if(async_rst)
          ckd2 <= 1'b0;
        else
          ckd2 <= ~ckd2;
      end


    EG_LOGIC_ODDR x2to1_20 (.q(q20), .clk(ckd2), .d1(d2), .d0(d0), .rst(async_rst));
    EG_LOGIC_ODDR x2to1_31 (.q(q31), .clk(ckd2), .d1(d3), .d0(d1), .rst(async_rst));

    EG_LOGIC_ODDR x2to1_4to1 (.q(q), .clk(sclk), .d1(q31), .d0(q20), .rst(async_rst));

endmodule

/*
//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_BI_DDR", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
***********module EG_LOGIC_BI_DDR (q, d1, d0, rst, osclk,
                        q0, q1, d, ipclk);
// oDDR ports    
    output q;
    input d1, d0;
    input osclk;
    input rst;

// iDDR ports    
    input d;
    output q1, q0;
    input ipclk;
    
    parameter ASYNCRST = "ENABLE"; //ENABLE, DISABLE
    parameter PIPEMODE = "PIPED"; //PIPED, NONE

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;

    EG_LOGIC_IDDR xiddr (.q1(q1), .q0(q0), .clk(ipclk), .d(d), .rst(async_rst));
//    defparam xiddr.ASYNCRST = ASYNCRST;
//    defparam xiddr.PIPEMODE = PIPEMODE;
    EG_LOGIC_ODDR xoddr (.q(q), .clk(osclk), .d1(d1), .d0(d0), .rst(async_rst));
//    defparam xoddr.ASYNCRST = ASYNCRST;

***********endmodule


//--------------------------------------------------------------------
// Verilog HDL for "EG_LOGIC_BI_DDRx2", "functional"
//--------------------------------------------------------------------
`timescale 1 ns / 1 ps
***********module EG_LOGIC_BI_DDRx2 (q, pclk, osclk, d3, d2, d1, d0, rst,
                          q3, q2, q1, q0, isclk, d);

// oDDRx2 ports    
    output q;
    input d3, d2, d1, d0;
    input rst;
    input pclk;
    input osclk;

// iDDRx2 ports    
    output q3, q2, q1, q0;
    input isclk;
    input d;

    parameter ASYNCRST = "ENABLE"; //ENABLE, DISABLE

    tri1 gsr_n = glbl.gsrn;
    wire rst_node = (ASYNCRST=="ENABLE")? rst:1'b0;
    wire async_rst = ~gsr_n | rst_node;

    // IDDRx2
    EG_LOGIC_IDDRx2 xiddrx2 (.q3(q3), .q2(q2), .q1(q1), .q0(q0), 
                             .pclk(pclk), .sclk(isclk), .d(d), .rst(async_rst));

    // ODDRx2
    EG_LOGIC_ODDRx2 xoddrx2 (.q(q), .pclk(pclk), .sclk(osclk), .rst(async_rst),
                             .d3(d3), .d2(d2), .d1(d1), .d0(d0));

***********endmodule
*/

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
