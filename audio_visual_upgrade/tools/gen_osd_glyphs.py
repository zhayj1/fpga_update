"""Extract native 32x32/16x32 glyphs from the card's HZK fonts.

Run from the project root; output is a Verilog ROM with no runtime card reads.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHARS = "攻击检测实时声学音量色彩灵敏触发频谱强度相对饱和度比基准上限0123456789%/<>"
GLYPHS = "".join(dict.fromkeys(CHARS))
FONT = (ROOT / "card/FONT.HZK").read_bytes()
ASCII = (ROOT / "card/ASC.HZK").read_bytes()


def rows(char):
    if ord(char) < 128:
        data = ASCII[(ord(char) - 32) * 64:][:64]
        width = 16
    else:
        hi, lo = char.encode("gb2312")
        data = FONT[((hi - 0xA1) * 94 + lo - 0xA1) * 128:][:128]
        width = 32
    if len(data) != width * 4:
        raise ValueError(f"Missing source glyph: {char}")
    packed = []
    for y in range(32):
        row = data[y * (width // 8):(y + 1) * (width // 8)]
        packed.append(int.from_bytes(row, "big"))
    return packed


chinese = [0] * 1024
ascii = [0] * 512
for index, char in enumerate(GLYPHS, 1):
    if index < 30:
        chinese[index * 32:index * 32 + 32] = rows(char)
    else:
        offset = (index - 30) * 32
        ascii[offset:offset + 32] = rows(char)

assert len(GLYPHS) < 48
(ROOT / "rtl/gfx/osd_font_ch.dath").write_text(
    "\n".join(f"{value:08X}" for value in chinese) + "\n", encoding="ascii")
(ROOT / "rtl/gfx/osd_font_ascii.dath").write_text(
    "\n".join(f"{value:04X}" for value in ascii) + "\n", encoding="ascii")

lines = [
    "`default_nettype none",
    "// Native 32x32/16x32 subset from card/FONT.HZK and ASC.HZK.",
    "module osd_font_rom(input wire clk, input wire [5:0] glyph,",
    "                    input wire [4:0] row, output wire [31:0] bits);",
    "`ifdef OSD_SIM",
    '    localparam CH_FILE="rtl/gfx/osd_font_ch.dath";',
    '    localparam ASCII_FILE="rtl/gfx/osd_font_ascii.dath";',
    "`else",
    '    localparam CH_FILE="osd_font_ch.dath";',
    '    localparam ASCII_FILE="osd_font_ascii.dath";',
    "`endif",
    "    wire [31:0] chinese_bits;",
    "    wire [15:0] ascii_bits;",
    "    wire [3:0] ascii_index = glyph[3:0] - 4'd14;",
    "    reg blank_d, ascii_d;",
    "    always @(posedge clk) begin",
    "        blank_d <= glyph==6'd0;",
    "        ascii_d <= glyph>=6'd30;",
    "    end",
    "    EG_LOGIC_BRAM #(",
    "        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),",
    "        .ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),",
    "        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),",
    "        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),",
    '        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),',
    '        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),',
    '        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),',
    '        .FORCE_KEEP("OFF"),.INIT_FILE(CH_FILE),',
    '        .FILL_ALL("NONE"),.IMPLEMENT("32K")',
    "    ) u_chinese (",
    "        .dia(32'd0),.addra(10'd0),.cea(1'b0),.ocea(1'b0),",
    "        .clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),",
    "        .dib(32'd0),.addrb({glyph[4:0],row}),.ceb(1'b1),.oceb(1'b1),",
    "        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(chinese_bits)",
    "    );",
    "    EG_LOGIC_BRAM #(",
    "        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),",
    "        .ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),",
    "        .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),",
    "        .BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),",
    '        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),',
    '        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),',
    '        .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),',
    '        .FORCE_KEEP("OFF"),.INIT_FILE(ASCII_FILE),',
    '        .FILL_ALL("NONE"),.IMPLEMENT("9K")',
    "    ) u_ascii (",
    "        .dia(16'd0),.addra(9'd0),.cea(1'b0),.ocea(1'b0),",
    "        .clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b0),.doa(),",
    "        .dib(16'd0),.addrb({ascii_index,row}),.ceb(1'b1),.oceb(1'b1),",
    "        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.dob(ascii_bits)",
    "    );",
]
lines += [
    "    assign bits=blank_d ? 32'd0 : (ascii_d ? {16'd0,ascii_bits} : chinese_bits);",
    "endmodule",
    "`default_nettype wire",
    "",
]
(ROOT / "rtl/gfx/osd_font_rom.v").write_text("\n".join(lines), encoding="utf-8")
print(" ".join(f"{index}:{char}" for index, char in enumerate(GLYPHS, 1)))
