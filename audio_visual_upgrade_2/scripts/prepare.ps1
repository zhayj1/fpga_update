$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$baseline=Join-Path (Split-Path $project -Parent) 'music_screen_area_opt'
$utf8=New-Object System.Text.UTF8Encoding($false)
$extra=@('fetch_line_scene','scene_fade','scene_blend','px_arb5')
$al=Get-Content (Join-Path $project 'prj/skeleton.al') -Raw
$al=$al.Replace('D:/Verilog_teacher/guoyi/pro/music_screen_area_opt/prj',($project.Replace('\','/')+'/prj'))
$order=80
foreach($name in $extra) {
    # TD uses its own XML dialect, including the literal UsedInP&R name.
    $pattern='^[ \t]*<File Path="'+[regex]::Escape("../rtl/gfx/$name.v")+'">.*?</File>\r?\n'
    $al=[regex]::Replace($al,$pattern,'',([Text.RegularExpressions.RegexOptions]::Singleline -bor [Text.RegularExpressions.RegexOptions]::Multiline))
    $entry=@"
            <File Path="../rtl/gfx/$name.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="$order" />
                </FileInfo>
            </File>
"@
    $al=$al.Replace('        </Verilog>',($entry+"`n        </Verilog>"))
    $order++
}
[IO.File]::WriteAllText((Join-Path $project 'prj/skeleton.al'),$al,$utf8)
# Existing explicit source manifest supplies the real IP dependencies.
$cfg=Get-Content (Join-Path $baseline 'sim/modelsim.json') -Raw | ConvertFrom-Json
$cfg.PSObject.Properties.Remove('tb_top')
$cfg.dut_parameters=@{SDR_CLK_MHZ=100;BW_NUM=2}
$cfg.data_files=@()
$cfg.libraries[0].sources=@($cfg.libraries[0].sources | Where-Object { !$_.path.StartsWith('tb/') -or $_.path.EndsWith('_stub.v') })
Copy-Item (Join-Path $baseline 'tb/hdmi_1_4b_transmitter_core_wrapper_stub.v') (Join-Path $project 'tb')
foreach($name in $extra) { $cfg.libraries[0].sources+=@{path="rtl/gfx/$name.v";language='verilog'} }
[IO.File]::WriteAllText((Join-Path $project 'sim/modelsim_core.json'),($cfg|ConvertTo-Json -Depth 12),$utf8)
# Board wrapper syntax/elaboration, with real PLL/ODDR models. The HDMI
# transmitter remains the existing stub; this is not a board function test.
$cfg.dut_top='work.skeleton_top'
$cfg.dut_parameters=@{}
$cfg.auxiliary_tops=@('work.glbl')
foreach($path in @('sim/vendor/eg4/eg_logic_clk.v','sim/vendor/eg4/eg_logic_io.v','sim/vendor/eg4/eg_phy_pll.v','rtl/video/lane_lvds_10_1.v','rtl/video/hdmi_phy_warpper.v','rtl/top/skeleton_top.v')) {
    $cfg.libraries[0].sources+=@{path=$path;language='verilog'}
}
[IO.File]::WriteAllText((Join-Path $project 'sim/modelsim_board_compile.json'),($cfg|ConvertTo-Json -Depth 12),$utf8)
