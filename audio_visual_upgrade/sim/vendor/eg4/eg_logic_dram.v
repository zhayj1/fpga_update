///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor      : Anlogic
//   Version     : 1.0
//   Description : Anlogic Functional Simulation Library Component
//                 mslice distribute ram
//   Filename    : eg_logic_dram.v
//   Timestamp   : 2020-4-17 11.57
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    2020-04-17 - 0.1 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ps / 1 ps
module EG_LOGIC_DRAM (
  di,
  waddr,
  we,
  wclk,
  raddr,
  do
  );
  parameter DATA_WIDTH_W = 4;                      //  >0.                 [Template:Bit width of write data.   ]
  parameter DATA_WIDTH_R = DATA_WIDTH_W;           //  >0.                 [Template:Bit width of read data.    ]
  parameter ADDR_WIDTH_W = 4;                      //  >0.                 [Template:Bit width of write address.]
  parameter ADDR_WIDTH_R = ADDR_WIDTH_W;           //  >0.                 [Template:Bit width of read address. ]
  parameter DATA_DEPTH_W = 2 ** ADDR_WIDTH_W;      //  2 ** ADDR_WIDTH_W.  [Template:Bit depth of write address.]
  parameter DATA_DEPTH_R = 2 ** ADDR_WIDTH_R;      //  2 ** ADDR_WIDTH_R.  [Template:Bit depth of read address. ]
  output  [DATA_WIDTH_R-1:0] do;                                       //  [Template:Read data.]         
  input   [DATA_WIDTH_W-1:0] di; //DEFAULT := (others => '0')              [Template:Write data.]
  input   we; //DEFAULT := '0'                                             [Template:Enable high active.]
  input   wclk; //DEFAULT := '0'                                           [Template:Write clock.]
  input   [ADDR_WIDTH_W-1:0] waddr; //DEFAULT := (others => '0')           [Template:Write address.]
  input   [ADDR_WIDTH_R-1:0] raddr; //DEFAULT := (others => '0')           [Template:Read address.]
  
  parameter INIT_FILE = "NONE";   //  DEFAULT "NONE".  [Template:Initial value file(.dat or .dath).]
  parameter FILL_ALL = "NONE";
// TO BE FILLED

  localparam DATA_WIDTH_MEM = (DATA_WIDTH_W < DATA_WIDTH_R) ? DATA_WIDTH_W : DATA_WIDTH_R; // select min data width 
  localparam DEPTH_MEM_W = DATA_DEPTH_W * DATA_WIDTH_W / DATA_WIDTH_MEM ;
  localparam DEPTH_MEM_R = DATA_DEPTH_R * DATA_WIDTH_R / DATA_WIDTH_MEM ;            
  localparam DEPTH_MEM = (DEPTH_MEM_W > DEPTH_MEM_R) ?  DEPTH_MEM_W : DEPTH_MEM_R; // select max data depth
  localparam RATIO_W = DATA_WIDTH_W / DATA_WIDTH_MEM ;
  localparam RATIO_R = DATA_WIDTH_R / DATA_WIDTH_MEM ;
  localparam RD_DELAY = 0.2 ;
  localparam SIM_INIT = 0 ;


