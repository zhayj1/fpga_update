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
//   Filename : eg_phy_fifo.v
//   Timestamp : Mon Nov  4 14:20:41 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/04/13 - Initial version.
//    03/28/14 - update
//    05/30/16 - add empty plus 1 pointer Error value report
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module EG_PHY_FIFO (
		rst, 
            // write port
            dia,dib, csw, we, clkw, 
            // read port
            dob,doa, csr, re, clkr, rprst, orea,oreb,
            // output flag
            empty_flag, aempty_flag, afull_flag, full_flag);



input    [8:0] dia,dib;
input    [2:0] csr;
input    [2:0] csw;
input    we, re, clkw, clkr, rst, rprst,orea,oreb;
output   [8:0] dob,doa;
output   empty_flag, aempty_flag, afull_flag, full_flag;
   parameter  MODE = "FIFO8K";        //  "FIFO8K".                  [Template:Type of FIFO.                   ]
   parameter  DATA_WIDTH_A = "18";    //  "1", "2", "4", "9", "18".  [Template:FIFO write data width of port A.]
   parameter  DATA_WIDTH_B = "18";    //  "1", "2", "4", "9", "18".  [Template:FIFO write data width of port B.]
   parameter  READBACK = "OFF";       //  "ON", "OFF".               [Template:Backward read enable.           ]
   parameter  REGMODE_A   = "NOREG";  //  "NOREG", "OUTREG".         [Template:FIFO write register of port A.  ]
   parameter  REGMODE_B   = "NOREG";  //  "NOREG", "OUTREG".         [Template:FIFO write register of port B.  ]
//   parameter  CSDECODE_A = "0b011"; //0b000,0b001,......0b111
//   parameter  CSDECODE_B = "0b011";  //0b000,0b001,......0b111
   parameter  [13:0] AE   = 14'b00000001100000;
   parameter  [13:0] AF   = 14'b01111110010000;
   parameter  [13:0] F 	  = 14'b01111111110000;
   parameter  [13:0] AEP1 = 14'b00000001110000;
   parameter  [13:0] AFM1 = 14'b01111110000000;
   parameter  [13:0] FM1  = 14'b01111111100000;   
   parameter  [4:0] E   = 5'b00000;
   parameter  [5:0] EP1 = 6'b010000;
        
   parameter  GSR = "ENABLE";                //  "DISABLE", "ENABLE".  [Template:Global reset.]              
   parameter  RESETMODE = "ASYNC";           //  "SYNC", "ASYNC".      [Template:Reset mode.  ]
   parameter  ASYNC_RESET_RELEASE = "SYNC";  //  "SYNC", "ASYNC".      [Template:Asynchronous reset release mode.]
   
// Full_Flag or AFull_Flag must connect to CSW[2] with CSDECODE_A=0b011 , which means input is inverted to CSW[2]
// Empty_Flag must connect to CSR[2] with CSDECODE_A=0b011 , which means Empty_Flag is inverted to CSR[2]
   localparam REGMODE = REGMODE_B ;
   localparam ADDR_WIDTH_W = (DATA_WIDTH_A == "1") ? 13 : (DATA_WIDTH_A == "2") ? 12 :
                       (DATA_WIDTH_A == "4") ? 11 : (DATA_WIDTH_A == "9") ? 10 : 9; 
   localparam ADDR_WIDTH_R = (DATA_WIDTH_B == "1") ? 13 : (DATA_WIDTH_B == "2") ? 12 :
                       (DATA_WIDTH_B == "4") ? 11 : (DATA_WIDTH_B == "9") ? 10 : 9; 

   localparam DINv_a = (DATA_WIDTH_A == "1") ? 8 : (DATA_WIDTH_A == "2") ? 4 :
                       (DATA_WIDTH_A == "4") ? 2 : (DATA_WIDTH_A == "9") ? 9216 : 9216 ;
   localparam DINv_b = (DATA_WIDTH_B == "1") ? 8 : (DATA_WIDTH_B == "2") ? 4 :
                       (DATA_WIDTH_B == "4") ? 2 : (DATA_WIDTH_B == "9") ? 9216 : 9216;

   localparam DWW_VALUE = (DATA_WIDTH_A == "1") ? 1 : (DATA_WIDTH_A == "2") ? 2 :
                       (DATA_WIDTH_A == "4") ? 4 : (DATA_WIDTH_A == "9") ? 9 : 
                       (DATA_WIDTH_A == "18") ? 18 : 0; 
   localparam DWR_VALUE = (DATA_WIDTH_B == "1") ? 1 : (DATA_WIDTH_B == "2") ? 2 :
                       (DATA_WIDTH_B == "4") ? 4 : (DATA_WIDTH_B == "9") ? 9 : 
                       (DATA_WIDTH_B == "18") ? 18 : 0;  
