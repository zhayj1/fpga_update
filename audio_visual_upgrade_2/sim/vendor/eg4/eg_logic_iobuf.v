///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2021 Anlogic, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//
//
//   Vendor : Anlogic
//   Version : 0.1
//   Description : Anlogic Functional Simulation Library Component
//                 EG_LOGIC_IBUF, EG_LOGIC_OBUF, EG_LOGIC_IOTRIBUF,
//                 To be mapped to PAD
//   Filename : eg_logic_iobuf.v
//   Timestamp : Thurs Jan 5 15:20:41 CST 2023
//
///////////////////////////////////////////////////////////////////////////////
//
// Revision:
//    2023-01-15 - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1 ps/1 ps

module EG_LOGIC_IBUF (
  i,
  o
);

input i;    //[Template:Input data (connect directly to top-level port).]
output o;   //[Template:Output data.]

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
KtBg89625ob8gEXFFFnm8TbHlO0L9zBIROiPhUI4EDcgT94A3oMvErDRdkBAGXWc
ogPVgufbM1x1q6pEUpQZkfE6LcUi96xxFLr02QU39+eSroBtwt5cTC9sBTmzN2x6
PjW8jz70EnLhBgIzE/FlvnmcV9FR5aTfWszA4Q62SFU=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
M+jvea+SXgDv/IiODzbw/Ky15g/9xPRCGv9NW6IYewPb+EPrt3D4fM62OuG2nTtj
OOiAby7OT0MCSCClOY9jcDQW43fydXfSqAP31vrTLvI49wQWSmP02o1JqBwNxCcu
CJPcb3/6mgdNFAH1JaiPPDO09yxpo27p6vABGKQziuE=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Ues181WQIMb0vVfwLH2Whcapr2zoBmP5e3piX/n3zNDnLlOLasWyD2gzXsEgj3/t
4dd0gJMtEsafqY97rRV7GQtv5GvkdOVOUOP+KfD6cncVLVK8uDzFGJ25K3pT/HBo
ATr6MabDmtyJQGhegxzhxq+mliyVOP8T1cQwFUGzU8eYScv/o6oLkr4H5yyXAwhL
S0PiYNcyS1OC02mEiagFixgmMdLepo42KYCnUi8UcavT965HQ9UCkguMUy3TS7Nu
jq8nmCUV9fL1zPcH14FsKtwEeB5Ap34mGy+dqo6P9mOqmh5W0NZam4K8OWUdIEAG
3d7UnXcHIvOuvjXJ9EKvNQ==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
n7mkh6v7yWFSL+bzAuWKaF7+zetqdaGSkMoueW9R9helvdkpJe3xndW8Fk49YKeN
G9nA8VbO/uz9oUsrnL8IUR9TVaSQPyGKLOERH8f7QYl8fJEvKRWAevehWAmz5DCq
YzEiYraDDlec+D5C3yqYg3x19tlC9n0QNVK79ejG/jo=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
iF9Q1xJ1gVMo/J5KYb6KocUOr+gOXpf3wElApHkksARpUXkgcFaoGufoNmq6kR4g
Ruxp/vzj+sYdmQg/g5ljeTLAFDI17qtNUobzP4bTL5wyPfSFevP251CIcsP5U+A0
J8YVT3yL+YRzpxu5sDt8dXXUABy8ifY78hUsDd1K3+OLhlUiJULbjnWJ+RFc0RP8
bzcBgz2Xiccb7ig381M6MnyKkdx7eMdxL6viIf2MVPz84o7t3v3E77ER5P2JLbbO
Z8aJkrDVtRbg+DIiBjAt1sAYQJf7wMzmj7GOL0G0uHLTe/9W6Zz1OqVNfAiDdJQ7
6xxTp6Cf1NDUJ0xA7EQd5g==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
H7eF/11QDSooQ+VV/ivIkRaNtGCaNrxnQnuW8j6mFmm75dkYyf4snAZN+c+Z2rG+
unoYqQFY2XEQsArN1Rm5fvQy4oz4DZNJztn/9EXkBDgWHGba9v8R5eC1EiNj27Ny
xzs6kLTWq51eTCij3V2/J2S5fg+rUtSmMOs1Dv5UwHOdClxTg0l3nsNQXA1wHul6
lkGvgd3JVWbPg5WrTtA+ffGMd0DQp3u1r0zlv0lwr6/hhilcBsUKUMRIfAzNEcc8
yMdaVsOBv2qbg9iW6wB9Qk3vg4SJwDZ/Z6w5MEn8hRCPypMdjksF/J3Wp2wNUOck
TMkOdVd/Q6nUiLIcSggEJw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 48)
`pragma protect data_block
BzDUxvq82HEI0h6DVttYHUC87DeVfA1rqDDi6Jz5sOy0qexmlF0jJwme6w0up5vv
`pragma protect end_protected