//++
  localparam ASIC_CHAR = 8;
  localparam ASIC_LEN = 9;
  localparam DATA_LEN_IN_BIT =DATA_WIDTH_MEM * DEPTH_MEM + DEPTH_MEM - 1;
  localparam REAL_DATA_LEN_IN_BIT = DATA_WIDTH_MEM * DEPTH_MEM;
  localparam INIT_VALUE_SRART = DATA_LEN_IN_BIT * ASIC_CHAR;
  localparam INIT_STR_LEN = INIT_VALUE_SRART  + (ASIC_CHAR * ASIC_LEN);

  reg [INIT_STR_LEN-1:0] asic_init_data;
  reg [DATA_LEN_IN_BIT-1:0] init_data;
  reg [REAL_DATA_LEN_IN_BIT-1:0] real_init_data;


  reg [DATA_WIDTH_MEM-1:0] memory [0:DEPTH_MEM-1];
  reg [DATA_WIDTH_R-1:0] mem_q_b;
  reg rtrig;
               
  //********************
  // Memory Port-A write
  //********************
  task MEM_WRITE_A
    ( input  reg [ADDR_WIDTH_W-1:0] addr,
      input  reg [DATA_WIDTH_W-1:0] data
  );     
    integer i; 
    begin      
      // Write data to memory
      if ( RATIO_W == 1) begin
        memory[addr] = data;
      end 
      else begin
        for (i = 0; i < RATIO_W; i = i + 1) begin
          memory[addr*RATIO_W + i] = data[DATA_WIDTH_MEM*i+:DATA_WIDTH_MEM];
        end    
      end      
    end        
  endtask      
               
               
  //********************
  // Memory Port-B read
  //********************

  task MEM_READ_B
    ( input reg [ADDR_WIDTH_R-1:0] addr
       );      
    integer i; 
    begin      
     if (RATIO_R==1) begin
       mem_q_b <= #RD_DELAY memory[addr];
     end 
     else begin
       for (i = 0; i < RATIO_R; i = i + 1) begin
         mem_q_b[DATA_WIDTH_MEM*i+:DATA_WIDTH_MEM] <= #RD_DELAY memory[addr*RATIO_R + i];
       end     
     end       
    end        
  endtask      
               
  reg check=0;
  /*
  task init_memory;
    integer i;
    if( (SIM_INIT==0) ) begin
      $display("incase\n");
      for(i=0;i<DEPTH_MEM;i=i+1) begin
        memory[i] = 0;
      end
    end else begin
      $display("error\n");
    end
  endtask
  */

//++
task init_memory;
begin:init_mem
  integer i,m,n; 
  reg [7:0] ch1;
  reg str_length72;
  reg [DATA_WIDTH_MEM-1:0] fill_init_data;

  for(i=0; i<9; i=i+1)
  begin
    ch1 = INIT_FILE>>(i<<3);
    if(ch1!=0)
    str_length72 = 1;
    else
    str_length72 = 0;
  end

  if( (FILL_ALL=="NONE") ) 
  begin
    if( INIT_FILE!="NONE" ) 
    begin
      $display("incase\n");
      if((str_length72 == 1) && (INIT_FILE[INIT_STR_LEN-1:INIT_VALUE_SRART] == "init_str:"))
      begin
        for (i=DATA_LEN_IN_BIT-1; i>=0; i=i-1)
        begin
          init_data[i] = INIT_FILE[i*8];
        end
        for (m=0; m<=DATA_WIDTH_MEM; m=m+1)
        begin
          for (n=0; n<=DEPTH_MEM-1; n=n+1)
          begin
          if (m !== DATA_WIDTH_MEM)
          real_init_data[(n+1)*DATA_WIDTH_MEM - 1 - m] = init_data[n*(DATA_WIDTH_MEM+1) + m];
          end
        end
        for(i=0;i<DEPTH_MEM;i=i+1) 
        begin
          memory[DEPTH_MEM-1-i] = real_init_data>>(i*DATA_WIDTH_MEM);
        end   
      end
      else begin
        if(INIT_FILE[31:0] == ".dat")
        $readmemb(INIT_FILE,memory);
        else if(INIT_FILE[31:0] == "dath")
        $readmemh(INIT_FILE,memory);
        end
    end
    else begin 
        for(i=0;i<DEPTH_MEM;i=i+1) 
        memory[i] = 0;
      end
  end
  else 
  begin
    for (i=DATA_WIDTH_MEM-1; i>=0; i=i-1)
    begin
      fill_init_data[i] = FILL_ALL[i*8];
      end
    for(i=0;i<DEPTH_MEM;i=i+1) 
      begin
      memory[i] = fill_init_data;
    end 
  end
end
endtask

  initial begin
    rtrig=0;
    init_memory;
  end  
  
  always @(posedge wclk) begin
    //Write A 
    if ( we==1 ) begin
      MEM_WRITE_A(waddr, di);
      rtrig=~rtrig;
    end
  end      
           
  always @(rtrig or raddr ) begin
    //Read B 
    MEM_READ_B(raddr);
    //Write B
  end      
  assign do = mem_q_b;
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
