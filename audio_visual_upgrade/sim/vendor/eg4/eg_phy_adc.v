///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Hard IP Library Component
//            ADC block
//   Filename : eg_phy_adc.v
//   Timestamp : Fri July  8 09:30:30 CST 2016
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    7/29/16 - Initial version. 
//    9/22/16 - add simulation code
//   10/26/16 - remove ch[7:0]&vref port , add CH[7:0] default sample output to 7~0.     
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 100 fs
module EG_PHY_ADC(clk, pd, s, soc, eoc, dout);
input clk;          // [Template:clock.                 ]
input pd;           // [Template:power Down signal,high active.     ]
input [2:0] s;      // [Template:channel Select Signal. ]
input soc;          // [Template:start of Conversion.   ]
output eoc;         // [Template:end of Conversion.     ]
output [11:0] dout; // [Template:AD conversion results. ]

parameter CH0 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH1 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH2 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH3 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH4 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH5 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH6 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter CH7 = "DISABLE" ;      //  "ENABLE", "DISABLE".
parameter VREF = "DISABLE" ;     //  "ENABLE", "DISABLE".
                               
wire [11:0] dout_tmp;
wire eoc_tmp;

  buf (eoc,  eoc_tmp);
  buf (dout[0],  dout_tmp[0]);
  buf (dout[1],  dout_tmp[1]);
  buf (dout[2],  dout_tmp[2]);
  buf (dout[3],  dout_tmp[3]);
  buf (dout[4],  dout_tmp[4]);
  buf (dout[5],  dout_tmp[5]);
  buf (dout[6],  dout_tmp[6]);
  buf (dout[7],  dout_tmp[7]);
  buf (dout[8],  dout_tmp[8]);
  buf (dout[9],  dout_tmp[9]);
  buf (dout[10], dout_tmp[10]);
  buf (dout[11], dout_tmp[11]);
