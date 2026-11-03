`default_nettype none
// Directory entries become resource IDs: song*8 + {BG1..3,CV1..3,WAV,LRC}.
// IDs 136 and 137 are FONT.HZK and ASC.HZK. The byte streams still come
// from the original files on the SD card; only the on-chip index changes.
module resource_catalog #(
    parameter integer MAX_SONG = 16
)(
    input wire clk, rst_n, clear,
    input wire wr_en,
    input wire [87:0] wr_name,
    input wire [1:0] wr_type,
    input wire [31:0] wr_size, wr_cluster,
    input wire [7:0] rd_index,
    output reg [31:0] rd_size, rd_cluster,
    output wire rd_valid,
    input wire [7:0] lo_index, hi_index,
    output wire lo_valid, hi_valid,
    input wire select_start,
    input wire [7:0] start_from,
    output reg select_busy, select_done,
    output wire [7:0] song_total,
    output reg [7:0] song_cur, pl_err, skip_cnt, song_max,
    output reg [7:0] nx_song,
    output wire nx_vld,
    output wire [7:0] wav_ft, bg_ft1, bg_ft2, bg_ft3,
    output wire [7:0] cv_ft1, cv_ft2, cv_ft3, lrc_ft,
    output wire lrc_vld,
    output wire [7:0] nx_bg1, nx_bg2, nx_bg3,
    output wire [7:0] nx_cv1, nx_cv2, nx_cv3, nx_wav_ft, nx_lrc_ft,
    output wire nx_lrc_vld,
    output wire font_valid, asc_valid,
    output reg [31:0] font_size, asc_size
);
    // Source BMPs are normalized by bmp_load before entering display slots.
    localparam [31:0] BG_MAX = 32'd67108864;
    localparam [31:0] CV_MAX = 32'd67108864;
    localparam [7:0] FONT_ID = 8'd136, ASC_ID = 8'd137;
    reg [63:0] descriptor [0:137];
    reg [137:0] seen, valid;
    reg [16:0] exists, too_large;

    // Full-byte ASCII checks below gate all uses of the song number.
    // For accepted digits the low nibble already is the exact decimal value.
    wire [3:0] d1 = wr_name[75:72];
    wire [3:0] d2 = wr_name[67:64];
    wire song_prefix = (wr_name[87:80] == 8'h53) &&
                       (wr_name[79:72] >= 8'h30) && (wr_name[79:72] <= 8'h39) &&
                       (wr_name[71:64] >= 8'h30) && (wr_name[71:64] <= 8'h39);
    wire [7:0] song_no = (d1 << 3) + (d1 << 1) + d2;
    wire song_ok = song_prefix && (song_no >= 8'd1) && (song_no <= MAX_SONG);
    wire bg = wr_type == 2'd0 && wr_name[63:48] == 16'h4247 &&
              wr_name[47:40] >= 8'h31 && wr_name[47:40] <= 8'h33;
    wire cv = wr_type == 2'd0 && wr_name[63:48] == 16'h4356 &&
              wr_name[47:40] >= 8'h31 && wr_name[47:40] <= 8'h33;
    wire font = wr_name == {8'h46,8'h4f,8'h4e,8'h54,8'h20,8'h20,8'h20,8'h20,8'h48,8'h5a,8'h4b};
    wire asc = wr_name == {8'h41,8'h53,8'h43,8'h20,8'h20,8'h20,8'h20,8'h20,8'h48,8'h5a,8'h4b};
    wire [2:0] group_field = wr_name[47:40] - 8'h31;
    // Accepted image suffixes make group_field 0..2, so the field cannot
    // carry into the song bits. IDs are a concatenation, not a wide adder.
    wire [2:0] resource_field = bg ? group_field :
                              cv ? 3'd3 + group_field :
                              wr_type == 2'd1 ? 3'd6 : 3'd7;
    wire [7:0] resource_id = font ? FONT_ID : asc ? ASC_ID :
                             {song_no[4:0],resource_field};
    wire matched = font || asc || (song_ok && (bg || cv ||
                    wr_type == 2'd1 || wr_type == 2'd2));
    wire within_limit = !(bg && wr_size > BG_MAX) &&
                        !(cv && wr_size > CV_MAX);
    wire first_write = wr_en && matched && !seen[resource_id];

    // Decode the fixed destination once per entry. Explicit bit enables avoid
    // variable-index read/modify/write networks for the two 138-bit flag banks.
    genvar entry;
    generate for(entry=0;entry<138;entry=entry+1) begin:g_flags
        wire hit = first_write && resource_id == entry;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin seen[entry]<=0; valid[entry]<=0; end
            else if(clear) begin seen[entry]<=0; valid[entry]<=0; end
            else if(hit) begin
                seen[entry]<=1;
                if(within_limit) valid[entry]<=1;
            end
        end
    end endgenerate

    assign rd_valid = valid[rd_index];
    assign lo_valid = valid[lo_index];
    assign hi_valid = valid[hi_index];
    assign font_valid = valid[FONT_ID];
    assign asc_valid = valid[ASC_ID];
    always @(posedge clk) begin
        {rd_cluster, rd_size} <= descriptor[rd_index];
    end

    // Duplicate resource names keep the first directory entry, including an
    // oversized first image. This preserves the old playlist's first-wins rule.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exists <= 17'd0;
            too_large <= 17'd0;
            skip_cnt <= 8'd0;
            song_max <= 8'd0;
            font_size <= 32'd0;
            asc_size <= 32'd0;
        end else if (clear) begin
            exists <= 17'd0;
            too_large <= 17'd0;
            skip_cnt <= 8'd0;
            song_max <= 8'd0;
            font_size <= 32'd0;
            asc_size <= 32'd0;
        end else if (wr_en) begin
            if (song_ok) begin
                exists[song_no] <= 1'b1;
                if (song_max < song_no) song_max <= song_no;
            end
            if (!matched) begin
                skip_cnt <= skip_cnt + 8'd1;
            end else if (!seen[resource_id]) begin
                if (!within_limit) begin
                    too_large[song_no] <= 1'b1;
                end else begin
                    descriptor[resource_id] <= {wr_cluster, wr_size};
                    if (font) font_size <= wr_size;
                    if (asc) asc_size <= wr_size;
                end
            end
        end
    end

    function [7:0] key;
        input [7:0] number;
        input [2:0] field;
        begin key = (number << 3) + {5'd0, field}; end
    endfunction
    // Reduce each song's fixed fields before selecting a song. Selecting
    // seven independent bits from the whole 138-bit directory replicated
    // large mux trees; these masks retain all fields and selection timing.
    wire [16:0] bg_ready,cv_ready,song_ready;
    genvar song;
    generate for(song=0;song<=16;song=song+1) begin:g_ready
        assign bg_ready[song]=&valid[song*8+:3];
        assign cv_ready[song]=&valid[song*8+3+:3];
        assign song_ready[song]=bg_ready[song] && cv_ready[song] &&
            valid[song*8+6] && !too_large[song];
    end endgenerate
    function playable;
        input [7:0] number;
        begin
            playable = song_ready[number];
        end
    endfunction

    reg [4:0] cursor;
    // At most sixteen songs are visited in the implemented catalog. Retain
    // the old counter width for out-of-range legacy parameter overrides.
    localparam integer COUNT_WIDTH = MAX_SONG <= 16 ? 5 : 8;
    reg [COUNT_WIDTH-1:0] total_count;
    assign song_total = total_count;
    reg [7:0] first_song;
    reg [7:0] second_song;
    reg found_next;
    wire [7:0] cursor8 = {3'd0, cursor};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            select_busy <= 1'b0;
            select_done <= 1'b0;
            total_count <= 0;
            song_cur <= 8'd0;
            nx_song <= 8'd0;
            pl_err <= 8'd0;
            cursor <= 5'd1;
            first_song <= 8'd0;
            second_song <= 8'd0;
            found_next <= 1'b0;
        end else begin
            select_done <= 1'b0;
            if (clear) begin
                select_busy <= 1'b0;
                total_count <= 0;
                song_cur <= 8'd0;
                nx_song <= 8'd0;
                pl_err <= 8'd0;
                first_song <= 8'd0;
                second_song <= 8'd0;
                found_next <= 1'b0;
            end else if (select_start && !select_busy) begin
                select_busy <= 1'b1;
                total_count <= 0;
                song_cur <= 8'd0;
                nx_song <= 8'd0;
                pl_err <= 8'd0;
                first_song <= 8'd0;
                second_song <= 8'd0;
                found_next <= 1'b0;
                cursor <= 5'd1;
            end else if (select_busy) begin
                if (exists[cursor] && !playable(cursor8) && pl_err == 8'd0) begin
                    if (too_large[cursor]) pl_err <= 8'h64;
                    else if (!bg_ready[cursor]) pl_err <= 8'h60;
                    else if (!cv_ready[cursor]) pl_err <= 8'h61;
                    else pl_err <= 8'h62;
                end
                if (playable(cursor8)) begin
                    total_count <= total_count + 1'b1;
                    if (first_song == 8'd0) first_song <= cursor8;
                    else if (second_song == 8'd0) second_song <= cursor8;
                    if (song_cur == 8'd0 && (start_from == 8'd0 || cursor8 >= start_from))
                        song_cur <= cursor8;
                    else if (song_cur != 8'd0 && !found_next) begin
                        nx_song <= cursor8;
                        found_next <= 1'b1;
                    end
                end
                if (cursor == MAX_SONG) begin
                    select_busy <= 1'b0;
                    select_done <= 1'b1;
                    if (song_max == 8'd0)
                        pl_err <= 8'h71;
                    if (song_cur == 8'd0) begin
                        if (playable(cursor8) &&
                            (start_from == 8'd0 || cursor8 >= start_from))
                            nx_song <= first_song == 8'd0 ? cursor8 : first_song;
                        else begin
                            song_cur <= first_song != 8'd0 ? first_song :
                                        playable(cursor8) ? cursor8 : 8'd0;
                            nx_song <= second_song != 8'd0 ? second_song :
                                       (first_song != 8'd0 && playable(cursor8)) ? cursor8 :
                                       first_song != 8'd0 ? first_song :
                                       playable(cursor8) ? cursor8 : 8'd0;
                        end
                    end else if (!found_next && !playable(cursor8)) begin
                        nx_song <= first_song;
                    end
                end else cursor <= cursor + 5'd1;
            end
        end
    end

    assign nx_vld = (nx_song != 8'd0);
    assign wav_ft = key(song_cur,3'd6);
    assign bg_ft1 = key(song_cur,3'd0);
    assign bg_ft2 = key(song_cur,3'd1);
    assign bg_ft3 = key(song_cur,3'd2);
    assign cv_ft1 = key(song_cur,3'd3);
    assign cv_ft2 = key(song_cur,3'd4);
    assign cv_ft3 = key(song_cur,3'd5);
    assign lrc_ft = key(song_cur,3'd7);
    assign lrc_vld = song_cur != 8'd0 && valid[lrc_ft];
    assign nx_bg1 = key(nx_song,3'd0);
    assign nx_bg2 = key(nx_song,3'd1);
    assign nx_bg3 = key(nx_song,3'd2);
    assign nx_cv1 = key(nx_song,3'd3);
    assign nx_cv2 = key(nx_song,3'd4);
    assign nx_cv3 = key(nx_song,3'd5);
    assign nx_wav_ft = key(nx_song,3'd6);
    assign nx_lrc_ft = key(nx_song,3'd7);
    assign nx_lrc_vld = nx_song != 8'd0 && valid[nx_lrc_ft];
endmodule
`default_nettype wire
