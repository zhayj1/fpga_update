///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//            PLL block
//   Filename : eg_phy_pll.v
//   Timestamp : Fri Nov  8 09:30:30 CST 2013
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    11/08/13 - Initial version.
//    12/25/2014 reduction IO connection  
//    2/25/2015  suport external feedback mode , align clkc to refclk
//    2016/2/14  change refclk_cycle initial value       
//    2016/5/06  Add function of post scale div2
//    2016/8/04  add user dymanic change interface
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 100 fs
   
module EG_PHY_PLL(clkc,extlock,stdby,refclk,fbclk,reset,load_reg,
                  psdone,psclk,psdown,psstep,psclksel,
                  do,dclk,dcs,dwe,di,daddr);
output [4:0] clkc;      //DEFAULT := (others => '0')   [Template:PLL clock output.]
output extlock;         //DEFAULT := '0'               
input  stdby;           //DEFAULT := '0'               [Template:Clock output control signal.]
input  refclk;          //DEFAULT := '0'               [Template:PLL reference clock input.]
input  fbclk;           //DEFAULT := '0'               [Template:PLL feedback clock input.]
input  reset;           //DEFAULT := '0'               [Template:PLL reset,high active.]
input  load_reg;        //DEFAULT := '0'               
// PLL dynamic phase shift                             
output psdone;          //DEFAULT := '0'               [Template:The dynamic phase shift is complete.]
input  psclk;           //DEFAULT := '0'               [Template:Dynamic phase adjustment clock.]
input  psdown;          //DEFAULT := '0'               [Template:Dynamic phase shift mode, increase or decrease.]
input  psstep;          //DEFAULT := '0'               [Template:Dynamic phase shift trigger signal, high active.]
input  [2:0] psclksel;  //DEFAULT := "000"             [Template:Dynamic phase adjustment Selects one output for phase shift.]
// PLL dynamic configuration user interface
output [7:0]do;         //DEFAULT := (others => '0')   [Template:Dynamic freq adjustment, data read out.]
input  dclk;            //DEFAULT := '0'               [Template:Dynamic freq adjustment clk.]  
input  dcs;             //DEFAULT := '0'               [Template:Dynamic freq adjustment select, high active.]  
input  dwe;             //DEFAULT := '0'               [Template:Dynamic freq adjustment write enable, high active.]
input  [7:0] di;        //DEFAULT := (others => '0')   [Template:Dynamic freq adjustment port data.]  
input  [5:0] daddr;     //DEFAULT := (others => '0')   [Template:Dynamic freq adjustment port addr.]  
tri0 dcs; 
tri0 dwe;
tri1 dclk;
tri1 [5:0]daddr;
tri1 [7:0]di;

wire clkcshot = 1'b0;
wire pllwakesync = 1'b0;
wire resetm      = 1'b0;
wire resetc2     = 1'b0;
wire resetc34    = 1'b0;
wire refshot     = 1'b0;
wire fbshot      = 1'b0;
wire en_pll2io   = 1'b1;
wire [4:0] enclkc= 5'b11111; 

tri1 [2:0] psclksel; 
tri1 reset;
tri1 psclk, psdown, psstep;
tri1 refclk, fbclk;
// PLL dynamic configuration user interface parameter
parameter DYNCFG = "DISABLE";          // "ENABLE","DISABLE".[Template:Dynamic Phase Change InterFace. ]
parameter IF_ESCLKSTSW = "DISABLE";    // "ENABLE","DISABLE".[Template:default Use dynamic clock switch to avoid glich, if_clk will delay 2 cycle after program done.]
//                                     
parameter REFCLK_SEL = "INTERNAL";     // "INTERNAL", "EXTRNAL". [Template:Reference clock select.]

parameter FIN = "100.0000";              //"ENABLE","DISABLE".[Template:no use in fact.]
parameter REFCLK_DIV    = 1;             //  1~128.[Template:Input divide clock.]
parameter FBCLK_DIV     = 1;             //  1~128.[Template:Feedback clock frequency division.]
parameter CLKC0_DIV     = 1;             //  1~128.[Template:Output divide clock 0.]
parameter CLKC1_DIV     = 1;             //  1~128.[Template:Output divide clock 1.]
parameter CLKC2_DIV     = 1;             //  1~128.[Template:Output divide clock 2.]
parameter CLKC3_DIV     = 1;             //  1~128.[Template:Output divide clock 3.]
parameter CLKC4_DIV     = 1;             //  1~128.[Template:Output divide clock 4.]
parameter CLKC0_ENABLE  = "DISABLE";     //  "ENABLE", "DISABLE", "SIGNAL". [Template:Output enable of clock 0.]
parameter CLKC1_ENABLE  = "DISABLE";     //  "ENABLE", "DISABLE", "SIGNAL". [Template:Output enable of clock 1.]
parameter CLKC2_ENABLE  = "DISABLE";     //  "ENABLE", "DISABLE", "SIGNAL". [Template:Output enable of clock 2.]
parameter CLKC3_ENABLE  = "DISABLE";     //  "ENABLE", "DISABLE", "SIGNAL". [Template:Output enable of clock 3.]
parameter CLKC4_ENABLE  = "DISABLE";     //  "ENABLE", "DISABLE", "SIGNAL". [Template:Output enable of clock 4.]

// Post Scale DIV2
parameter CLKC0_DIV2_ENABLE = "DISABLE";   //  "ENABLE", "DISABLE".[Template:Output division 2 enables frequency predivision of clock 0.]
parameter CLKC1_DIV2_ENABLE = "DISABLE";   //  "ENABLE", "DISABLE".[Template:Output division 2 enables frequency predivision of clock 1.]
parameter CLKC2_DIV2_ENABLE = "DISABLE";   //  "ENABLE", "DISABLE".[Template:Output division 2 enables frequency predivision of clock 2.]
parameter CLKC3_DIV2_ENABLE = "DISABLE";   //  "ENABLE", "DISABLE".[Template:Output division 2 enables frequency predivision of clock 3.]
parameter CLKC4_DIV2_ENABLE = "DISABLE";   //  "ENABLE", "DISABLE".[Template:Output division 2 enables frequency predivision of clock 4.]

parameter FEEDBK_MODE   = "NORMAL";    // "NORMAL", "SOURCESYNC", "NOCOMP", "ZERODELAY".[Template:Feedback mode selection.]
parameter FEEDBK_PATH   = "VCO_PHASE_0";  
// VCO_PHASE_0   --- for vco feedback mode 
// CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT   --- for clkc interal feedback mode
// CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT   --- for clkc exteral feedback mode
//parameter INT_FEEDBK_PATH   = "VCO_PHASE_0";  
parameter STDBY_ENABLE  = "ENABLE";   //  ENABLE/DISABLE

