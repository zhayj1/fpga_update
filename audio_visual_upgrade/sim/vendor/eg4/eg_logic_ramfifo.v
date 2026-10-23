
/////////////////////////////////////////////////////////////////////
//     文件名         async_fifo.v
//     日期           2017-06-05
//     作者           车驰
//     顶层模块       async_fifo.v
//     模块功能描述   异步时钟fifo模块
/////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module EG_LOGIC_RAMFIFO (/*autoarg*/
                   // Inputs
                   rst, di, clk, re, we,
                   // Outputs
                   do, empty_flag, full_flag, rdusedw, wrusedw
                   );
   
   parameter DATA_WIDTH = 8;      //  1~432.                [Template:FIFO bit width of read-write.]
   parameter ADDR_WIDTH = 8;      //  2~15.                 [Template:FIFO bit width of depth.     ]
   parameter SHOWAHEAD = 0;       //  0, 1.                 [Template:1-SHOWAHEAD,0-general.       ]
   parameter IMPLEMENT = "AUTO";  //  "9K", "32K", "AUTO".  [Template:Implementation model.        ]
   
   input                     rst;              //  [Template:Asynchronous reset signal, high active.]   
   input   [DATA_WIDTH-1:0]  di;               //  [Template:Data input.                     ]
   input                     clk;              //  [Template:Read enable.                    ]
   input                     re;               //  [Template:Input clock,high active.        ]
   input                     we;               //  [Template:Write enable,high active.       ]
   output  [DATA_WIDTH-1:0]  do;               //  [Template:Data output.                    ]
   output                    empty_flag;       //  [Template:Empty signal flag.              ]
   output                    full_flag;        //  [Template:Full signal flag.               ]
   output  [ADDR_WIDTH:0]    rdusedw;          //  [Template:Number of data that can be read.]
   output  [ADDR_WIDTH:0]    wrusedw;          //  [Template:Number of written data.         ]
   
   wire                      valid_wrreq;
   wire                      valid_rdreq;
   wire                      int_wrfull;
   wire                      int_rdempty;
   wire    [ADDR_WIDTH:0]    wrptr;
   reg     [ADDR_WIDTH:0]    wrptr_g;
   reg     [ADDR_WIDTH:0]    delayed_wrptr_g;
   wire    [ADDR_WIDTH:0]    rdptr;
   reg     [ADDR_WIDTH:0]    rdptr_g;
   reg     [ADDR_WIDTH:0]    sync_rdptr_g;
   wire    [ADDR_WIDTH:0]    sync_rdptr_g_bin;
   reg     [ADDR_WIDTH:0]    sync_rdptr_g_bin_d1;
   wire    [ADDR_WIDTH:0]    wrptr_g_bin;
   reg     [ADDR_WIDTH:0]    wrptr_g_bin_d1;
   reg     [ADDR_WIDTH:0]    sync_delayed_wrptr_g;
   wire    [ADDR_WIDTH:0]    sync_delayed_wrptr_g_bin;
   reg     [ADDR_WIDTH:0]    sync_delayed_wrptr_g_bin_d1;
   wire    [ADDR_WIDTH:0]    rdptr_g_bin;
   reg     [ADDR_WIDTH:0]    rdptr_g_bin_d1;
   wire                      showahead_empty;
   wire    [ADDR_WIDTH-1:0]  read_addr;
   wire    [ADDR_WIDTH-1:0]  write_addr;
   wire    [ADDR_WIDTH:0]    rdptr_test;
   reg     [ADDR_WIDTH:0]    rdptr_g_test;
   wire                      addr_inc;
   wire                      valid_rdreq_test;
   wire                      int_rdempty_test;
   wire    [DATA_WIDTH-1:0]  ram_q;
   wire    [DATA_WIDTH-1:0]  showahead_q;
   wire    [ADDR_WIDTH-1:0]  read_addr_test;
   wire    [ADDR_WIDTH-1:0]  ram_read_addr;
   wire                      ram_read_req;
   
   assign valid_wrreq = we & ~int_wrfull;
   assign valid_rdreq = re & ~int_rdempty;
   
   generate if (ADDR_WIDTH >= 2) begin: GEN_FULL
   assign int_wrfull = (wrptr_g == {~sync_rdptr_g[ADDR_WIDTH:ADDR_WIDTH-1], sync_rdptr_g[ADDR_WIDTH-2:0]});
   end else begin
   assign int_wrfull = (wrptr_g == ~sync_rdptr_g[ADDR_WIDTH:0]);
   end
   endgenerate
   
   generate if(SHOWAHEAD) begin: GEN_EMPTY
   assign int_rdempty = (sync_delayed_wrptr_g == rdptr_g) | showahead_empty;
   end else begin
   assign int_rdempty = (sync_delayed_wrptr_g == rdptr_g);
   end
   endgenerate
   
   assign full_flag = int_wrfull;
   assign empty_flag = int_rdempty;
   assign read_addr = {(rdptr_g[ADDR_WIDTH]^rdptr_g[ADDR_WIDTH-1]), rdptr_g[ADDR_WIDTH-2:0]};
   assign write_addr = {(wrptr_g[ADDR_WIDTH]^wrptr_g[ADDR_WIDTH-1]), wrptr_g[ADDR_WIDTH-2:0]};
   assign wrusedw = wrptr_g_bin_d1 - sync_rdptr_g_bin_d1;
   assign rdusedw = sync_delayed_wrptr_g_bin_d1 - rdptr_g_bin_d1;
   
   assign read_addr_test = {(rdptr_g_test[ADDR_WIDTH]^rdptr_g_test[ADDR_WIDTH-1]), rdptr_g_test[ADDR_WIDTH-2:0]};
   assign int_rdempty_test = (sync_delayed_wrptr_g == rdptr_g_test);
   assign valid_rdreq_test = addr_inc && !int_rdempty_test;
   
   generate if(SHOWAHEAD) begin: GEN_Q
   assign do = showahead_q;
   end else begin
   assign do = ram_q;
   end
   endgenerate
   
   generate if(SHOWAHEAD) begin: GEN_ADDR
   assign ram_read_addr = read_addr_test;
   end else begin
   assign ram_read_addr = read_addr;
   end
   endgenerate
   
   generate if(SHOWAHEAD) begin: GEN_RDREQ
   assign ram_read_req = valid_rdreq_test;
   end else begin
   assign ram_read_req = valid_rdreq;
   end
   endgenerate
   
   gray_count # (
                 .WIDTH  (ADDR_WIDTH+1),
                 .INIT   (1))
              u1 (
                  .clk     (clk),
                  .enable  (valid_wrreq),
                  .reset   (rst),
                  .cnt     (wrptr));
   
   gray_count # (
                 .WIDTH  (ADDR_WIDTH+1),
                 .INIT  (1))
              u2 (
                  .clk     (clk),
                  .enable  (valid_rdreq),
                  .reset   (rst),
                  .cnt     (rdptr));
   
   gray_count # (
                 .WIDTH  (ADDR_WIDTH+1),
                 .INIT   (1))
              u3 (
                  .clk     (clk),
                  .enable  (valid_rdreq_test),
                  .reset   (rst),
                  .cnt     (rdptr_test));
   
   showahead_buffer # (
                       .DATA_WIDTH  (DATA_WIDTH))
                    u4 (
                        .rstn_i      (~rst),
                        .clk_i       (clk),
                        .ena_i       (!int_rdempty_test),
                        .rd_i        (valid_rdreq),
                        .data_i      (ram_q),
                        .data_o      (showahead_q),
                        .empty_o     (showahead_empty),
                        .addr_inc_o  (addr_inc));
   
    EG_LOGIC_BRAM # (
                     .DATA_WIDTH_A  (DATA_WIDTH),
                     .MODE          ("PDPW"),
                     .ADDR_WIDTH_A  (ADDR_WIDTH),
                     .IMPLEMENT     (IMPLEMENT))
                  u5 (
                      .dia    (di),
                      .addra  (write_addr),
                      .cea    (1'b1),
                      .bea    (0),
                      .ocea   (1'b1),
                      .clka   (clk),
                      .wea    (valid_wrreq),
                      .rsta   (rst),
                      .dib    (0),
                      .addrb  (ram_read_addr),
                      .ceb    (ram_read_req),
                      .beb    (0),
                      .oceb   (1'b1),
                      .clkb   (clk),
                      .web    (1'b0),
                      .rstb   (rst),
                      .doa    (),
                      .dob    (ram_q));
  
   //EG_PHY_BRAM u5 (
   //                .dia    ({1'b0, di}),
   //                .csa    (3'b111),
   //                .addra  ({2'b0, write_addr, 3'b111}),
   //                .cea    (1'b1),
   //                .ocea   (1'b1),
   //                .clka   (clk),
   //                .wea    (valid_wrreq),
   //                .rsta   (rst),
   //                .dib    (0),
   //                .csb    (3'b111),
   //                .addrb  ({2'b0, ram_read_addr, 3'b111}),
   //                .ceb    (ram_read_req),
   //                .oceb   (1'b1),
   //                .clkb   (clk),
   //                .web    (1'b0),
   //                .rstb   (rst),
   //                .doa    (),
   //                .dob    (ram_q));
   
   gray2bin # (
               .WIDTH  (ADDR_WIDTH+1))
            u6 (
                .din   (sync_rdptr_g),
                .dout  (sync_rdptr_g_bin));
                
   gray2bin # (
               .WIDTH  (ADDR_WIDTH+1))
            u7 (
                .din   (wrptr_g),
                .dout  (wrptr_g_bin));
   
   gray2bin # (
               .WIDTH  (ADDR_WIDTH+1))
            u8 (
                .din   (sync_delayed_wrptr_g),
                .dout  (sync_delayed_wrptr_g_bin));
   
   gray2bin # (
               .WIDTH  (ADDR_WIDTH+1))
            u9 (
                .din   (rdptr_g),
                .dout  (rdptr_g_bin));
   
   // wrptr
   always @(posedge clk or posedge rst)
      if(rst) begin
         wrptr_g <= 0;
         delayed_wrptr_g <= 0;
      end else begin
         if(valid_wrreq)
            wrptr_g <= wrptr;
         delayed_wrptr_g <= wrptr_g;
      end
      
   // rdptr
   always @(posedge clk or posedge rst)
      if(rst) begin
         rdptr_g <= 0;
      end else begin
         if(valid_rdreq)
            rdptr_g <= rdptr;
      end
   
   // rdptr_g_test
   always @(posedge clk or posedge rst)
      if(rst) begin
         rdptr_g_test <= 0;
      end else begin
         if(valid_rdreq_test)
            rdptr_g_test <= rdptr_test;
      end
   
   // sync_rdptr_g
   always @(posedge clk or posedge rst)
      if(rst) begin
         sync_rdptr_g <= 0;
         sync_rdptr_g_bin_d1 <= 0;
         wrptr_g_bin_d1 <= 0;
      end else begin
         sync_rdptr_g <= rdptr_g;
         sync_rdptr_g_bin_d1 <= sync_rdptr_g_bin;
         wrptr_g_bin_d1 <= wrptr_g_bin;
      end
   
   // sync_delayed_wrptr_g
   always @(posedge clk or posedge rst)
      if(rst) begin
         sync_delayed_wrptr_g <= 0;
         sync_delayed_wrptr_g_bin_d1 <= 0;
         rdptr_g_bin_d1 <= 0;
      end else begin
         sync_delayed_wrptr_g <= delayed_wrptr_g;
         sync_delayed_wrptr_g_bin_d1 <= sync_delayed_wrptr_g_bin;
         rdptr_g_bin_d1 <= rdptr_g_bin;
      end
   