/* 2018/09/05 remove EP check
initial 
  begin
    if(DATA_WIDTH_B == "18")
        begin
          if(EP1 != 6'b010000) $display("Error: EP1 pointer not equal 6b010000 for 18bit read mode");
        end
    else if(DATA_WIDTH_B == "9")
        begin
          if(EP1 != 6'b001000) $display("Error: EP1 pointer not equal 6b001000 for 9bit read mode");
        end
    else if(DATA_WIDTH_B == "4")
        begin
          if(EP1 != 6'b000100) $display("Error: EP1 pointer not equal 6b001000 for 4bit read mode");
        end
    else if(DATA_WIDTH_B == "2")
        begin
          if(EP1 != 6'b000010) $display("Error: EP1 pointer not equal 6b001000 for 2bit read mode");
        end
    else if(DATA_WIDTH_B == "1")
        begin
          if(EP1 != 6'b000001) $display("Error: EP1 pointer not equal 6b001000 for 1bit read mode");
        end
  end
*/                        
// bram vs fifo port mapping
/*  bram : fifo
clka 	: clkw
ocea 	: orea
cea  	: we
wea  	: null
rsta 	: rst
csa[2:0] : csw[2:0]
clkb 	: clkr
oceb 	: oreb
ceb  	: re
web  	: null
rstb 	: rprst
csb[2:0] : csr[2:0]
*/
//mention: for fifo input INVMUX , we use same parameter with bram
parameter CEA = "SIG";     //  "0", "1", "INV", "SIG".
parameter CEB = "SIG";     //  "0", "1", "INV", "SIG".
parameter OCEA = "SIG";    //  "0", "1", "INV", "SIG".
parameter OCEB = "SIG";    //  "0", "1", "INV", "SIG".
parameter RSTA = "SIG";    //  "0", "1", "INV", "SIG".
parameter RSTB = "SIG";    //  "0", "1", "INV", "SIG".
parameter CLKA = "SIG";    //  "0", "1", "INV", "SIG".
parameter CLKB = "SIG";    //  "0", "1", "INV", "SIG".
parameter WEA = "SIG";     //  "0", "1", "INV", "SIG".
parameter WEB = "SIG";     //  "0", "1", "INV", "SIG".
parameter CSA0 = "SIG" ;   //  "0", "1", "INV", "SIG".
parameter CSA1 = "SIG" ;   //  "0", "1", "INV", "SIG".
parameter CSA2 = "SIG" ;   //  "0", "1", "INV", "SIG".
parameter CSB0 = "SIG" ;   //  "0", "1", "INV", "SIG".
parameter CSB1 = "SIG" ;   //  "0", "1", "INV", "SIG".
parameter CSB2 = "SIG" ;   //  "0", "1", "INV", "SIG".

reg cea_node;
reg ocea_node;
reg ceb_node;
reg oceb_node;
reg clka_node;
reg clkb_node;
reg rsta_node;
reg rstb_node;


reg csa0_node, csa1_node, csa2_node;
reg csb0_node, csb1_node, csb2_node;
reg param_trig;
initial begin
param_trig=0;
param_trig=1;
end

   always @(param_trig)
   begin
        case (CSA0)
            "SIG"   	: assign csa0_node = csw[0];
            "0" 	: assign csa0_node = 0;
            "1" 	: assign csa0_node = 1;
            "INV"   	: assign csa0_node = ~csw[0];
            default 	: assign csa0_node = 1;
        endcase

        case (CSA1)
            "SIG"   	: assign csa1_node = csw[1];
            "0" 	: assign csa1_node = 0;
            "1" 	: assign csa1_node = 1;
            "INV"   	: assign csa1_node = ~csw[1];
            default 	: assign csa1_node = 1;
        endcase

        case (CSA2)
            "SIG"   	: assign csa2_node = csw[2];
            "0" 	: assign csa2_node = 0;
            "1" 	: assign csa2_node = 1;
            "INV"   	: assign csa2_node = ~csw[2];
            default 	: assign csa2_node = 1;
        endcase

        case (CSB0)
            "SIG"   	: assign csb0_node = csr[0];
            "0" 	: assign csb0_node = 0;
            "1" 	: assign csb0_node = 1;
            "INV"   	: assign csb0_node = ~csr[0];
            default 	: assign csb0_node = 1;
        endcase

        case (CSB1)
            "SIG"   	: assign csb1_node = csr[1];
            "0" 	: assign csb1_node = 0;
            "1" 	: assign csb1_node = 1;
            "INV"   	: assign csb1_node = ~csr[1];
            default 	: assign csb1_node = 1;
        endcase

        case (CSB2)
            "SIG"   	: assign csb2_node = csr[2];
            "0" 	: assign csb2_node = 0;
            "1" 	: assign csb2_node = 1;
            "INV"   	: assign csb2_node = ~csr[2];
            default 	: assign csb2_node = 1;
        endcase

        case (RSTA)
            "SIG"   	: assign rsta_node = rst;
            "0" 	: assign rsta_node = 0;
            "1" 	: assign rsta_node = 1;
            "INV"   	: assign rsta_node = ~rst;
            default 	: assign rsta_node = rst;
        endcase
    
        case (RSTB)
            "SIG"   	: assign rstb_node = rprst;
            "0" 	: assign rstb_node = 0;
            "1" 	: assign rstb_node = 1;
            "INV"   	: assign rstb_node = ~rprst;
            default 	: assign rstb_node = rprst;
        endcase 
             
        case (CEA)
            "SIG"   	: assign cea_node = we;
            "0" 	: assign cea_node = 0;
            "1" 	: assign cea_node = 1;
            "INV"   	: assign cea_node = ~we;
            default 	: assign cea_node = we;
        endcase
     
        case (CEB)
            "SIG"   	: assign ceb_node = re;
            "0" 	: assign ceb_node = 0;
            "1" 	: assign ceb_node = 1;
            "INV"   	: assign ceb_node = ~re;
            default 	: assign ceb_node = re;
        endcase        
    
        case (OCEA)
            "SIG"   	: assign ocea_node = orea;
            "0" 	: assign ocea_node = 0;
            "1" 	: assign ocea_node = 1;
            "INV"   	: assign ocea_node = ~orea;
            default 	: assign ocea_node = orea;
        endcase
    
        case (OCEB)
            "SIG"   	: assign oceb_node = oreb;
            "0" 	: assign oceb_node = 0;
            "1" 	: assign oceb_node = 1;
            "INV"   	: assign oceb_node = ~oreb;
            default 	: assign oceb_node = oreb;
        endcase        