parameter CLKC0_FPHASE     = 0;    //  0~7.[Template:Output fine tuning parameters of clock 0.]
parameter CLKC1_FPHASE     = 0;    //  0~7.[Template:Output fine tuning parameters of clock 1.]
parameter CLKC2_FPHASE     = 0;    //  0~7.[Template:Output fine tuning parameters of clock 2.]
parameter CLKC3_FPHASE     = 0;    //  0~7.[Template:Output fine tuning parameters of clock 3.]
parameter CLKC4_FPHASE     = 0;    //  0~7.[Template:Output fine tuning parameters of clock 4.]
parameter CLKC0_CPHASE     = 1;    //  1~127  ,CLKC0_CPHASE <= CLKC0_DIV    [Template:Output coarse tuning parameters of clock 0.]
parameter CLKC1_CPHASE     = 1;    //  1~127  ,CLKC1_CPHASE <= CLKC1_DIV    [Template:Output coarse tuning parameters of clock 1.]
parameter CLKC2_CPHASE     = 1;    //  1~127  ,CLKC2_CPHASE <= CLKC2_DIV    [Template:Output coarse tuning parameters of clock 2.]
parameter CLKC3_CPHASE     = 1;    //  1~127  ,CLKC3_CPHASE <= CLKC3_DIV    [Template:Output coarse tuning parameters of clock 3.]
parameter CLKC4_CPHASE     = 1;    //  1~127  ,CLKC4_CPHASE <= CLKC4_DIV    [Template:Output coarse tuning parameters of clock 4.]

parameter GMC_GAIN         = 7;  // 0~7.[Template:Parameters related to bandwidth Settings.]
parameter GMC_TEST         = 14; // 0~15.
parameter ICP_CURRENT      = 14;   // 1~32.[Template:Parameters related to bandwidth Settings.]
parameter KVCO             = 7;  // 0~7.
parameter LPF_CAPACITOR    = 3;  // 0~3.    [Template:Parameters related to bandwidth Settings.]
parameter LPF_RESISTOR     = 1;    // 1~128.[Template:Parameters related to bandwidth Settings.]

parameter PLLRST_ENA       = "ENABLE";     // "ENABLE", "DISABLE".[Template:PLL reset enable.]
parameter PLLMRST_ENA      = "DISABLE";    // "ENABLE", "DISABLE".
parameter PLLC2RST_ENA     = "DISABLE";    // "ENABLE", "DISABLE".
parameter PLLC34RST_ENA    = "DISABLE";    // "ENABLE", "DISABLE".

parameter PREDIV_MUXC0 = "VCO";    // VCO/CLKMINUS1/CLKPLUS1/REFCLK
parameter PREDIV_MUXC1 = "VCO";    // VCO/CLKMINUS1/CLKPLUS1/REFCLK
parameter PREDIV_MUXC2 = "VCO";    // VCO/CLKMINUS1/CLKPLUS1/REFCLK
parameter PREDIV_MUXC3 = "VCO";    // VCO/CLKMINUS1/CLKPLUS1/REFCLK
parameter PREDIV_MUXC4 = "VCO";    // VCO/CLKMINUS1/CLKPLUS1/REFCLK

parameter ODIV_MUXC0 = "DIV";     // "VCO", "CLKMINUS1", "CLKPLUS1", "REFCLK".[Template:Output path of the advanced divider clock source selection of clock 0.]
parameter ODIV_MUXC1 = "DIV";     // "VCO", "CLKMINUS1", "SSCCLK","REFCLK".[Template:Output path of the advanced divider clock source selection of clock 1.   ]
parameter ODIV_MUXC2 = "DIV";     // "VCO", "CLKMINUS1", "SSCCLK","REFCLK".[Template:Output path of the advanced divider clock source selection of clock 2.   ]
parameter ODIV_MUXC3 = "DIV";     // "VCO", "CLKMINUS1", "SSCCLK","REFCLK".[Template:Output path of the advanced divider clock source selection of clock 3.   ]
parameter ODIV_MUXC4 = "DIV";     // "VCO", "CLKMINUS1", "CLKPLUS1", "REFCLK".[Template:Output path of the advanced divider clock source selection of clock 4.]

parameter FREQ_LOCK_ACCURACY = 2; // 0~3
//parameter PLL_LOCK_DELAY = 200;
parameter PLL_LOCK_MODE = 0;    // 0~7, 2 => sticky, 0 => non-sticky

parameter INTFB_WAKE      = "DISABLE"; //  "ENBALE", "DISABLE".
parameter DPHASE_SOURCE   = "DISABLE"; //  "ENABLE", "DISABLE".
parameter VCO_NORESET     = "DISABLE"; //  "ENABLE", "DISABLE".
parameter STDBY_VCO_ENA   = "DISABLE"; //  "ENABLE", "DISABLE".
parameter NORESET         = "DISABLE"; //  "ENABLE", "DISABLE".
parameter SYNC_ENABLE     = "ENABLE";  //  "ENABLE", "DISABLE".                   

// derive_pll_clocks settings
parameter DERIVE_PLL_CLOCKS = "DISABLE";   //  "ENABLE", "DISABLE".
parameter GEN_BASIC_CLOCK   = "DISABLE";   //  "ENABLE", "DISABLE".

real refclk_cycle_reg;
realtime vco_half_cycle, time_refclk_1st_r, time_refclk_2nd_r, fph_step, refclk_cycle;

reg refclk_1st_rise, refclk_1st_fall;
reg clkvco;
reg [4:0] clkc_en_sram;
reg [4:0] clkc_omux_sram;
reg clkoen_sync;
reg rstdiv0_n_sync;
reg rstdiv2_n_sync;
reg rstdiv3_n_sync;

reg [9:0] lock_cnt;
reg [5:0] fph_sram;
reg [7:0] fphsel;
reg chk_ok;
reg [160:0] param_name;
reg ilock_rls;
reg elock_rls;
reg int_lock, extlock;
reg vco_st;
integer pulse_count;
integer ref_cnt,fb_cnt;
reg refclk_toggle_smpl;
reg refclk_toggle;

reg stdby_sync;
reg vco_st_sync;
reg [3:1] phaset;

wire [7:0] phase;
wire [4:0] clkoen;
wire [4:0] clk_prediv;
wire [4:0] clk_prediv_delay;

wire pll2io;
wire divc4,divc3,divc2,divc1,divc0;
wire mfgouta = 1'b0;
wire mfgoutb = 1'b0;