wire done_gwe = glbl.done_gwe;
 specify
        (clk  => dout[0]) = (0:0:0, 0:0:0);
        (clk  => dout[1]) = (0:0:0, 0:0:0);
        (clk  => dout[2]) = (0:0:0, 0:0:0);
        (clk  => dout[3]) = (0:0:0, 0:0:0);
        (clk  => dout[4]) = (0:0:0, 0:0:0);
        (clk  => dout[5]) = (0:0:0, 0:0:0);
        (clk  => dout[6]) = (0:0:0, 0:0:0);
        (clk  => dout[7]) = (0:0:0, 0:0:0);
        (clk  => dout[8]) = (0:0:0, 0:0:0);
        (clk  => dout[9]) = (0:0:0, 0:0:0);
        (clk  => dout[10]) = (0:0:0, 0:0:0);
        (clk  => dout[11]) = (0:0:0, 0:0:0);                             
        (clk  => eoc ) = (0:0:0, 0:0:0);        
	$setuphold (posedge clk, posedge pd  	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[0] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (posedge clk, posedge s[1] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[2] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);		
	$setuphold (posedge clk, posedge soc 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (negedge clk, posedge pd 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[0] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (posedge clk, posedge s[1] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[2] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);		
	$setuphold (negedge clk, posedge soc 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, negedge pd  	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[0] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (posedge clk, posedge s[1] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[2] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, negedge soc 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (negedge clk, negedge pd 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[0] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (posedge clk, posedge s[1] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
	$setuphold (posedge clk, posedge s[2] 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);
	$setuphold (negedge clk, negedge soc 	&&& (done_gwe!=0) , 0:0:0, 0:0:0);	
 endspecify 


HARD_SAR12_ADC udt(
    .VDDA(1'b1), .VSSA(1'b0), .CLK(clk), .PD(pd), .SOC(soc), .S(s), .CH(8'hff), .VREF(1'b1), .EOC(eoc_tmp), .B(dout_tmp)
    );

endmodule

module HARD_SAR12_ADC(
    VDDA,       //Analog power supply 
    VSSA,       //Analog ground.
    CLK,        //Main Clock.
    PD,         //Power Down signal.
    SOC,        //Start of Conversion.
    S,          //Channel Select Signal.
    CH,         //Channel Signal-ended analog voltage input.
    VREF,       //Voltage reference
    EOC,        //End of Conversion.
    B           //AD conversion results.
    );

    parameter DATASIZE=12;      //ADC output bits
    parameter S_SIZE = 3;       //Select size
    parameter CH_SIZE= 8;       //Channel size
    parameter CONVERT_SIZE=16;  //one conversion cycle
    parameter SAMPLE_SIZE=4;    //sample cycle    
    parameter Td_B = 0;         //16;
    parameter Td_EOC = 0;       //13.5;
    
    
    

// Output digital data
    output  [11:0]   B ;
    output  EOC;

// Inputs from External
    input   CLK ;
    input   PD;
    input   SOC ;
    input   [2:0]   S;
    input   [7:0]   CH;
    input   VREF;

// Inputs from External Power
    input   VDDA;
    input   VSSA;

//////////////buffer/////////////////
    reg  [DATASIZE-1:0]  reg_B;
//    reg  sample_B;
    wire [DATASIZE-1:0] Bi;
    reg  reg_EOC;
    wire EOCi;
    wire CLKi;
    wire PDi;
    wire SOCi;
    wire [S_SIZE-1:0] Si;
    wire [CH_SIZE-1:0] CHi;
    wire VREFi;
    reg  [4:0]   counter;
    wire unknown;
    reg notify_TCLK, notify_TS, notify_TH;
    reg err_TCLK, err_TS, err_TH;

    buf (B[0],Bi[0]);
    buf (B[11],Bi[11]);
    buf (B[10],Bi[10]);
    buf (B[9],Bi[9]);
    buf (B[8],Bi[8]);
    buf (B[7],Bi[7]);
    buf (B[6],Bi[6]);
    buf (B[5],Bi[5]);
    buf (B[4],Bi[4]);
    buf (B[3],Bi[3]);
    buf (B[2],Bi[2]);
    buf (B[1],Bi[1]);
    buf (EOC,EOCi);
    buf (SOCi,SOC);
    buf (CLKi,CLK); 
    buf (PDi,PD);
    buf (Si[0],S[0]);
    buf (Si[2],S[2]);
    buf (Si[1],S[1]);
    buf (CHi[0],CH[0]);
    buf (CHi[7],CH[7]);
    buf (CHi[6],CH[6]);
    buf (CHi[5],CH[5]);
    buf (CHi[4],CH[4]);
    buf (CHi[3],CH[3]);
    buf (CHi[2],CH[2]);
    buf (CHi[1],CH[1]);
    buf (VREFi,VREF);
    	
//////////////initial///////    
    initial 
    begin
       counter = 0; 
       notify_TCLK =0;
       notify_TS =0;
       notify_TH = 0;
       err_TS = 0;
       err_TH = 0;
       err_TCLK = 0;
    end     
    

//////////////unknow////////////////
    assign unknown = (CLKi===1'bx)||(PDi===1'bx)||(SOCi===1'bx)||(^Si===1'bx)||(CHi[Si]===1'bx)||(VREFi===1'bx);
    
    always @(posedge unknown)
    begin 
       if($realtime>0)
       begin
           #0.1;
           if(unknown==1)
           begin   
               $display("****************************************************");
               $display("Error at %f ns: One or more of the inputs unknown, output will be unknown.",$realtime);
           end 
       end 
    end

////////////////////////////////////   
    always @(posedge CLKi or posedge PDi or posedge unknown)
    begin          
       if(PDi||unknown)
           counter <=5'd0;  
       else if(((counter==5'd0)&&(SOCi==1'b1))||((counter==CONVERT_SIZE)&&(SOCi == 1'b1)))
           counter <= 5'd1;	  
       else if((counter<CONVERT_SIZE)&&(counter>=1))
           counter <= counter + 1;	   
       else 
           counter <=5'd0; 
    end
    

///////////sampling////////////////   
reg [11:0] sample_B ;
    always @(posedge CLKi or posedge PDi or posedge unknown)          
    begin
       if(PDi)
         sample_B <= 12'hxxx; 
       else if(unknown) 
         sample_B <= 12'hxxx;    
       else if(counter==SAMPLE_SIZE)
         begin
           case(Si)
             3'b000 : sample_B <= 12'h000;
             3'b001 : sample_B <= 12'h001;
             3'b010 : sample_B <= 12'h002;
             3'b011 : sample_B <= 12'h003;
             3'b100 : sample_B <= 12'h004;
             3'b101 : sample_B <= 12'h005;
             3'b110 : sample_B <= 12'h006;
             3'b111 : sample_B <= 12'h007;
             default: sample_B <= 12'hxxx;
           endcase 
         end  
    end 
     

///////////output//////////////////
    always @(posedge CLKi or posedge PDi or posedge unknown)		      
    begin
       if(PDi)
       begin
          reg_EOC <= 1'b0;
          reg_B <= 0;
       end
       else if(unknown) 
       begin
          reg_EOC <= 1'bx;
          reg_B <= {{DATASIZE}{1'bx}}; 
       end 
       else if(counter==CONVERT_SIZE)
       begin     	    
           if(err_TCLK||err_TS||err_TH) 
	   begin
	      reg_EOC <= 1'bx;
    	      reg_B <= {{DATASIZE}{1'bx}}; 
              $display("****************************************************");
              $display("Error at %f ns:  TS or TCLK or TH violation in a conversion cycle, EOC/B will be unknown.",$realtime);	   
	   end
	   else
	   begin
	      reg_EOC <= #Td_EOC 1'b1;
              reg_B <= sample_B;
	   end
       end
       else
    	   reg_EOC <= #Td_EOC 1'b0;
    end  
    
    assign Bi = PDi ? {{DATASIZE}{1'b0}} :
                unknown ? {{DATASIZE}{1'bx}} : reg_B; 
    
    assign EOCi = PDi ? 1'b0 :
                  unknown ? 1'bx : reg_EOC; 
		   

///////////timing violation///////////
    always @(notify_TCLK)
    begin
       if($realtime>0)
      err_TCLK=1;    
    end    
    
    always @(notify_TS)
    begin
       if($realtime>0)
      err_TS=1;   
    end    
    
    always @(notify_TH)
    begin
       if($realtime>0)
      err_TH=1;    
    end
        
////////////////////////////////////   
    always @(posedge CLKi)
    begin          
       if(((counter==5'd0)&&(SOCi==1'b1))||((counter==CONVERT_SIZE)&&(SOCi == 1'b1)))
       begin
      err_TCLK <= 0;
      err_TS <= 0;
      err_TH <= 0;
       end 
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
