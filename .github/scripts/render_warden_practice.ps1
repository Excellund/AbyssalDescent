param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_warden_practice.gd' -FrameFolder 'warden_practice_frames' -ExpectedFrames 37 -PreserveProductionCanvas -MaxFrames 5000