wire [1:0] prediv_mux0_sram;
wire [1:0] prediv_mux1_sram;
wire [1:0] prediv_mux2_sram;
wire [1:0] prediv_mux3_sram;
wire [1:0] prediv_mux4_sram;

wire [4:0] sclk, load_reg, rotate, direct;
integer fb_path_div;



// PLL dynamic configuration user interface
// user valid address 1~12,16,17
reg [7:0] mem_data[31:0];
reg [4:0] wr_addr;

integer i;

initial begin
  for(i=0;i<=31;i=i+1) begin
    mem_data[i] = 8'b0;
  end
end


task check_daddr;
  input addr;
  begin
    if(addr==0) begin
    $display("Attribute Syntax Error : The Address 0 on pll parameter memory is writen.  This Address can't be written.");
    end 
    if(addr>17 | addr>13 & addr<16) begin
    $display("Attribute Syntax Error : The Address 13,14,15,18~ on pll parameter memory is writen.");
    end 
  end

endtask

buf(dclkt,dclk);
buf(dwet,dwe);
buf(dcst,(dcs & (DYNCFG == "ENABLE")));
always @(posedge dclkt )
    begin         
        if(dcst & dwet) begin
             mem_data[daddr] <= di ;
             check_daddr(daddr);
        end
    end  

always @(posedge dclkt )
    begin         
        if(dcst) begin
             wr_addr <= daddr[4:0] ;
        end
    end  
       
wire [7:0] do = mem_data[wr_addr];
wire [7:0] data00 = mem_data[0];                                   
wire [6:0] fdkclk_divnum ;
wire [6:0] refclk_divnum ;
wire [6:0] chanel0_del;
wire [6:0] chanel1_del;
wire [6:0] chanel2_del;
wire [6:0] chanel3_del;
wire [6:0] chanel4_del;
wire [6:0] chanel0_divnum;
wire [6:0] chanel1_divnum;
wire [6:0] chanel2_divnum;
wire [6:0] chanel3_divnum;
wire [6:0] chanel4_divnum;
wire [6:0] chanel0_delnum;
wire [6:0] chanel1_delnum;
wire [6:0] chanel2_delnum;
wire [6:0] chanel3_delnum;
wire [6:0] chanel4_delnum;

wire [2:0] chanel0_phase;
wire [2:0] chanel1_phase;
wire [2:0] chanel2_phase;
wire [2:0] chanel3_phase;
wire [2:0] chanel4_phase;
wire reserved_1_7;
wire reserved_2_7;
wire reserved_3_7;
wire reserved_4_7; 
wire reserved_5_7;
wire reserved_6_7;
wire reserved_7_7;
wire reserved_8_7; 
wire reserved_9_7;
wire reserved_10_7;
wire reserved_11_7;
wire reserved_12_7; 

assign {reserved_1_7,refclk_divnum} = mem_data[1];
assign {reserved_2_7,feedback_divnum} = mem_data[2];
assign {reserved_3_7,chanel0_delnum} = mem_data[3];
assign {reserved_4_7,chanel0_divnum} = mem_data[4];
assign {reserved_5_7,chanel1_delnum} = mem_data[5];
assign {reserved_6_7,chanel1_divnum} = mem_data[6];
assign {reserved_7_7,chanel2_delnum} = mem_data[7];
assign {reserved_8_7,chanel2_divnum} = mem_data[8];
assign {reserved_9_7,chanel3_delnum} = mem_data[9];
assign {reserved_10_7,chanel3_divnum} = mem_data[10];
assign {reserved_12_7,chanel4_divnum} = mem_data[12];
assign {reserved_11_7,chanel4_delnum} = mem_data[11];


wire [15:0] phasesel = {mem_data[17],mem_data[16]};

assign chanel0_phase[2:0] = phasesel[2:0];
assign chanel1_phase[2:0] = phasesel[5:3];
assign chanel2_phase[2:0] = phasesel[8:6];
assign chanel3_phase[2:0] = phasesel[11:9];
assign chanel4_phase[2:0] = phasesel[14:12];

always @(chanel0_phase)
  begin
    dphase_sel_0.ph_init= chanel0_phase;
  end
always @(chanel1_phase)
  begin
    dphase_sel_1.ph_init= chanel1_phase;
  end
always @(chanel2_phase)
  begin
    dphase_sel_2.ph_init= chanel2_phase;
  end
always @(chanel3_phase)
  begin
    dphase_sel_3.ph_init= chanel3_phase;
  end
always @(chanel4_phase)
  begin
    dphase_sel_4.ph_init= chanel4_phase;
  end



// measure the refclk half cycle

  initial
   begin
     clkc_en_sram      = 5'b00000;
     clkc_omux_sram    = 5'b00000;
     clkoen_sync       = 1'b0;
     rstdiv0_n_sync    = 1'b0;
     rstdiv2_n_sync    = 1'b0;
     rstdiv3_n_sync    = 1'b0;

     lock_cnt = 10'b0000000000;
     fph_sram = 6'b000000;
     chk_ok   = 1'b0;
     clkvco   = 1'b0;
     ilock_rls = 1'b0;
     elock_rls = 1'b0;
     phaset    = 3'b0;
   end

  initial
   begin
      vco_st = 1'b0;
      fph_sram = 6'b0;
      time_refclk_2nd_r    = 0.0;
      time_refclk_1st_r    = 1;
      vco_half_cycle       = 1;
      refclk_cycle         = 1; 
      refclk_1st_rise = 1'b0;
      refclk_1st_fall = 1'b0;
      pulse_count     = 0;
      ref_cnt         = 0;
      fb_cnt          = 0;  
      #1;
      refclk_1st_rise = 1'b1;
      refclk_1st_fall = 1'b1;
      #500;