endmodule
module gray2bin (
                  // Inputs
                  din,
                  // Outputs
                  dout
                  );
                  
   parameter WIDTH = 8;
   
   input   [WIDTH-1:0]  din;
   output  [WIDTH-1:0]  dout;
   
   assign dout[WIDTH-1] = din[WIDTH-1];
   genvar i;
   generate for (i=WIDTH-2;i>=0;i=i-1) begin:G2B
      assign dout[i] = dout[i+1] ^ din[i];
   end
   endgenerate
   
endmodule
module gray_count (
                   // Inputs
                   clk, enable, reset,
                   // Outputs
                   cnt
                   );
                  
   parameter WIDTH = 8;
   parameter INIT  = 0;
   
   input                clk;
   input                enable;
   input                reset;
   output  [WIDTH-1:0]  cnt;
   
   reg     [WIDTH-1:-1] do ; // do is the counter, plus the imaginary bit
   reg     [WIDTH-2:-1] no_ones_below ; // no_ones_below[x] = 1 if there are no 1's in do below do[x]
   wire                 q_msb;// q_msb is a modification to make the msb logic work
   integer i;
   
   assign cnt = do[WIDTH-1:0];
   assign q_msb = do[WIDTH-1] | do[WIDTH-2];
    
   always @ (posedge reset or posedge clk) begin
      if (reset) begin // Resetting involves setting the imaginary bit to 1
         do[-1] <= 0;
         do[WIDTH-1:0] <= INIT;
      end else if (enable) begin // Flip do[i] if lower bits are a 1 followed by all 0's
         do[-1] <= ~do[-1];
         
         for (i = 0; i < WIDTH-1; i = i + 1) begin
            do[i] <= do[i] ^ (do[i-1] & no_ones_below[i-1]);
         do[WIDTH-1] <= do[WIDTH-1] ^ (q_msb & no_ones_below[WIDTH-2]);
         end
      end
   end
   
   always @(*) begin // There are never any 1's beneath the lowest bit
      no_ones_below[-1] <= 1;
      for (i = 0; i < WIDTH-1; i = i + 1)
         no_ones_below[i] <= no_ones_below[i-1] & ~do[i-1];
   end
      