// wea/web pin are not used in fifo
/*
   always @(WEA) begin     
        case (WEA)
            "SIG"   	: assign wrea_node = wea;
            "0" 	: assign wrea_node = 0;
            "1" 	: assign wrea_node = 1;
            "INV"   	: assign wrea_node = ~wea;
            default 	: assign wrea_node = wea;
        endcase
   end
   always @(WEB) begin
        case (WEB)
            "SIG"   	: assign wreb_node = web;
            "0" 	: assign wreb_node = 0;
            "1" 	: assign wreb_node = 1;
            "INV"   	: assign wreb_node = ~web;
            default 	: assign wreb_node = web;
        endcase          
   end
*/

        case (CLKA)
            "SIG"   	: assign clka_node = clkw;
            "0" 	: assign clka_node = 0;
            "1" 	: assign clka_node = 1;
            "INV"   	: assign clka_node = ~clkw;
            default 	: assign clka_node = clkw;
        endcase

        case (CLKB)
            "SIG"   	: assign clkb_node = clkr;
            "0" 	: assign clkb_node = 0;
            "1" 	: assign clkb_node = 1;
            "INV"   	: assign clkb_node = ~clkr;
            default 	: assign clkb_node = clkr;
        endcase                     
   end // always









//   integer DWW_VALUE, DWR_VALUE;
wire [17:0]do_buf;
wire [17:0]DI = {dib[8:0],dia[8:0]};

  buf (doa[0],  do_buf[9]);
  buf (doa[1],  do_buf[10]);
  buf (doa[2],  do_buf[11]);
  buf (doa[3],  do_buf[12]);
  buf (doa[4],  do_buf[13]);
  buf (doa[5],  do_buf[14]);
  buf (doa[6],  do_buf[15]);
  buf (doa[7],  do_buf[16]);
  buf (doa[8],  do_buf[17]);

  buf (dob[0],  do_buf[0]);
  buf (dob[1],  do_buf[1]);
  buf (dob[2],  do_buf[2]);
  buf (dob[3],  do_buf[3]);
  buf (dob[4],  do_buf[4]);
  buf (dob[5],  do_buf[5]);
  buf (dob[6],  do_buf[6]);
  buf (dob[7],  do_buf[7]);
  buf (dob[8],  do_buf[8]); 

// orea oreb should connect to same signal
wire ore = ocea_node & oceb_node ;
  
    

tri1 gsrn_sig =  glbl.gsrn; //gsr_sig = 0 , reset// 
tri1 done_sig =  glbl.done_gwe;