//      vco_st = 1'b1;
   end

  initial
   begin
     param_name = "REFCLK_DIV";
     chk_ok = para_int_range_chk(REFCLK_DIV,  param_name,  1, 128); 
     param_name = "FBCLK_DIV";
     chk_ok = para_int_range_chk(FBCLK_DIV, param_name,  1, 128); 
     param_name = "CLKC0_DIV";
     chk_ok = para_int_range_chk(CLKC0_DIV, param_name,  1, 128); 
     param_name = "CLKC1_DIV";
     chk_ok = para_int_range_chk(CLKC1_DIV, param_name,  1, 128); 
     param_name = "CLKC2_DIV";
     chk_ok = para_int_range_chk(CLKC2_DIV, param_name,  1, 128); 
     param_name = "CLKC3_DIV";
     chk_ok = para_int_range_chk(CLKC3_DIV, param_name,  1, 128); 
     param_name = "CLKC4_DIV";
     chk_ok = para_int_range_chk(CLKC4_DIV, param_name,  1, 128); 
   end

  initial begin
    case (FEEDBK_PATH)
      "VCO_PHASE_0" : fb_path_div <= 1;
      "CLKC0_INT"   : fb_path_div <= CLKC0_DIV;
      "CLKC0_EXT"   : fb_path_div <= CLKC0_DIV;
      "CLKC1_INT"   : fb_path_div <= CLKC1_DIV;
      "CLKC1_EXT"   : fb_path_div <= CLKC1_DIV;
      "CLKC2_INT"   : fb_path_div <= CLKC2_DIV;
      "CLKC2_EXT"   : fb_path_div <= CLKC2_DIV;
      "CLKC3_INT"   : fb_path_div <= CLKC3_DIV;
      "CLKC3_EXT"   : fb_path_div <= CLKC3_DIV;
      "CLKC4_INT"   : fb_path_div <= CLKC4_DIV;   
      "CLKC4_EXT"   : fb_path_div <= CLKC4_DIV;   
      default   : begin
        $display("attribute syntax error : the attribute FEEDBK_PATH is set to %s. legal values for this attribute are one of : \
                 VCO_PHASE_0, CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT , CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT", FEEDBK_PATH);
        $finish;
      end
    endcase
  end

  //add refclk detection
  //assume input refclk lower limit is higher than 5MHz
  //use 5MHz interval to check if refclk is still available(toggling) 
  initial begin
    refclk_toggle_smpl = 1'b0;
    refclk_toggle      = 1'b0;
    fork
      forever begin
        @(posedge refclk or negedge refclk);
        refclk_toggle = 1'b1;
        #1;
      end
      forever begin
        refclk_toggle_smpl = refclk_toggle;
        refclk_toggle = 1'b0;
        #200;
      end
    join
  end
 
  wire rstm_n   =  (PLLMRST_ENA == "ENABLE")? (~resetm & ~stdby)  : ~stdby;
  wire pllrst_n =  (PLLRST_ENA == "ENABLE")? (rstm_n & ~reset) : rstm_n;
  wire rstdiv2_n =  (PLLC2RST_ENA == "ENABLE")? (~resetc2 & pllrst_n) : pllrst_n;
  wire rstdiv3_n =  (PLLC34RST_ENA == "ENABLE")? (~resetc34 & pllrst_n) : pllrst_n;
                          
  //add refclk detection 
  always @(negedge refclk or negedge pllrst_n or negedge refclk_toggle_smpl) 
    if(~pllrst_n | ~refclk_toggle_smpl)
        pulse_count <= 0;
    else if(pulse_count<30) 
        pulse_count <= pulse_count + 1;    
    
  always @(posedge refclk) begin
    if (pulse_count == 23) begin
      vco_st <= 1'b1;
    end
  end

  always @(posedge refclk) begin
    if (pulse_count >= 20) begin
      time_refclk_1st_r <= $realtime;
      time_refclk_2nd_r <= time_refclk_1st_r;
    end
  end

//always @(posedge refclk) begin
//  if ((pulse_count >= 21)) begin
//    time_refclk_1st_r <= $realtime;
//  end
//end

  always @(posedge refclk) 
  if(pulse_count >= 22) begin: vco_gen
    vco_half_cycle <= (time_refclk_1st_r - time_refclk_2nd_r)*REFCLK_DIV/FBCLK_DIV/fb_path_div/2.0;
    refclk_cycle   <= (time_refclk_1st_r - time_refclk_2nd_r);    
  end  
  
  always @(posedge refclk ) begin
    refclk_cycle_reg <= refclk_cycle;
  end


  always @(posedge refclk)  fph_step <= vco_half_cycle/4;

  reg clkvco_org=0;
  reg clkvco_org1=0;
  reg clkvco_org2=0;

  real clkdiv;

  always @( * ) clkdiv = $itor(FBCLK_DIV*fb_path_div*2)/REFCLK_DIV;

  //div ratio has fractional part
  //add refclk detection
  always @(clkvco_org1 or vco_st_sync or stdby_sync or refclk_toggle_smpl)  
    clkvco_org1 <= #(vco_half_cycle) ~clkvco_org1 & ~stdby_sync & vco_st_sync & refclk_toggle_smpl;

  //div ratio has no fractional part
  always @(posedge refclk) begin
    if(~stdby_sync & vco_st_sync) begin
      clkvco_org2 = ~clkvco_org2;
      repeat( clkdiv - 1 ) begin
        clkvco_org2 =  #(vco_half_cycle) ~clkvco_org2 ;
      end
    end
  //else
  //  clkvco_org2 = 0;
  end

  always @(clkvco_org1 or clkvco_org2) begin
    if( clkdiv == $rtoi(clkdiv) )
	clkvco_org <= clkvco_org2;
    else
        clkvco_org <= clkvco_org1;
  end
       
  always @(clkvco_org) begin
    if( clkdiv == $rtoi(clkdiv) )
      clkvco <=                                   clkvco_org ;  //aligned already
    else
      clkvco <= #(refclk_cycle - vco_half_cycle)  clkvco_org ;  //align posedge of clkvco to  posedge of refclk
  end


  always @(posedge refclk or negedge pllrst_n) begin
    if(!pllrst_n) stdby_sync <= 1'b0;
    else          stdby_sync <= stdby;
  end

  always @(posedge refclk or negedge pllrst_n) begin
    if(!pllrst_n) vco_st_sync <= 1'b0;
    else          vco_st_sync <= vco_st;
  end

  always @(clkvco) begin
  //#(fph_step)   phaset[1] <= clkvco;
                  phaset[1] <= #(fph_step) clkvco;
  end
  
  always @(clkvco) begin
  //#(fph_step*2) phaset[2] <= clkvco;
                  phaset[2] <= #(fph_step*2) clkvco;
  end
  
  always @(clkvco) begin
  //#(fph_step*3) phaset[3] <= clkvco;
                  phaset[3] <= #(fph_step*3) clkvco;
  end
  
  assign phase[7:0] = {~phaset[3:1],~clkvco,phaset[3:1],clkvco};
  wire vco_p0 = clkvco;

