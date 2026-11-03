$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$utf8=New-Object System.Text.UTF8Encoding($false)
foreach($variant in @('physical150','physical100_trace','physical100_phase_probe','app100','full_app100')) {
    $cfg=Get-Content (Join-Path $project 'sim/modelsim_memory.json') -Raw|ConvertFrom-Json
    $params=[ordered]@{PHYSICAL=0}
    if($variant -eq 'physical150') {$params=[ordered]@{PHYSICAL=1;SDR_HALF=3.333;SDR_SHIFT=-1.666}}
    if($variant -eq 'physical100_trace') {$params=[ordered]@{SDR_HALF=5.0;SDR_SHIFT=5.0}}
    # Diagnostic only: this phase is not the board PLL configuration.
    if($variant -eq 'physical100_phase_probe') {$params=[ordered]@{SDR_HALF=5.0;SDR_SHIFT=-2.0}}
    if($variant -in @('physical100_trace','physical100_phase_probe')) {
        $cfg.tb_top='work.tb_display_memory_trace'
        $cfg.libraries[0].sources+=@{path='tb/tb_display_memory_trace.v';language='verilog'}
    }
    if($variant -eq 'full_app100') {$params=[ordered]@{PHYSICAL=0;LINES=480;COVER_LINES=320}}
    $cfg|Add-Member -NotePropertyName tb_parameters -NotePropertyValue $params
    [IO.File]::WriteAllText((Join-Path $project "sim/modelsim_${variant}.json"),($cfg|ConvertTo-Json -Depth 12),$utf8)
}