// reg GSR_sig, PUR_sig;
integer i;
wire [13:0] ae_ptr;
wire [13:0] empty_ptr;
wire [17:0] DIN;
wire [2:0]  CSWin;
wire [2:0]  CSRin;
reg  [17:0] DO_out;
reg  [DWR_VALUE-1:0] DO_reg;
reg  [DWR_VALUE-1:0] DO_reg_sync;
reg  [DWR_VALUE-1:0] DO_reg_async;
reg  [DWR_VALUE-1:0] DO_node;
reg  [DWR_VALUE-1:0] DO_int;
reg  [17:0] DO_intb;
wire        WRE_node, RDE_node, WCLK_node, RCLK_node, RST_node, RPRST_node;
reg         SRN;
wire  [DWW_VALUE-1:0] DIN_node;
reg   [DWW_VALUE-1:0] DIN_reg;
reg   [DWW_VALUE-1:0] DIN_reg_sync;
reg   [DWW_VALUE-1:0] DIN_reg_async;
reg   [ADDR_WIDTH_W:0] ADW_node;
reg   [ADDR_WIDTH_W:0] ADW_node_syncb;
reg   [ADDR_WIDTH_W:0] ADW_var;
reg   [ADDR_WIDTH_W:0] ADW_var_syncb;
reg   [ADDR_WIDTH_R:0] ADR_node;
reg   [ADDR_WIDTH_R:0] ADR_node_syncb;
reg   [ADDR_WIDTH_R:0] ADR_var;
reg   [ADDR_WIDTH_R:0] ADR_var_syncb;
reg   [13:0] ADWF_node;
reg   [13:0] ADWF_node_syncb;
reg   [13:0] ADRF_node;
reg   [13:0] ADRF_node_syncb;
wire [13:0] fifo_words_used_syncw;
wire [13:0] fifo_words_used_syncr;
reg   [9215:0] MEM;

integer WADDR, RADDR;
wire  DIN_0, DIN_1, ORE_node;
wire  ef_int, pef_int, pff_int, ff_int;
reg   RPRST_reg1, RPRST_reg2;
reg   SRN_pur, RST_sig2, RPRST_sig2, RST_sig, RPRST_sig;
wire  RST_sig1, RPRST_sig1, SR_pur;

  buf (DIN[0], DIN_0);
  buf (DIN[1], DIN_1);
  buf (DIN[2], DI[2]);
  buf (DIN[3], DI[3]);
  buf (DIN[4], DI[4]);
  buf (DIN[5], DI[5]);
  buf (DIN[6], DI[6]);
  buf (DIN[7], DI[7]);
  buf (DIN[8], DI[8]);
  buf (DIN[9], DI[9]);
  buf (DIN[10], DI[10]);
  buf (DIN[11], DI[11]);
  buf (DIN[12], DI[12]);
  buf (DIN[13], DI[13]);
  buf (DIN[14], DI[14]);
  buf (DIN[15], DI[15]);
  buf (DIN[16], DI[16]);
  buf (DIN[17], DI[17]);
  buf (CSWin[0], csa0_node);
  buf (CSWin[1], csa1_node);
  buf (CSWin[2], csa2_node);
  buf (CSRin[0], csb0_node);
  buf (CSRin[1], csb1_node);
  buf (CSRin[2], csb2_node);
  buf (WCLK_node, clka_node);
  buf (RCLK_node, clkb_node);
  buf (WRE_node, cea_node);
  buf (RDE_node, ceb_node);
  buf (RST_node, rsta_node);
  buf (RPRST_node, rstb_node);
  buf (ORE_node, ore);
  buf (do_buf[0], DO_out[0]);
  buf (do_buf[1], DO_out[1]);
  buf (do_buf[2], DO_out[2]);
  buf (do_buf[3], DO_out[3]);
  buf (do_buf[4], DO_out[4]);
  buf (do_buf[5], DO_out[5]);
  buf (do_buf[6], DO_out[6]);
  buf (do_buf[7], DO_out[7]);
  buf (do_buf[8], DO_out[8]);
  buf (do_buf[9], DO_out[9]);
  buf (do_buf[10], DO_out[10]);
  buf (do_buf[11], DO_out[11]);
  buf (do_buf[12], DO_out[12]);
  buf (do_buf[13], DO_out[13]);
  buf (do_buf[14], DO_out[14]);
  buf (do_buf[15], DO_out[15]);
  buf (do_buf[16], DO_out[16]);
  buf (do_buf[17], DO_out[17]);


localparam [13:0] AE_POINTER_B = AE;
localparam [13:0] AF_POINTER_B = AF;
localparam [13:0] FULL_POINTER_B = F;


//////////////////////////
initial begin
  //$display("AE_POINTER_B: %s,%d,%b",AE_POINTER_B,AE_POINTER_B,AE_POINTER_B);
  //$display("AF_POINTER_B: %s,%d,%b",AF_POINTER_B,AF_POINTER_B,AF_POINTER_B);
  //$display("FULL_POINTER_B: %s,%d,%b",FULL_POINTER_B,FULL_POINTER_B,FULL_POINTER_B);