// Phase select
  wire [4:0] phdone;
  wire psdone = &phdone;
  
  wire ld_reg_i     = (DPHASE_SOURCE == "ENABLE")? clkcshot : fph_sram[0];
  wire phstep_i     = (DPHASE_SOURCE == "ENABLE")? psstep: fph_sram[1];
  wire phupdown_i = (DPHASE_SOURCE == "ENABLE")? psdown : fph_sram[2];
  wire [2:0] phsel  = (DPHASE_SOURCE == "ENABLE")? psclksel : fph_sram[5:3];

  always @(phsel) begin
    case(phsel)
      3'b000 : fphsel <= 8'b00000001;
      3'b001 : fphsel <= 8'b00000010;
      3'b010 : fphsel <= 8'b00000100;
      3'b011 : fphsel <= 8'b00001000;
      3'b100 : fphsel <= 8'b00010000;
      default: fphsel <= 8'b10000000;
    endcase
  end

  assign sclk      = fphsel[4:0] & {5{psclk}};
  assign rotate    = fphsel[4:0] & {5{phstep_i}};
  assign direct    = fphsel[4:0] & {5{phupdown_i}};
  assign load_reg  = {5{ld_reg_i}};
  
    
  eg_dphase_sel dphase_sel_0 (.clko(phc0), .phdone(phdone[0]), .rotate(rotate[0]), .direct(direct[0]),
                              .phase(phase), .psclk(sclk[0]), .rst_n(pllrst_n), .fphactive(fphsel[0]));

  eg_dphase_sel dphase_sel_1 (.clko(phc1), .phdone(phdone[1]), .rotate(rotate[1]), .direct(direct[1]),
                              .phase(phase), .psclk(sclk[1]), .rst_n(pllrst_n), .fphactive(fphsel[1]));

  eg_dphase_sel dphase_sel_2 (.clko(phc2), .phdone(phdone[2]), .rotate(rotate[2]), .direct(direct[2]),
                              .phase(phase), .psclk(sclk[2]), .rst_n(pllrst_n), .fphactive(fphsel[2]));

  eg_dphase_sel dphase_sel_3 (.clko(phc3), .phdone(phdone[3]), .rotate(rotate[3]), .direct(direct[3]),
                              .phase(phase), .psclk(sclk[3]), .rst_n(pllrst_n), .fphactive(fphsel[3]));

  eg_dphase_sel dphase_sel_4 (.clko(phc4), .phdone(phdone[4]), .rotate(rotate[4]), .direct(direct[4]),
                              .phase(phase), .psclk(sclk[4]), .rst_n(pllrst_n), .fphactive(fphsel[4]));

  defparam  dphase_sel_0.PH_INIT_PARA = CLKC0_FPHASE;
  defparam  dphase_sel_1.PH_INIT_PARA = CLKC1_FPHASE;
  defparam  dphase_sel_2.PH_INIT_PARA = CLKC2_FPHASE;
  defparam  dphase_sel_3.PH_INIT_PARA = CLKC3_FPHASE;
  defparam  dphase_sel_4.PH_INIT_PARA = CLKC4_FPHASE;

  always @* begin
    dphase_sel_0.vco_hcycle <= vco_half_cycle;
    dphase_sel_1.vco_hcycle <= vco_half_cycle;
    dphase_sel_2.vco_hcycle <= vco_half_cycle;
    dphase_sel_3.vco_hcycle <= vco_half_cycle;
    dphase_sel_4.vco_hcycle <= vco_half_cycle;
  end

  wire ph7 = phase[7];

// clkc output premux select

    prediv_mux xpmuxsel_0 (.prediv_mux_sram(prediv_mux0_sram));
    prediv_mux xpmuxsel_1 (.prediv_mux_sram(prediv_mux1_sram));
    prediv_mux xpmuxsel_2 (.prediv_mux_sram(prediv_mux2_sram));
    prediv_mux xpmuxsel_3 (.prediv_mux_sram(prediv_mux3_sram));
    prediv_mux xpmuxsel_4 (.prediv_mux_sram(prediv_mux4_sram));

    defparam xpmuxsel_0.MUX_SEL = PREDIV_MUXC0;
    defparam xpmuxsel_1.MUX_SEL = PREDIV_MUXC1;
    defparam xpmuxsel_2.MUX_SEL = PREDIV_MUXC2;
    defparam xpmuxsel_3.MUX_SEL = PREDIV_MUXC3;
    defparam xpmuxsel_4.MUX_SEL = PREDIV_MUXC4;

  initial begin

// clkc output en

    case (CLKC0_ENABLE)
      "ENABLE"  : clkc_en_sram[0] <= 1'b1;
      "DISABLE" : clkc_en_sram[0] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute CLKC0_ENABLE on pll instance %m is set to %s. legal values for this attribute are ENABLE or DISABLE.", CLKC0_ENABLE);
        $finish;
      end
    endcase

    case (CLKC1_ENABLE)
      "ENABLE"  : clkc_en_sram[1] <= 1'b1;
      "DISABLE" : clkc_en_sram[1] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute CLKC1_ENABLE on pll instance %m is set to %s. legal values for this attribute are ENABLE or DISABLE.", CLKC1_ENABLE);
        $finish;
      end
    endcase

    case (CLKC2_ENABLE)
      "ENABLE"  : clkc_en_sram[2] <= 1'b1;
      "DISABLE" : clkc_en_sram[2] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute CLKC2_ENABLE on pll instance %m is set to %s. legal values for this attribute are ENABLE or DISABLE.", CLKC2_ENABLE);
        $finish;
      end
    endcase

    case (CLKC3_ENABLE)
      "ENABLE"  : clkc_en_sram[3] <= 1'b1;
      "DISABLE" : clkc_en_sram[3] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute CLKC3_ENABLE on pll instance %m is set to %s. legal values for this attribute are ENABLE or DISABLE.", CLKC3_ENABLE);
        $finish;
      end
    endcase

    case (CLKC4_ENABLE)
      "ENABLE"  : clkc_en_sram[4] <= 1'b1;
      "DISABLE" : clkc_en_sram[4] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute CLKC4_ENABLE on pll instance %m is set to %s. legal values for this attribute are ENABLE or DISABLE.", CLKC4_ENABLE);
        $finish;
      end
    endcase

