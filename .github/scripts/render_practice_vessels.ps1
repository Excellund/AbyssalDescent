param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_practice_vessels.gd' -FrameFolder 'practice_vessel_frames' -ExpectedFrames 46 -PreserveProductionCanvas -MaxFrames 10000