end
//////////////////////////

  assign DIN_0 = (DWW_VALUE == 1) ? DI[1] : (DWW_VALUE == 2) ? DI[2] : DI[0];
  assign DIN_1 = (DWW_VALUE == 2) ? DI[5] : DI[1];


  always @ (gsrn_sig or done_sig ) begin
    if (GSR == "ENABLE")
      SRN = gsrn_sig & done_sig ;
    else if (GSR == "DISABLE")
      SRN = done_sig;

    SRN_pur = done_sig;
  end

  initial
  begin
     MEM = 0;
     DIN_reg = 0;
     RST_sig2 = 0;
     DO_reg = 0;
     DO_out = 0;
     DO_reg_sync = 0;
     DO_reg_async = 0;
     DO_node = 0;
     DO_int = 0;
     DIN_reg_sync = 0;
     DIN_reg_async = 0;
     ADW_node = 0;
     ADW_node_syncb = 0;
     ADW_var = 0;
     ADW_var_syncb = 0;
     ADR_node = 0;
     ADR_node_syncb = 0;
     ADR_var = 0;
     ADR_var_syncb = 0;
     RPRST_reg1 = 0;
     RPRST_reg2 = 0;
     RPRST_sig2 = 0;
     RST_sig = 0;
     RPRST_sig = 0;
  end

// chip select W decode
/*
  always @ (CSWin)
  begin
     if (CSWin == 3'b000 && CSDECODE_A == "0b000")
        CSW_EN = 1'b1;
     else if (CSWin == 3'b001 && CSDECODE_A == "0b001")
        CSW_EN = 1'b1;
     else if (CSWin == 3'b010 && CSDECODE_A == "0b010")
        CSW_EN = 1'b1;
     else if (CSWin == 3'b011 && CSDECODE_A == "0b011")
        CSW_EN = 1'b1;
     else
        CSW_EN = 1'b0;
  end

// chip select R decode
  always @ (CSRin)
  begin
     if (CSRin == 3'b000 && CSDECODE_B == "0b000")
        csr_en = 1'b1;
     else if (CSRin == 3'b001 && CSDECODE_B == "0b001")
        csr_en = 1'b1;
     else if (CSRin == 3'b010 && CSDECODE_B == "0b010")
        csr_en = 1'b1;
     else if (CSRin == 3'b011 && CSDECODE_B == "0b011")
        csr_en = 1'b1;
     else
        csr_en = 1'b0;
  end
*/
wire  csw_en = csa0_node & csa1_node & csa2_node;
wire  csr_en = csb0_node & csb1_node & csb2_node;

