param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_pause_options.gd' -FrameFolder 'pause_options_frames' -ExpectedFrames 8 -PreserveProductionCanvas -MaxFrames 5000