// omux
    case (ODIV_MUXC0)
      "DIV"     : clkc_omux_sram[0] <= 1'b1;
      "REFCLK"  : clkc_omux_sram[0] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute ODIV_MUXC0 on pll instance %m is set to %s. legal values for this attribute are DIV or REFCLK.", ODIV_MUXC0);
        $finish;
      end
    endcase

    case (ODIV_MUXC1)
      "DIV"     : clkc_omux_sram[1] <= 1'b1;
      "REFCLK"  : clkc_omux_sram[1] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute ODIV_MUXC1 on pll instance %m is set to %s. legal values for this attribute are DIV or REFCLK.", ODIV_MUXC1);
        $finish;
      end
    endcase

    case (ODIV_MUXC2)
      "DIV"     : clkc_omux_sram[2] <= 1'b1;
      "REFCLK"  : clkc_omux_sram[2] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute ODIV_MUXC2 on pll instance %m is set to %s. legal values for this attribute are DIV or REFCLK.", ODIV_MUXC2);
        $finish;
      end
    endcase

    case (ODIV_MUXC3)
      "DIV"     : clkc_omux_sram[3] <= 1'b1;
      "REFCLK"  : clkc_omux_sram[3] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute ODIV_MUXC3 on pll instance %m is set to %s. legal values for this attribute are DIV or REFCLK.", ODIV_MUXC3);
        $finish;
      end
    endcase

    case (ODIV_MUXC4)
      "DIV"     : clkc_omux_sram[4] <= 1'b1;
      "REFCLK"  : clkc_omux_sram[4] <= 1'b0;
      default   : begin
        $display("attribute syntax error : the attribute ODIV_MUXC4 on pll instance %m is set to %s. legal values for this attribute are DIV or REFCLK.", ODIV_MUXC4);
        $finish;
      end
    endcase
  end


    wire [4:0] enclkco = clkc_en_sram & enclkc;
    wire [4:0] clkc_fb = {divc4,divc3,divc2,divc1,divc0};
    wire [4:0] clkomux = clkc_omux_sram & clkc_fb | ~clkc_omux_sram & {4{refclk}};

  eg_pll_div2 xdiv2_0 (.out(phc0div2), .clk(phc0), .rst_n(rstdiv0_n_sync));
  eg_pll_div2 xdiv2_1 (.out(phc1div2), .clk(phc1), .rst_n(rstdiv0_n_sync));
  eg_pll_div2 xdiv2_2 (.out(phc2div2), .clk(phc2), .rst_n(rstdiv2_n_sync));
  eg_pll_div2 xdiv2_3 (.out(phc3div2), .clk(phc3), .rst_n(rstdiv3_n_sync));
  eg_pll_div2 xdiv2_4 (.out(phc4div2), .clk(phc4), .rst_n(rstdiv3_n_sync));

  defparam xdiv2_0.DIV2_ENABLE = CLKC0_DIV2_ENABLE;
  defparam xdiv2_1.DIV2_ENABLE = CLKC1_DIV2_ENABLE;
  defparam xdiv2_2.DIV2_ENABLE = CLKC2_DIV2_ENABLE;
  defparam xdiv2_3.DIV2_ENABLE = CLKC3_DIV2_ENABLE;
  defparam xdiv2_4.DIV2_ENABLE = CLKC4_DIV2_ENABLE;

  eg_clko_premux xclko_premux_0 (.clko(clk_prediv[0]), .d({refclk,divc1,divc4,phc0div2}), .sd(prediv_mux0_sram[1:0]));
  eg_clko_premux xclko_premux_1 (.clko(clk_prediv[1]), .d({refclk,divc2,divc0,phc1div2}), .sd(prediv_mux1_sram[1:0]));
  eg_clko_premux xclko_premux_2 (.clko(clk_prediv[2]), .d({refclk,divc3,divc1,phc2div2}), .sd(prediv_mux2_sram[1:0]));
  eg_clko_premux xclko_premux_3 (.clko(clk_prediv[3]), .d({refclk,divc4,divc2,phc3div2}), .sd(prediv_mux3_sram[1:0]));
  eg_clko_premux xclko_premux_4 (.clko(clk_prediv[4]), .d({refclk,divc0,divc3,phc4div2}), .sd(prediv_mux4_sram[1:0]));
  eg_clko_premux xclko_premux_ph7 (.clko(phase7), .d({refclk,1'b0,1'b0,ph7}), .sd({stdby,stdby}));

  assign clk_prediv_delay = clk_prediv;
  eg_pll_div128 xdivc0 (.out(divc0), .shot(load_reg[0]), .clk(clk_prediv[0]), .clk_delay(clk_prediv_delay[0]), .rst_n(rstdiv0_n_sync));
  defparam xdivc0.DIV = CLKC0_DIV-1;
  defparam xdivc0.DIP = CLKC0_CPHASE;

  eg_pll_div128 xdivc1 (.out(divc1), .shot(load_reg[1]), .clk(clk_prediv[1]), .clk_delay(clk_prediv_delay[1]), .rst_n(rstdiv0_n_sync));
  defparam xdivc1.DIV = CLKC1_DIV-1;
  defparam xdivc1.DIP = CLKC1_CPHASE;

  eg_pll_div128 xdivc2 (.out(divc2), .shot(load_reg[2]), .clk(clk_prediv[2]), .clk_delay(clk_prediv_delay[2]), .rst_n(rstdiv2_n_sync));
  defparam xdivc2.DIV = CLKC2_DIV-1;
  defparam xdivc2.DIP = CLKC2_CPHASE;

  eg_pll_div128 xdivc3 (.out(divc3), .shot(load_reg[3]), .clk(clk_prediv[3]), .clk_delay(clk_prediv_delay[3]), .rst_n(rstdiv3_n_sync));
  defparam xdivc3.DIV = CLKC3_DIV-1;
  defparam xdivc3.DIP = CLKC3_CPHASE;

  eg_pll_div128 xdivc4 (.out(divc4), .shot(load_reg[4]), .clk(clk_prediv[4]), .clk_delay(clk_prediv_delay[4]), .rst_n(rstdiv3_n_sync));
  defparam xdivc4.DIV = CLKC4_DIV-1;
  defparam xdivc4.DIP = CLKC4_CPHASE;

  always @(posedge clkomux[0] or negedge rstdiv0_n_sync) begin
    if(!rstdiv0_n_sync)  clkoen_sync <= 1'b0;
    else clkoen_sync <= enclkco[0];
  end

  always @(posedge phase7 or negedge pllrst_n) begin
    if(!pllrst_n)  rstdiv0_n_sync <= 1'b0;
    else rstdiv0_n_sync <= pllrst_n;
  end

  wire rstdiv2_ni = pllrst_n & rstdiv2_n;
  always @(posedge phase7 or negedge rstdiv2_ni) begin
    if(!rstdiv2_ni)  rstdiv2_n_sync <= 1'b0;
    else rstdiv2_n_sync <= rstdiv2_ni;
  end

  wire rstdiv3_ni = pllrst_n & rstdiv3_n;
  always @(posedge phase7 or negedge rstdiv3_ni) begin
    if(!rstdiv3_ni)  rstdiv3_n_sync <= 1'b0;
    else rstdiv3_n_sync <= rstdiv3_ni;
  end

  wire sync2c0 = (SYNC_ENABLE == "ENABLE")? 1'b1 : 1'b0;
  eg_clko_ctrl xclko_ctrl0 (.clko_en_o(clkoen[0]), .clko_en_i(enclkco[0]), .clko_en_sync(clkoen_sync),
                            .sync2c0(sync2c0), .clk(clkomux[0]), .rst_n(rstdiv0_n_sync));

  eg_clko_ctrl xclko_ctrl1 (.clko_en_o(clkoen[1]), .clko_en_i(enclkco[1]), .clko_en_sync(clkoen_sync),
                            .sync2c0(sync2c0), .clk(clkomux[1]), .rst_n(rstdiv0_n_sync));

  eg_clko_ctrl xclko_ctrl2 (.clko_en_o(clkoen[2]), .clko_en_i(enclkco[2]), .clko_en_sync(clkoen_sync),
                            .sync2c0(sync2c0), .clk(clkomux[2]), .rst_n(rstdiv0_n_sync));

  eg_clko_ctrl xclko_ctrl3 (.clko_en_o(clkoen[3]), .clko_en_i(enclkco[3]), .clko_en_sync(clkoen_sync),
                            .sync2c0(sync2c0), .clk(clkomux[3]), .rst_n(rstdiv0_n_sync));

  eg_clko_ctrl xclko_ctrl4 (.clko_en_o(clkoen[4]), .clko_en_i(enclkco[4]), .clko_en_sync(clkoen_sync),
                            .sync2c0(sync2c0), .clk(clkomux[4]), .rst_n(rstdiv0_n_sync));

  always @(posedge phase7 or negedge pllrst_n) begin
    if(!pllrst_n) lock_cnt <= 9'b0;
    else lock_cnt <= lock_cnt + 1;
  end

  always @(lock_cnt) begin
    case(PLL_LOCK_MODE)
      0: begin ilock_rls <= &lock_cnt[6:0]; elock_rls <= &lock_cnt[7:0]; end
      1: begin ilock_rls <= &lock_cnt[7:0]; elock_rls <= &lock_cnt[8:0]; end
      2: begin ilock_rls <= &lock_cnt[8:0]; elock_rls <= &lock_cnt[9:0]; end
      default   : begin
        $display("attribute syntax error : the attribute PLL_LOCK_MODE on pll instance %m is set to %s. legal values for this attribute are 0 to 2.", PLL_LOCK_MODE);
        $finish;
      end
    endcase
  end

  always @(posedge phase7 or negedge pllrst_n) begin
    if(!pllrst_n) int_lock <= 1'b0;
    else if(ilock_rls) int_lock <= 1'b1;
  end

    reg fbclk4lock;
	always @ * begin

    case (FEEDBK_PATH)
      "VCO_PHASE_0" : fbclk4lock <= phase7;
      "SSCCLK"      : fbclk4lock <= divc0;
      "CLKC0_INT"   : fbclk4lock <= divc0;
      "CLKC0_EXT"   : fbclk4lock <= divc0;
      "CLKC1_INT"   : fbclk4lock <= divc1;
      "CLKC1_EXT"   : fbclk4lock <= divc1;
      "CLKC2_INT"   : fbclk4lock <= divc2;
      "CLKC2_EXT"   : fbclk4lock <= divc2;
      "CLKC3_INT"   : fbclk4lock <= divc3;
      "CLKC3_EXT"   : fbclk4lock <= divc3;
      "CLKC4_INT"   : fbclk4lock <= divc4;
      "CLKC4_EXT"   : fbclk4lock <= divc4;
    endcase
  end
  reg[3:0] fakelockcnt;  

  real  tmp_time_value;
  real  tmp_time_value2;
  real  tmp_time_value3;

  always @* begin
  tmp_time_value2 =(refclk_cycle - refclk_cycle_reg);
  tmp_time_value3 =(refclk_cycle - refclk_cycle_reg)*100000000;
  tmp_time_value = $rtoi((refclk_cycle - refclk_cycle_reg)*100000000);
  end

  always @ (posedge fbclk4lock or negedge pllrst_n) begin
   if(!pllrst_n | ((pulse_count >= 22) && tmp_time_value!=0))  fakelockcnt <= 4'b0;
   //if(!pllrst_n)  fakelockcnt <= 4'b0;
   else if (fakelockcnt < 4'b0110) fakelockcnt <= fakelockcnt+ 4'b1;

  end

  //add refclk detection
  always @(posedge phase7 or negedge pllrst_n or negedge refclk_toggle_smpl) begin
    if(!pllrst_n | !refclk_toggle_smpl || tmp_time_value!=0) extlock <= 1'b0;
    else if(elock_rls && fakelockcnt == 4'b0110)                  extlock <= 1'b1;
  end

  assign pll2io   = clkc[0] & en_pll2io;
  assign clkc = clkoen & clkomux;

  function  para_int_range_chk;
   input para_in; 
   input reg [160:0] para_name;
   input range_low;
   input range_high;

   integer para_in;
   integer range_low;
   integer  range_high;

   begin
        $display("******************** : The Attribute %s on pll instance %m is set to %d.  Legal values for this attribute are %d to %d.", para_name, para_in, range_low, range_high);
     if ( para_in < range_low || para_in > range_high) begin
        $display("Attribute Syntax Error : The Attribute %s on pll instance %m is set to %d.  Legal values for this attribute are %d to %d.", para_name, para_in, range_low, range_high);
        $finish;
     end
     para_int_range_chk = 1'b1;
   end
  endfunction

 specify                                      
        (refclk  *> clkc) = (0:0:0, 0:0:0);
        (refclk  *> extlock) = (0:0:0, 0:0:0);
        (dclk  *> do) = (0:0:0, 0:0:0);
        (psclk => psdone) = (0:0:0, 0:0:0);
	
	$setuphold (posedge psclk, psdown 	, 0:0:0, 0:0:0);
	$setuphold (posedge psclk, psstep 	, 0:0:0, 0:0:0);
	$setuphold (posedge psclk, psclksel 	, 0:0:0, 0:0:0);	
	$setuphold (posedge dclk, di 	, 0:0:0, 0:0:0);	
	$setuphold (posedge dclk, daddr , 0:0:0, 0:0:0);	
	$setuphold (posedge dclk, dcs 	, 0:0:0, 0:0:0);
	$setuphold (posedge dclk, dwe 	, 0:0:0, 0:0:0);		
	
 endspecify


endmodule

//-------------------------------------------------------------------------
// sub modules
//-------------------------------------------------------------------------

  module prediv_mux(prediv_mux_sram);
    output [1:0] prediv_mux_sram;

    parameter MUX_SEL = "VCO";
    reg [1:0] prediv_mux_sram;

//    always @ (*) begin
    initial begin
      case (MUX_SEL)
        "VCO"       : prediv_mux_sram <= 2'b00;
        "CLKMINUS1" : prediv_mux_sram <= 2'b01;
        "CLKPLUS1"  : prediv_mux_sram <= 2'b10;
        "REFCLK"    : prediv_mux_sram <= 2'b11;
        default   : begin
          $display("attribute syntax error : the attribute MUX_SEL on pll instance %m is set to %s. legal values for this attribute are VCO/CLKMINUS1/CLKPLUS1/REFCLK.", MUX_SEL);
          $finish;
        end
      endcase
    end
  endmodule

module eg_dphase_sel (clko, phdone, rotate, direct, phase, psclk, rst_n, fphactive);
  
  output clko, phdone;
  input  rotate, direct, psclk, rst_n, fphactive;
  input  [7:0] phase;
  
  reg [2:0] ph_init;
  reg [2:0] ph_sel;
  reg clko;
  reg [3:0] phdone_r;

  realtime vco_hcycle;


  initial begin
    phdone_r = 4'b0;
    vco_hcycle = 1;
    #1; ph_sel = ph_init;
  end
  
  parameter PH_INIT_PARA = 0 ;
  
  always @ (rst_n) begin
    case(PH_INIT_PARA)
      0 : ph_init     <= 3'b000;
      1 : ph_init     <= 3'b001;
      2 : ph_init     <= 3'b010;
      3 : ph_init     <= 3'b011;
      4 : ph_init     <= 3'b100;
      5 : ph_init     <= 3'b101;
      6 : ph_init     <= 3'b110;
      7 : ph_init     <= 3'b111;
      default: ph_init  <= 3'b000;
    endcase
  end
  

  always @(ph_sel or phase) begin
    case(ph_sel)
      3'b000: clko <= phase[0];
      3'b001: clko <= phase[1];
      3'b010: clko <= phase[2];
      3'b011: clko <= phase[3];
      3'b100: clko <= phase[4];
      3'b101: clko <= phase[5];
      3'b110: clko <= phase[6];
      3'b111: clko <= phase[7];
    endcase
  end

  assign phdone = ~phdone_r[1] | phdone_r[3]; // & fphactive;

  always @ (posedge psclk or negedge rst_n) begin
    if(!rst_n) phdone_r[3:0] <= 4'b0;
    else begin
      phdone_r[3:0] <= {phdone_r[2:0],rotate};
    end
  end

  always @ (posedge psclk or negedge rst_n) begin
    if(!rst_n)  ph_sel <= ph_init;
    else if(phdone_r[1] & ~phdone_r[2]) begin
      if(direct)    ph_sel <= #0.001 ph_sel - 1;
      else          ph_sel <= #(0.01 + vco_hcycle*(ph_sel+1)/4) ph_sel + 1;
    end
  end   

endmodule


module eg_clko_premux (clko, d, sd);

  output clko;
  input [3:0] d;
  input [1:0] sd;

  reg clko;

  always @(sd or d) begin
    case (sd)
      2'b00: clko <= d[0];
      2'b01: clko <= d[1];
      2'b10: clko <= d[2];
      2'b11: clko <= d[3];
    endcase
  end

endmodule

module eg_clko_ctrl (clko_en_o, clko_en_i, clko_en_sync, sync2c0, clk, rst_n);

  output clko_en_o;  // Synced
  input  clko_en_i;  // local
  input  clko_en_sync;  // clko_en of c0
  input  sync2c0, clk, rst_n;

  reg clko_en_o;
  
  wire clko_en = sync2c0? (clko_en_sync & clko_en_i) : clko_en_i;
  
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)  clko_en_o <= 1'b0;
    else clko_en_o <= clko_en;
  end

endmodule


module eg_pll_div128 (out, shot, clk, clk_delay, rst_n);

output out;
input shot, clk, rst_n;
input clk_delay;

reg [2:0] lsf_q;
reg rst_n_sync;
reg  [6:0] m_half;
reg [7:0] m_prd;

reg [7:0] count;
reg out_en;

wire rst_n_dly;
assign #0.1 rst_n_dly = rst_n;
  parameter DIV = 7'b0000000;
  parameter DIP = 7'b0000000;

  wire lsf_rst_n = rst_n & ~shot;
  wire lsf_pls   = lsf_q[1] & ~lsf_q[0];
  wire [6:0] divp = lsf_pls? DIP:DIV;

  wire #0.2 out_int= (count<=m_half); 
  wire out=out_int & out_en; 

  always @ (negedge out_int or negedge lsf_rst_n) begin
    if(!lsf_rst_n) lsf_q <= 3'b0;
    else lsf_q <={1'b1, lsf_q[2:1]};
  end


  initial begin
    out_en = 1'b0;
    m_half = 7'b0;
    rst_n_sync = 1'b1;
    count = 8'b0000_0000;
    m_prd = 8'b0000_0000;
  end 

//always @(negedge clk)
  always @(posedge clk)
  //#0.1 rst_n_sync <=      rst_n;
     rst_n_sync <= #0.1 rst_n_dly;

 always @(negedge lsf_pls or negedge rst_n_sync)
   begin
     if(~rst_n_sync) out_en <= 1'b0;
     else if(~lsf_pls) out_en <= 1'b1;
   end  

 always @(posedge out_int or rst_n_sync)
   begin
     if(~rst_n_sync) out_en <= 1'b0;
     else if(lsf_pls) begin m_half <= DIP; m_prd <= DIP*2+1; end
     else begin m_half <= DIV; m_prd <= DIV*2+1; end
   end

 always @(posedge clk_delay or negedge clk_delay or negedge rst_n_sync)
   begin
     if(~rst_n_sync) begin
       count <= 0;
      end
     else if(count==m_prd) begin
       count <= 0;
      end
     else count <= count+1;
  end

endmodule


module eg_pll_div2 (out, clk, rst_n);

output out;
input  clk, rst_n;

reg rst_n_sync;
reg ckd2;
 
  parameter DIV2_ENABLE  = "DISABLE";   //  ENABLE/DISABLE

  initial begin
    ckd2 = 1'b0;
  end 

 always @(posedge clk)
   #0.1 rst_n_sync <= rst_n;

 wire int_rst_n = rst_n_sync & (DIV2_ENABLE == "ENABLE");
 wire out = (DIV2_ENABLE == "ENABLE")? ckd2 : clk;


 always @(posedge clk or negedge int_rst_n)
   begin
     if(~int_rst_n)
       ckd2 <= 1'b0;
     else 
       ckd2 <= ~ckd2;
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