endmodule
module showahead_buffer (/*autoarg*/
                         // Inputs
                         rstn_i, clk_i, ena_i, rd_i, data_i,
                         // Outputs
                         data_o, addr_inc_o, empty_o
                         );
   
   parameter DATA_WIDTH = 8;
   
   localparam IDLE   = 0;
   localparam STATE1 = 1;
   localparam STATE2 = 2;
   localparam STATE3 = 3;
   localparam STATE4 = 4;
   
   input                     rstn_i;
   input                     clk_i;
   input                     ena_i;
   input                     rd_i;
   input   [DATA_WIDTH-1:0]  data_i;
   output  [DATA_WIDTH-1:0]  data_o;
   output                    addr_inc_o;
   output                    empty_o;
   
   reg                       empty_r;
   reg                       empty_o;
   reg                       addr_inc;
   reg     [DATA_WIDTH-1:0]  r1;
   reg     [DATA_WIDTH-1:0]  r2;
   reg     [2:0]             curr_state;
   reg     [2:0]             next_state;
   reg                       s_idle;
   reg                       s_state1;
   reg                       s_state2;
   reg                       s_state3;
   reg                       s_state4;
   
   assign data_o = r2;
   assign addr_inc_o = addr_inc;
   
   // 状态机
   always @(posedge clk_i or negedge rstn_i)
      if (!rstn_i)
         curr_state <= IDLE;
      else
         curr_state <= next_state;
   
   always @(*) begin
      s_idle   = 1'b0;
      s_state1 = 1'b0;
      s_state2 = 1'b0;
      s_state3 = 1'b0;
      s_state4 = 1'b0;
      empty_r   = 1'b0;
      addr_inc = 0;
      case(curr_state)
         IDLE: begin
            next_state = ena_i ? STATE1 : IDLE;
            addr_inc = ena_i;
            empty_r = 1'b1;
            s_idle = 1'b1;
         end
         STATE1: begin
            next_state = (!ena_i && rd_i) ? IDLE:
                         ena_i            ? STATE4:
                                            STATE2;
            addr_inc = ena_i;
            empty_r = (!ena_i && rd_i);
            s_state1 = 1'b1;
         end
         STATE2: begin
            next_state = (ena_i && !rd_i) ? STATE4:
                         rd_i             ? IDLE:
                                            STATE2;
            addr_inc = (ena_i && !rd_i);
            empty_r   = rd_i;
            s_state2 = 1'b1;
         end
         STATE3: begin
            next_state = (!ena_i && rd_i) ? STATE2:
                         rd_i             ? STATE4:
                                            STATE3;
            addr_inc = rd_i;
            s_state3 = 1'b1;
         end
         STATE4: begin
            next_state = (!ena_i && rd_i) ? STATE2:
                         rd_i             ? STATE4:
                                            STATE3;
            addr_inc = rd_i;
            s_state4 = 1'b1;
         end
      default: next_state = IDLE;
      endcase
   end
   
   // 数据寄存
   always @(posedge clk_i or negedge rstn_i)
      if(!rstn_i) begin
         r1 <= 0;
         r2 <= 0;
      end else begin
         if(s_state1) begin
            r1 <= 0;
            r2 <= data_i;
         end else if(s_state2 && ena_i) begin
            r1 <= data_i;
            r2 <= r2;
         end else if(s_state3 && rd_i) begin
            r1 <= data_i;
            r2 <= r1;
         end else if(s_state4 && rd_i) begin
            r1 <= 0;
            r2 <= data_i;
         end else if(s_state4 && !rd_i) begin
            r1 <= data_i;
            r2 <= r2;
         end
      end
   
   // empty_o
   always @(posedge clk_i or negedge rstn_i)
      if(!rstn_i) begin
         empty_o <= 1;
      end else begin
         empty_o <= empty_r;
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