endmodule

module EG_LOGIC_OBUF (
  i,
  o
);

input i;    //[Template:Input data.]
output o;   //[Template:Output data (connect directly to top-level port).]

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
KtBg89625ob8gEXFFFnm8TbHlO0L9zBIROiPhUI4EDcgT94A3oMvErDRdkBAGXWc
ogPVgufbM1x1q6pEUpQZkfE6LcUi96xxFLr02QU39+eSroBtwt5cTC9sBTmzN2x6
PjW8jz70EnLhBgIzE/FlvnmcV9FR5aTfWszA4Q62SFU=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
M+jvea+SXgDv/IiODzbw/Ky15g/9xPRCGv9NW6IYewPb+EPrt3D4fM62OuG2nTtj
OOiAby7OT0MCSCClOY9jcDQW43fydXfSqAP31vrTLvI49wQWSmP02o1JqBwNxCcu
CJPcb3/6mgdNFAH1JaiPPDO09yxpo27p6vABGKQziuE=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Ues181WQIMb0vVfwLH2Whcapr2zoBmP5e3piX/n3zNDnLlOLasWyD2gzXsEgj3/t
4dd0gJMtEsafqY97rRV7GQtv5GvkdOVOUOP+KfD6cncVLVK8uDzFGJ25K3pT/HBo
ATr6MabDmtyJQGhegxzhxq+mliyVOP8T1cQwFUGzU8eYScv/o6oLkr4H5yyXAwhL
S0PiYNcyS1OC02mEiagFixgmMdLepo42KYCnUi8UcavT965HQ9UCkguMUy3TS7Nu
jq8nmCUV9fL1zPcH14FsKtwEeB5Ap34mGy+dqo6P9mOqmh5W0NZam4K8OWUdIEAG
3d7UnXcHIvOuvjXJ9EKvNQ==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
n7mkh6v7yWFSL+bzAuWKaF7+zetqdaGSkMoueW9R9helvdkpJe3xndW8Fk49YKeN
G9nA8VbO/uz9oUsrnL8IUR9TVaSQPyGKLOERH8f7QYl8fJEvKRWAevehWAmz5DCq
YzEiYraDDlec+D5C3yqYg3x19tlC9n0QNVK79ejG/jo=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
iF9Q1xJ1gVMo/J5KYb6KocUOr+gOXpf3wElApHkksARpUXkgcFaoGufoNmq6kR4g
Ruxp/vzj+sYdmQg/g5ljeTLAFDI17qtNUobzP4bTL5wyPfSFevP251CIcsP5U+A0
J8YVT3yL+YRzpxu5sDt8dXXUABy8ifY78hUsDd1K3+OLhlUiJULbjnWJ+RFc0RP8
bzcBgz2Xiccb7ig381M6MnyKkdx7eMdxL6viIf2MVPz84o7t3v3E77ER5P2JLbbO
Z8aJkrDVtRbg+DIiBjAt1sAYQJf7wMzmj7GOL0G0uHLTe/9W6Zz1OqVNfAiDdJQ7
6xxTp6Cf1NDUJ0xA7EQd5g==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
H7eF/11QDSooQ+VV/ivIkRaNtGCaNrxnQnuW8j6mFmm75dkYyf4snAZN+c+Z2rG+
unoYqQFY2XEQsArN1Rm5fvQy4oz4DZNJztn/9EXkBDgWHGba9v8R5eC1EiNj27Ny
xzs6kLTWq51eTCij3V2/J2S5fg+rUtSmMOs1Dv5UwHOdClxTg0l3nsNQXA1wHul6
lkGvgd3JVWbPg5WrTtA+ffGMd0DQp3u1r0zlv0lwr6/hhilcBsUKUMRIfAzNEcc8
yMdaVsOBv2qbg9iW6wB9Qk3vg4SJwDZ/Z6w5MEn8hRCPypMdjksF/J3Wp2wNUOck
TMkOdVd/Q6nUiLIcSggEJw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 48)
`pragma protect data_block
BzDUxvq82HEI0h6DVttYHUC87DeVfA1rqDDi6Jz5sOy0qexmlF0jJwme6w0up5vv
`pragma protect end_protected

