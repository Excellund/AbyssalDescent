param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_farshot.gd' -FrameFolder 'farshot_frames' -ExpectedFrames 35 -PreserveProductionCanvas -MaxFrames 10000
