param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_relic_recovery.gd' -FrameFolder 'relic_recovery_frames' -ExpectedFrames 10 -PreserveProductionCanvas -MaxFrames 4000