endmodule

`timescale 1ps/1ps

module EG_LOGIC_IOTRIBUF (
  i,
  t,
  o,
  io
);

input i;      //  [Template:Input data.]
input t;      //  [Template:Input three state control signal, high=input, low=output.]
output o;     //  [Template:Output data.]
inout io;     //  [Template:Two-way signal (connect directly to top-level port).]
             
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
dkFQTw27LDzUx33wumiyp1TKxNPbAjdxSA9uQ3MAZIU/Hs7fNRUcLLjRhw+zlKFZ
Uk7ftQ+HQRl7O6+L2gcQIriuaBe1Jo28we0X4Fhu0ITsFu5oRTK9RN+UzMmfDz82
Amjwf4IWe8mxlfWIEYXtJ1wanGNHGKe25q3yymMwASc=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
tE+fw/CIsDafBo/CLriaEs6ZgU7BPtC99WM/NRLdhIclWsBNl8MLDs5xlIql03aA
b5VXJ+YMJ+DyJho6E0cBCCcXX1M8u6EKpvWshJirIN2CORb/KRIYUeaSRWDKW78N
h0BFkOJpK/tFz5K6ml5wIr+wXkvkSxrDwEZ+71h2oRA=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
L+WKu4ujZGSm8UmFkrmActRvE1Mvl7JQn1RxYqTEBnQdBhdPUHrayprZEHHuLkBH
4F9oEDR2UJaXR99QwL5fUAonCdXbwsXOrE3Rfs4BxvWWA/T5qyd8Qe2yIw/hJhI3
fFQcsbj2yfKBXwq2xH5yZgQQTs37pytfrDX/bhIUhxQQVlIGammZ3Rbdqu5w4XAp
0h+TG49ZRBTeE2kdlkp7VCFAyh46BP6nNs8NuG81CbeEqXuOMR7rwkR8Uklo5TIC
aNNrj8clLJSxTc7LZqe/RSEpEmMKe9QPdGubbUVoXkxuT+Gesv2Hvfo3TzLtwgsh
axOvIeI08mRosFjRTNr5DQ==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
K2vaY6HI4J6wOFuNQJg/dKVeky2YnGF4O7WQXc9VIRLOY9J0lxNasZqT7+9S8QkK
UfJBzQyhg/LnqxsIts7A8jMRcKHJviijkPlVEkZZO8ef6b359eChjuMz9/XPXXhK
etq/xuS1/T5ctK6Id8yACZWRHUXT1RkX/N9kq3uDLDU=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
RpoNoMse24PX1zKUAknekWr+SPJzvmoiAZZxM/s6H6VBhYPGYlMlqgOSG1mFLYkN
reZm29bU4IVOI/R93d2IjSUiF2ftQkDZBfiGiigCxNVdfROqaG75eaYueKJSk68k
Hz48vfhjnD9rUAUwG34a0HKhwQ3c1XxYPltd11M7nAlXz7xCZO3WRfpMKX7VS7eo
sytBcS6nYX64lxObuBdXFSOupRRGQkDEWQ0qR4lhXgt62KxACNoD8lqUooigBko0
rrO2Og6uPwV67trCsPUCV5Ala2iTkCJG3nxdYrxnyqlBABqdRDpurQbXwV4F2vDi
IKifyx67AImy+8Kjf/0aaA==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
FnZzrOp2YcQsCONIuGpmMXQ2jRCvH6GYzA8kMM1/S1DDb6tj+3des6rBLuhMykq1
kqwwGfgRsv3DbUFozhrc5J5xCK6oCm3+l/HpPbCMKhntPITjMyi1XZLuC5k2oh3g
w22Ck+0FHAbYBGCLljsSJxII55k2cZK0NyL/VAkvSl3fdszIdbnTuy/1gLeTVExc
rVBMGm1H/YjArnbiWFc46VynsbrMQh0y0fqMdw+M4U0v/hDcNdrsPihXyn/2ccgU
MU1ZnK9uEL4EXpAlxe7l5Q+YC76dV9O6UNo33BuX0tq2GKcfx/mJIQIUKi/d72yh
362yxvd6ez6ZAjq9r/CerQ==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 64)
`pragma protect data_block
EHNKftEwQJs25RrY+5SAo+J7UlKiEemnM+xK/UwZplwLWbccmQ7fXvCeDeKS6rJO
IZRW5b82WffRqYBmDdYj1g==
`pragma protect end_protected

endmodule