assign DIN_node = (DWW_VALUE == 1) ? DIN[0] :
             (DWW_VALUE == 2) ? DIN[1:0] :
             (DWW_VALUE == 4) ? DIN[3:0] :
             (DWW_VALUE == 9) ? DIN[8:0] : DIN[17:0];
   
   not (SR_pur, SRN_pur);
   not (SR1, SRN);
   or INST1 (RST_sig1, RST_node, SR1);
   or INST2 (RPRST_sig1, RPRST_node, SR1);


   always @ (posedge WCLK_node or posedge RST_sig1)
   begin
      if (RST_sig1 == 1'b1)
         RST_sig2 <= 1'b1;
      else
         RST_sig2 <= 1'b0;
   end
                                                                                             
   always @ (RST_sig1 or RST_sig2)
   begin
      if (ASYNC_RESET_RELEASE == "SYNC" && RESETMODE == "ASYNC")
      begin
         RST_sig <= RST_sig2;
      end
      else
      begin
         RST_sig <= RST_sig1;
      end
   end
                                                                                             
   always @ (posedge RCLK_node or posedge RPRST_sig1)
   begin
      if (RPRST_sig1 == 1'b1)
         RPRST_sig2 <= 1'b1;
      else
         RPRST_sig2 <= 1'b0;
   end

   always @ (RPRST_sig1 or RPRST_sig2)
   begin
      if (ASYNC_RESET_RELEASE == "SYNC" && RESETMODE == "ASYNC")
      begin
         RPRST_sig <= RPRST_sig2;
      end
      else
      begin
         RPRST_sig <= RPRST_sig1;
      end
   end

  always @(posedge WCLK_node)
  begin
     RPRST_reg1 <= RPRST_sig;
     RPRST_reg2 <= RPRST_reg1;
  end
      
  always @(RST_sig or RPRST_sig or RPRST_reg1)
  begin
     if (RST_sig == 1)
     begin
        assign ADW_node = 14'b11111111111111;
        assign ADW_node_syncb = 14'b11111111111111;
     end
     else
     begin
        deassign ADW_node;
        deassign ADW_node_syncb;
     end

     if (RPRST_sig == 1 || RST_sig == 1)
     begin
        assign ADR_node = 14'b11111111111111;
     end
     else
     begin
        deassign ADR_node;
     end

     if (RPRST_reg1 == 1 || RST_sig == 1)
     begin
        assign ADR_node_syncb = 14'b11111111111111;
     end
     else
     begin
        deassign ADR_node_syncb;
     end
  end

  always @(SR1)
  begin
     if (SR1 == 1)
     begin
        assign DO_reg = 0;
     end
     else
     begin
        deassign DO_reg;
     end
  end

  always @(SR_pur or DIN)
  begin
     if (SR_pur == 1)
     begin
        assign DIN_reg = 0;
     end
     else
     begin
        deassign DIN_reg;
     end
  end

  always @(posedge WCLK_node)
  begin
     if (csw_en == 1 && WRE_node == 1)
        DIN_reg_sync <= DIN;
  end

  always @(DIN_reg_sync)
  begin
     DIN_reg = DIN_reg_sync;
  end
 
  always @(posedge WCLK_node)
  begin
     if (csw_en == 1 && WRE_node == 1)
     begin
        ADW_node <= ADW_node + 1;
     end
  end

  always @(posedge RCLK_node)
  begin
        ADW_node_syncb <= ADW_node;
  end

  always @(posedge RCLK_node)
  begin
     if (csr_en == 1 && RDE_node == 1)
     begin
        ADR_node <= ADR_node + 1;
     end
  end

  always @(posedge WCLK_node)
  begin
        ADR_node_syncb <= ADR_node;
  end

  always @(DIN_reg or ADW_node)
  begin
     WADDR = ADW_node[ADDR_WIDTH_W - 1:0];

     if ((DWW_VALUE == 18) | (DWW_VALUE == 9))
     begin
        for (i = 0; i < DWW_VALUE; i = i+1)
          begin
             MEM[WADDR * DWW_VALUE + i] = DIN_reg[i];
          end
     end
     else
     begin
        for (i = 0; i < DWW_VALUE; i = i+1)
          begin
             MEM[WADDR * DWW_VALUE + (WADDR / DINv_a) + i] = DIN_reg[i];
          end
     end
  end

  always @(ADR_node or posedge RST_sig or posedge RPRST_sig)
  begin
     RADDR = ADR_node[ADDR_WIDTH_R - 1:0];

     if (RST_sig == 1'b1 || RPRST_sig == 1'b1)
     begin
        DO_node = 0;
     end
     else if (RST_sig == 0 && RPRST_sig == 0)
     begin
        for (i = 0; i < DWR_VALUE; i = i+1)
        begin
           DO_node[i] = MEM[(RADDR * DWR_VALUE) + (RADDR / DINv_b) + i];
        end
     end
  end

  always @(posedge RST_sig or posedge RPRST_sig or posedge RCLK_node)
  begin
     if (RST_sig == 1 || RPRST_sig == 1)
     begin
        DO_reg_async <= 0;
     end
     else
     begin
        if (ORE_node == 1)
           DO_reg_async <= DO_node;
     end
  end

  always @(posedge RCLK_node)
  begin
     if (RST_sig == 1 || RPRST_sig == 1)
     begin
        DO_reg_sync <= 0;
     end
     else
     begin
        if (ORE_node == 1)
           DO_reg_sync <= DO_node;
     end
  end

  always @(DO_reg_sync or DO_reg_async)
  begin
     if (RESETMODE == "ASYNC")
        DO_reg <= DO_reg_async;
     else
        DO_reg <= DO_reg_sync;
  end

  always @(DO_reg or DO_node)
  begin
     if (REGMODE == "OUTREG")
     begin
        DO_int <= DO_reg;
     end
     else
     begin
        DO_int <= DO_node;
     end
  end

  always @(DO_int)
  begin
     if (DWR_VALUE == 1)
        DO_out[0] = DO_int ;
     else if (DWR_VALUE == 2)
        DO_out[1:0] = DO_int ;
     else if (DWR_VALUE == 4)
        DO_out[3:0] = DO_int ;
     else if (DWR_VALUE == 9)
        DO_out[8:0] = DO_int ;
     else if (DWR_VALUE == 18)
     begin
        DO_intb = DO_int ;
        DO_out[17:9] = DO_intb[8:0] ;
        DO_out[8:0] = DO_intb[17:9] ;
     end
  end

// Flag Generation
  
  always @(ADW_node)
  begin
     ADW_var = ADW_node + 1;
     
     if (DWW_VALUE == 1)
        ADWF_node <= ADW_var;
     else if (DWW_VALUE == 2)
        ADWF_node <= {ADW_var, 1'b0};
     else if (DWW_VALUE == 4)
        ADWF_node <= {ADW_var, 2'b00};
     else if (DWW_VALUE == 9)
        ADWF_node <= {ADW_var, 3'b000};
     else if (DWW_VALUE == 18)
        ADWF_node <= {ADW_var, 4'b0000};
  end

  always @(ADW_node_syncb or posedge RPRST_sig or posedge RCLK_node)
  begin
     ADW_var_syncb = ADW_node_syncb + 1;
    
     if (DWW_VALUE == 1)
     begin
        if (RPRST_sig == 1)
           ADWF_node_syncb <= 14'b00000000000000;
        else
           ADWF_node_syncb <= ADW_var_syncb;
     end
     else if (DWW_VALUE == 2)
     begin
        if (RPRST_sig == 1)
           ADWF_node_syncb <= 14'b00000000000000;
        else
           ADWF_node_syncb <= {ADW_var_syncb, 1'b0};
     end
     else if (DWW_VALUE == 4)
     begin
        if (RPRST_sig == 1)
           ADWF_node_syncb <= 14'b00000000000000;
        else
           ADWF_node_syncb <= {ADW_var_syncb, 2'b00};
     end
     else if (DWW_VALUE == 9)
     begin
        if (RPRST_sig == 1)
           ADWF_node_syncb <= 14'b00000000000000;
        else
           ADWF_node_syncb <= {ADW_var_syncb, 3'b000};
     end
     else if (DWW_VALUE == 18)
     begin
        if (RPRST_sig == 1)
           ADWF_node_syncb <= 14'b00000000000000;
        else
           ADWF_node_syncb <= {ADW_var_syncb, 4'b0000};
     end
  end

  always @(ADR_node)
  begin
     ADR_var = ADR_node + 1;
     
     if (DWR_VALUE == 1)
        ADRF_node <= ADR_var;
     else if (DWR_VALUE == 2)
        ADRF_node <= {ADR_var, 1'b0};
     else if (DWR_VALUE == 4)
        ADRF_node <= {ADR_var, 2'b00};
     else if (DWR_VALUE == 9)
        ADRF_node <= {ADR_var, 3'b000};
     else if (DWR_VALUE == 18)
        ADRF_node <= {ADR_var, 4'b0000};
  end

  always @(ADR_node_syncb)
  begin
     ADR_var_syncb = ADR_node_syncb + 1;

     if (DWR_VALUE == 1)
        ADRF_node_syncb <= ADR_var_syncb;
     else if (DWR_VALUE == 2)
        ADRF_node_syncb <= {ADR_var_syncb, 1'b0};
     else if (DWR_VALUE == 4)
        ADRF_node_syncb <= {ADR_var_syncb, 2'b00};
     else if (DWR_VALUE == 9)
        ADRF_node_syncb <= {ADR_var_syncb, 3'b000};
     else if (DWR_VALUE == 18)
        ADRF_node_syncb <= {ADR_var_syncb, 4'b0000};
  end

assign fifo_words_used_syncr = {ADWF_node_syncb[13] ^ ADRF_node[13], ADWF_node_syncb[12:0]} - {1'b0, ADRF_node[12:0]};

assign fifo_words_used_syncw = {ADRF_node_syncb[13] ^ ADWF_node[13], ADWF_node[12:0]} - {1'b0, ADRF_node_syncb[12:0]};

  assign ae_ptr = AE_POINTER_B[13:0];

  assign empty_ptr = (DWR_VALUE == 1) ? 14'b00000000000000 :
             (DWR_VALUE == 2) ? 14'b00000000000001 :
             (DWR_VALUE == 4) ? 14'b00000000000011 :
             (DWR_VALUE == 9) ? 14'b00000000000111 : 14'b00000000001111;

  buf (empty_flag, (fifo_words_used_syncr <= empty_ptr));
  buf (aempty_flag, (fifo_words_used_syncr <= ae_ptr));
  buf (afull_flag, (fifo_words_used_syncw >= AF_POINTER_B));
  buf (full_flag, (fifo_words_used_syncw >= FULL_POINTER_B));
and (di_check, cea_node, done_sig);
 specify                                            
        (clkr  => dob[0]) = (0:0:0, 0:0:0);
        (clkr  => dob[1]) = (0:0:0, 0:0:0);
        (clkr  => dob[2]) = (0:0:0, 0:0:0);
        (clkr  => dob[3]) = (0:0:0, 0:0:0);
        (clkr  => dob[4]) = (0:0:0, 0:0:0);
        (clkr  => dob[5]) = (0:0:0, 0:0:0);
        (clkr  => dob[6]) = (0:0:0, 0:0:0);
        (clkr  => dob[7]) = (0:0:0, 0:0:0);
        (clkr  => dob[8]) = (0:0:0, 0:0:0);            
        (clkr  => doa[0]) = (0:0:0, 0:0:0);
        (clkr  => doa[1]) = (0:0:0, 0:0:0);
        (clkr  => doa[2]) = (0:0:0, 0:0:0);
        (clkr  => doa[3]) = (0:0:0, 0:0:0);
        (clkr  => doa[4]) = (0:0:0, 0:0:0);
        (clkr  => doa[5]) = (0:0:0, 0:0:0);
        (clkr  => doa[6]) = (0:0:0, 0:0:0);
        (clkr  => doa[7]) = (0:0:0, 0:0:0);
        (clkr  => doa[8]) = (0:0:0, 0:0:0);                   
        (clkw  => full_flag) = (0:0:0, 0:0:0);
        (clkw  => afull_flag) = (0:0:0, 0:0:0);
        (clkr  => empty_flag) = (0:0:0, 0:0:0);
        (clkr  => aempty_flag) = (0:0:0, 0:0:0);
        $recovery (rst,   posedge clkw   &&& (done_sig!=0) , 0:0:0 );
        $removal  (rst,   posedge clkw   &&& (done_sig!=0) , 0:0:0 );
        $recovery (rprst, posedge clkr   &&& (done_sig!=0) , 0:0:0 );
        $removal  (rprst, posedge clkr   &&& (done_sig!=0) , 0:0:0 );
        $recovery (rst,   negedge clkw   &&& (done_sig!=0) , 0:0:0 );
        $removal  (rprst, posedge clkr   &&& (done_sig!=0) , 0:0:0 );
        $recovery (rprst, negedge clkr   &&& (done_sig!=0) , 0:0:0 );
        $removal  (rprst, posedge clkr   &&& (done_sig!=0) , 0:0:0 );
        
                      
	$setuphold (posedge clkw, posedge dia[0] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dia[1] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dia[2] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dia[3] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dia[4] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dia[5] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dia[6] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dia[7] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dia[8] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);		
	$setuphold (posedge clkw, posedge dib[0] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dib[1] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dib[2] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dib[3] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dib[4] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dib[5] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge dib[6] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dib[7] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, posedge dib[8] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);           
	$setuphold (posedge clkw, posedge csw[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge csw[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge csw[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkr, posedge csr[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, posedge csr[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, posedge csr[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);           
	$setuphold (posedge clkw, posedge we 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, posedge re 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);		
	$setuphold (posedge clkr, posedge orea 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, posedge oreb 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, posedge rst 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	$setuphold (posedge clkr, posedge rprst	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dia[0] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dia[1] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dia[2] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dia[3] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dia[4] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dia[5] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dia[6] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dia[7] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dia[8] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);		
	$setuphold (negedge clkw, posedge dib[0] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dib[1] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dib[2] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dib[3] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dib[4] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dib[5] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge dib[6] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dib[7] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, posedge dib[8] &&& (di_check!=1'b0)	, 0:0:0, 0:0:0);           
	$setuphold (negedge clkw, posedge csw[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge csw[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge csw[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkr, posedge csr[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, posedge csr[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, posedge csr[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);           
	$setuphold (negedge clkw, posedge we 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, posedge re 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);		
	$setuphold (negedge clkr, posedge orea 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, posedge oreb 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, posedge rst 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	$setuphold (negedge clkr, posedge rprst	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	
	$setuphold (posedge clkw, negedge dia[0] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dia[1] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dia[2] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dia[3] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dia[4] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dia[5] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dia[6] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dia[7] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dia[8] &&& (di_check!=0)	, 0:0:0, 0:0:0);		
	$setuphold (posedge clkw, negedge dib[0] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dib[1] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dib[2] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dib[3] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dib[4] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dib[5] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge dib[6] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dib[7] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkw, negedge dib[8] &&& (di_check!=0)	, 0:0:0, 0:0:0);           
	$setuphold (posedge clkw, negedge csw[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge csw[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge csw[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);
	$setuphold (posedge clkr, negedge csr[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, negedge csr[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, negedge csr[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);           
	$setuphold (posedge clkw, negedge we 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, negedge re 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);		
	$setuphold (posedge clkr, negedge orea 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkr, negedge oreb 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);	
	$setuphold (posedge clkw, negedge rst 	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	$setuphold (posedge clkr, negedge rprst	 &&& (done_sig!=0) 	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dia[0] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dia[1] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dia[2] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dia[3] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dia[4] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dia[5] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dia[6] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dia[7] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dia[8] &&& (di_check!=0)	, 0:0:0, 0:0:0);		
	$setuphold (negedge clkw, negedge dib[0] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dib[1] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dib[2] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dib[3] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dib[4] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dib[5] &&& (di_check!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge dib[6] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dib[7] &&& (di_check!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkw, negedge dib[8] &&& (di_check!=0)	, 0:0:0, 0:0:0);           
	$setuphold (negedge clkw, negedge csw[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge csw[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge csw[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkr, negedge csr[0] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, negedge csr[1] &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, negedge csr[2] &&& (done_sig!=0)	, 0:0:0, 0:0:0);           
	$setuphold (negedge clkw, negedge we 	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, negedge re 	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);		
	$setuphold (negedge clkr, negedge orea 	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkr, negedge oreb 	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
	$setuphold (negedge clkw, negedge rst 	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);
	$setuphold (negedge clkr, negedge rprst	 &&& (done_sig!=0)	, 0:0:0, 0:0:0);	
      
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
