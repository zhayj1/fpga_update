`default_nettype none
//=============================================================================
// rtl/file_table.v
//   第 2 层：文件表存储
//     - 写端口：fat32_scan 在扫描根目录时逐个写入
//     - 读端口：storage_top 用 file_index 随机访问，同步读，1 拍延迟
//
//   条目字段：
//     ft_mem : [121:120]=type  [119:88]=size(32b)  [87:0]=11 字节 8.3 原始名
//     ft_cluster : 首簇号（仅内部使用，绝不出现在公共端口 —— 需求 F-12）
//
//   存储策略：不做逐位复位（避免破坏 BRAM 推断）。有效范围由 file_total 界定，
//   storage_top 只在 ready=1 时才允许上层访问。
//
//   需求依据：F-15（FILE_MAX=240，文件表存 BRAM，资源可控）
//=============================================================================
module file_table #(
    parameter integer FILE_MAX = 240,     // 对外声明的最大条目数（0 表示不限制到 DEPTH）
    parameter integer DEPTH    = 256      // 物理深度，必须是 2 的幂且 >= FILE_MAX
)(
    input  wire        clk,

    // 写端口（扫描）
    input  wire        wr_en,
    input  wire [8:0]  wr_index,
    input  wire [87:0] wr_name,     // [87:80] = 第 0 字节(名字首字符) ... [7:0] = 第 10 字节
    input  wire [1:0]  wr_type,
    input  wire [31:0] wr_size,
    input  wire [31:0] wr_cluster,

    // 读端口（上层随机访问）
    input  wire [7:0]  rd_index,
    output reg  [87:0] rd_name,
    output reg  [1:0]  rd_type,
    output reg  [31:0] rd_size,
    output reg  [31:0] rd_cluster
);

    //-------------------------------------------------------------------------
    // 存储本体（简单双端口：写口 + 同步读口）
    //-------------------------------------------------------------------------
    reg [127:0] ft_mem     [0:DEPTH-1];
    reg [31:0]  ft_cluster [0:DEPTH-1];

    wire [8:0] widx = wr_index[8:0];

    always @(posedge clk) begin
        if (wr_en) begin
            ft_mem[widx]     <= {6'd0, wr_type, wr_size, wr_name};
            ft_cluster[widx] <= wr_cluster;
        end
    end

    always @(posedge clk) begin
        rd_name    <= ft_mem[rd_index][87:0];
        rd_type    <= ft_mem[rd_index][121:120];
        rd_size    <= ft_mem[rd_index][119:88];
        rd_cluster <= ft_cluster[rd_index];
    end

endmodule
`default_nettype wire
