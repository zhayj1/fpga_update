param([ValidateSet('syn','phy')][string]$Stage='syn',[string]$Tag='candidate',[switch]$GenerateBitstream,
      [ValidateSet('on','off','high')][string]$LutStructure='off',[string]$SynthesisTag='',
      [ValidateRange(1,999)][int]$Seed=3,
      [ValidateSet('default','routability')][string]$RouteEffort='default')
$ErrorActionPreference='Stop'
if ($Tag -notmatch '^[a-zA-Z][a-zA-Z0-9_]*$') { throw 'Invalid tag' }
if ($SynthesisTag -and $SynthesisTag -notmatch '^[a-zA-Z][a-zA-Z0-9_]*$') { throw 'Invalid synthesis tag' }
if ($SynthesisTag -and $Stage -ne 'phy') { throw 'SynthesisTag is only valid for the phy stage' }
if (!$SynthesisTag) { $SynthesisTag=$Tag }
if ($GenerateBitstream -and $Stage -ne 'phy') { throw 'Bitstream generation requires the phy stage' }
$project=Split-Path $PSScriptRoot -Parent
$baseline=Join-Path (Split-Path $project -Parent) 'music_screen_area_opt'
$template=Join-Path $baseline 'prj/td_build/timing_repair_v3_syn'
if ($Stage -eq 'phy') {$template=Join-Path $baseline 'prj/td_build/timing_repair_v3_seed3_phy'}
$run=Join-Path $project "prj/td_build/${Tag}_${Stage}"
if (Test-Path $run) {throw "Preserve existing build: $run"}
New-Item -ItemType Directory -Path $run -Force | Out-Null
$utf8=New-Object System.Text.UTF8Encoding($false)
$manifest=[System.Collections.Generic.List[object]]::new()
$prj=Get-Content (Join-Path $template 'skeleton.prj') -Raw -Encoding UTF8
$order=80
foreach($source in @('gfx/fetch_line_scene','gfx/scene_raster','gfx/fetch_writer4','gfx/scene_fade','gfx/scene_blend','gfx/px_arb5','audio/spec_window','audio/spec_bands64','audio/spec_attack18','gfx/layer_fft64','gfx/cover_pop','gfx/cover_pop_geom','gfx/attack_rings','gfx/osd_controls','gfx/osd_font_rom','gfx/osd_layer')) {
    $prj=$prj.Replace('</Verilog>',"<File Path=`"../../../rtl/$source.v`"><FileInfo><Attr Name=`"UsedInSyn`" Val=`"true`"/><Attr Name=`"UsedInP&R`" Val=`"true`"/><Attr Name=`"BelongTo`" Val=`"design_1`"/><Attr Name=`"CompileOrder`" Val=`"$order`"/></FileInfo></File></Verilog>")
    $order++
}
foreach($fontFile in @('osd_font_ch.dath','osd_font_ascii.dath')) {
    $fontData=Join-Path $project "rtl/gfx/$fontFile"
    $manifest.Add(@{path=$fontData;sha256=(Get-FileHash -LiteralPath $fontData -Algorithm SHA256).Hash})
}
$prj=[regex]::Replace($prj,'<File Path="([^"]+)"',{
    param($m)
    $path=[IO.Path]::GetFullPath((Join-Path $template $m.Groups[1].Value)).Replace($baseline,$project)
    if (!(Test-Path $path)) {throw "Missing source: $path"}
    $manifest.Add(@{path=$path;sha256=(Get-FileHash $path -Algorithm SHA256).Hash})
    '<File Path="'+$path.Replace('\','/')+'"'
})
[IO.File]::WriteAllText((Join-Path $run 'skeleton.prj'),$prj,$utf8)
$cfg=Get-Content (Join-Path $template 'settings.cfg') -Raw -Encoding UTF8
$cfg=$cfg.Replace('../../../constraints/',$project.Replace('\','/')+'/constraints/')
$cfg=$cfg.Replace('add_map_lut_struct high',"add_map_lut_struct $LutStructure")
if ($Stage -eq 'phy') {
    $syn=Join-Path $project "prj/td_build/${SynthesisTag}_syn"
    $inputs=Get-Content (Join-Path $syn 'inputs.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Implementation must use the mapping configuration recorded at synthesis.
    if ($inputs.PSObject.Properties.Name -contains 'lut_structure') {
        $LutStructure=$inputs.lut_structure
        $cfg=[regex]::Replace($cfg,'add_map_lut_struct (on|off|high)',"add_map_lut_struct $LutStructure")
    }
    foreach($item in $inputs.sources) {if ((Get-FileHash $item.path).Hash -ne $item.sha256) {throw "Changed since synthesis: $($item.path)"}}
    $cfg=$cfg.Replace('set parent ../timing_repair_v3_syn',"set parent ../${SynthesisTag}_syn")
    if (!$GenerateBitstream) {$cfg=$cfg.Replace('set end_step bitgen','set end_step opt_route')}
}
[IO.File]::WriteAllText((Join-Path $run 'settings.cfg'),$cfg,$utf8)
$tcl=Get-Content (Join-Path $template 'skeleton.tcl') -Raw -Encoding UTF8
if ($Stage -eq 'phy') {
    $tcl=$tcl.Replace('update_timing -mode final',"update_timing -mode final`n report_qor -step route -file route.qor`n report_timing_summary -file final_timing.rpt")
    if ($RouteEffort -eq 'routability') {
        $tcl=$tcl.Replace("  route`n", "  set_param route effort routability`n  route`n")
    }
}
[IO.File]::WriteAllText((Join-Path $run 'skeleton.tcl'),$tcl,$utf8)
$buildFiles=@('skeleton.prj','settings.cfg','skeleton.tcl') | ForEach-Object {
    $path=Join-Path $run $_
    @{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
$inputRecord=@{time=(Get-Date).ToString('o');stage=$Stage;seed=$Seed;lut_structure=$LutStructure;route_effort=$RouteEffort;generate_bitstream=[bool]$GenerateBitstream;sources=$manifest;build_files=$buildFiles;script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash}
if ($Stage -eq 'phy') {
    $inputRecord.synthesis_tag=$SynthesisTag
    $inputRecord.synthesis_inputs=@{path=(Join-Path $syn 'inputs.json');sha256=(Get-FileHash -LiteralPath (Join-Path $syn 'inputs.json') -Algorithm SHA256).Hash}
    $inputRecord.synthesis_netlist=@{path=(Join-Path $syn 'skeleton_gate.db');sha256=(Get-FileHash -LiteralPath (Join-Path $syn 'skeleton_gate.db') -Algorithm SHA256).Hash}
}
[IO.File]::WriteAllText((Join-Path $run 'inputs.json'),($inputRecord|ConvertTo-Json -Depth 6),$utf8)
Push-Location $run
$previousSeed=$env:PL_SEED
try {
    $env:PL_SEED="$Seed"
    & 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' skeleton.tcl *> console.log
    $expected=if($Stage -eq 'syn'){'gate.qor'}else{'route.qor'}
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $expected) -or (Get-ChildItem -Force -Filter '*.error.f').Count -gt 0) {
        Get-Content console.log -Tail 30
        throw 'TD build failed'
    }
    foreach($item in @($manifest)+@($buildFiles)) {
        if ((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash -ne $item.sha256) {throw "Input changed during build: $($item.path)"}
    }
    if ($Stage -eq 'phy' -and (!(Test-Path -LiteralPath 'final_timing.rpt') -or (Get-Item -LiteralPath 'final_timing.rpt').Length -eq 0)) {throw 'Missing final timing report'}
    $result=@{completed=(Get-Date).ToString('o');stage=$Stage;status='BUILD_COMPLETE';inputs_unchanged=$true;bitstream=$null}
    if ($GenerateBitstream) {
        $bit=Join-Path $run 'skeleton.bit'
        if (!(Test-Path -LiteralPath $bit) -or (Get-Item -LiteralPath $bit).Length -eq 0) {throw 'Missing or empty bitstream'}
        $result.bitstream=@{path=$bit;bytes=(Get-Item -LiteralPath $bit).Length;sha256=(Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash}
    }
    [IO.File]::WriteAllText((Join-Path $run 'build_result.json'),($result|ConvertTo-Json -Depth 6),$utf8)
    Get-Content $expected -Tail 30
} finally {
    $env:PL_SEED=$previousSeed
    Pop-Location
}
